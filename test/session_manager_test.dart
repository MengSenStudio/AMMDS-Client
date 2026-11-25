import 'package:ammds_client/core/errors/app_exception.dart';
import 'package:ammds_client/core/storage/storage.dart';
import 'package:ammds_client/core/storage/storage_impl.dart';
import 'package:ammds_client/domain/entities/auth.dart';
import 'package:ammds_client/domain/entities/server.dart';
import 'package:ammds_client/domain/repositories/repositories.dart';
import 'package:ammds_client/domain/services/session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

const ServerProfile _server = ServerProfile(
  id: 'srv-1',
  name: 'Test',
  host: '127.0.0.1',
  port: 8080,
);

UserProfile _user({String username = 'admin'}) =>
    UserProfile(id: 'u1', username: username, nickname: '管理员');

AuthTokens _tokens({
  String access = 'access-1',
  String refresh = 'refresh-1',
  Duration ttl = const Duration(minutes: 30),
}) => AuthTokens(
  accessToken: access,
  refreshToken: refresh,
  expiresAt: DateTime.now().add(ttl),
);

/// 可脚本化的认证仓库。
final class FakeAuthRepository implements AuthRepository {
  int loginCalls = 0;
  int refreshCalls = 0;
  int logoutCalls = 0;
  int validateCalls = 0;
  int profileCalls = 0;

  AuthResult Function()? loginHandler;
  Future<AuthTokens> Function(String refreshToken)? refreshHandler;
  bool validateResult = true;
  Object? validateError;
  AuthTokens nextTokens = _tokens();

  @override
  Future<AuthResult> login({
    required ServerProfile server,
    required AuthCredentials credentials,
  }) async {
    loginCalls++;
    final handler = loginHandler;
    if (handler != null) {
      return handler();
    }
    return AuthResult(tokens: _tokens(), user: _user());
  }

  @override
  Future<AuthTokens> refresh({
    required ServerProfile server,
    required String refreshToken,
  }) async {
    refreshCalls++;
    final handler = refreshHandler;
    if (handler != null) {
      return handler(refreshToken);
    }
    return nextTokens;
  }

  @override
  Future<void> logout({
    required ServerProfile server,
    required String accessToken,
  }) async {
    logoutCalls++;
  }

  @override
  Future<UserProfile> fetchProfile({
    required ServerProfile server,
    required String accessToken,
  }) async {
    profileCalls++;
    return _user();
  }

  @override
  Future<bool> validateSession({
    required ServerProfile server,
    required String accessToken,
  }) async {
    validateCalls++;
    final error = validateError;
    if (error != null) {
      throw error;
    }
    return validateResult;
  }
}

void main() {
  late FakeAuthRepository repository;
  late InMemorySecureStorage secureStorage;
  late SessionStore store;
  late SessionManager manager;

  setUp(() {
    repository = FakeAuthRepository();
    secureStorage = InMemorySecureStorage();
    store = SessionStore(secureStorage: secureStorage);
    manager = SessionManager(
      resolveAuthRepository: () => repository,
      sessionStore: store,
      refreshWindow: const Duration(seconds: 60),
    );
  });

  tearDown(() async {
    await manager.dispose();
  });

  group('SessionManager 登录与登出', () {
    test('登录成功后进入 authenticated 并持久化令牌', () async {
      final session = await manager.login(
        server: _server,
        credentials: const AuthCredentials(
          username: 'admin',
          password: 'secret',
        ),
      );
      expect(session.tokens.accessToken, 'access-1');
      expect(manager.state, AuthState.authenticated);
      expect(manager.isAuthenticated(), isTrue);
      expect(manager.currentUser?.username, 'admin');
      expect(await secureStorage.read(StorageKeys.accessToken), 'access-1');
      expect(await secureStorage.read(StorageKeys.refreshToken), 'refresh-1');
    });

    test('登录失败回到 unauthenticated 并抛出原始错误', () async {
      repository.loginHandler = () => throw const AuthError('bad credentials');
      await expectLater(
        manager.login(
          server: _server,
          credentials: const AuthCredentials(username: 'a', password: 'b'),
        ),
        throwsA(isA<AuthError>()),
      );
      expect(manager.state, AuthState.unauthenticated);
      expect(manager.session, isNull);
    });

    test('登出会通知服务端并清理本地认证信息', () async {
      await manager.login(
        server: _server,
        credentials: const AuthCredentials(username: 'a', password: 'b'),
      );
      await manager.logout();
      expect(repository.logoutCalls, 1);
      expect(manager.session, isNull);
      expect(manager.state, AuthState.unauthenticated);
      expect(await secureStorage.read(StorageKeys.accessToken), isNull);
      expect(await secureStorage.read(StorageKeys.currentUser), isNull);
    });

    test('登出时服务端异常不影响本地清理', () async {
      await manager.login(
        server: _server,
        credentials: const AuthCredentials(username: 'a', password: 'b'),
      );
      await manager.logout(notifyServer: false);
      expect(repository.logoutCalls, 0);
      expect(manager.session, isNull);
    });
  });

  group('SessionManager 令牌刷新', () {
    test('并发刷新只产生一次真实请求（共享 Future）', () async {
      await manager.login(
        server: _server,
        credentials: const AuthCredentials(username: 'a', password: 'b'),
      );
      repository.nextTokens = _tokens(access: 'access-2', refresh: 'refresh-2');

      final results = await Future.wait<String?>(<Future<String?>>[
        manager.refresh(),
        manager.refresh(),
        manager.refresh(),
        manager.refresh(),
        manager.refresh(),
      ]);

      expect(repository.refreshCalls, 1, reason: '同一时间只允许一个刷新请求');
      expect(results, everyElement('access-2'));
      expect(manager.session?.tokens.accessToken, 'access-2');
      expect(await secureStorage.read(StorageKeys.accessToken), 'access-2');
    });

    test('刷新完成后可以再次刷新', () async {
      await manager.login(
        server: _server,
        credentials: const AuthCredentials(username: 'a', password: 'b'),
      );
      await manager.refresh();
      expect(repository.refreshCalls, 1);
      await manager.refresh();
      expect(repository.refreshCalls, 2);
    });

    test('访问令牌接近过期时 currentAccessToken 主动刷新', () async {
      repository.loginHandler = () => AuthResult(
        tokens: _tokens(ttl: const Duration(seconds: 10)),
        user: _user(),
      );
      await manager.login(
        server: _server,
        credentials: const AuthCredentials(username: 'a', password: 'b'),
      );
      repository.nextTokens = _tokens(access: 'access-fresh');
      final token = await manager.currentAccessToken();
      expect(repository.refreshCalls, 1);
      expect(token, 'access-fresh');
    });

    test('令牌充足时不触发刷新', () async {
      await manager.login(
        server: _server,
        credentials: const AuthCredentials(username: 'a', password: 'b'),
      );
      final token = await manager.currentAccessToken();
      expect(repository.refreshCalls, 0);
      expect(token, 'access-1');
    });

    test('刷新失败会清理会话并触发认证失效回调', () async {
      final lost = <Object>[];
      manager.onAuthenticationLost(lost.add);
      await manager.login(
        server: _server,
        credentials: const AuthCredentials(username: 'a', password: 'b'),
      );
      repository.refreshHandler = (token) async =>
          throw const AuthError('refresh token expired');

      final result = await manager.refresh();

      expect(result, isNull);
      expect(lost, hasLength(1));
      expect(manager.session, isNull);
      expect(manager.state, AuthState.expired);
      expect(await secureStorage.read(StorageKeys.accessToken), isNull);
    });

    test('缺少刷新令牌时直接判定失效', () async {
      await manager.login(
        server: _server,
        credentials: const AuthCredentials(username: 'a', password: 'b'),
      );
      // 手动构造一个没有 refreshToken 的会话。
      final session = manager.session!;
      manager = SessionManager(
        resolveAuthRepository: () => repository,
        sessionStore: store,
        refreshWindow: const Duration(seconds: 60),
      );
      await manager.login(
        server: _server,
        credentials: const AuthCredentials(username: 'a', password: 'b'),
      );
      expect(session.tokens.refreshToken, isNotNull);

      await manager.logout(notifyServer: false);
      await manager.restore(server: _server, isSessionForServer: (_) => true);
      expect(manager.state, AuthState.unauthenticated);
    });
  });

  group('SessionManager 会话恢复', () {
    test('本地无会话时进入 unauthenticated', () async {
      final state = await manager.restore(
        server: _server,
        isSessionForServer: (_) => true,
      );
      expect(state, AuthState.unauthenticated);
      expect(repository.validateCalls, 0);
    });

    test('本地会话有效时进入 authenticated 并校验服务端', () async {
      await store.save(
        AuthSession(tokens: _tokens(), user: _user(), serverId: _server.id),
      );
      final state = await manager.restore(
        server: _server,
        isSessionForServer: (session) => session.serverId == _server.id,
      );
      expect(state, AuthState.authenticated);
      expect(repository.validateCalls, 1);
      expect(repository.profileCalls, 1);
    });

    test('会话属于其他服务端时视为未认证', () async {
      await store.save(
        AuthSession(tokens: _tokens(), user: _user(), serverId: 'other-server'),
      );
      final state = await manager.restore(
        server: _server,
        isSessionForServer: (session) => session.serverId == _server.id,
      );
      expect(state, AuthState.unauthenticated);
      expect(repository.validateCalls, 0);
    });

    test('校验失败但刷新成功时保持已认证', () async {
      await store.save(
        AuthSession(tokens: _tokens(), user: _user(), serverId: _server.id),
      );
      repository.validateResult = false;
      repository.nextTokens = _tokens(access: 'access-2');

      final state = await manager.restore(
        server: _server,
        isSessionForServer: (_) => true,
      );

      expect(state, AuthState.authenticated);
      expect(repository.refreshCalls, 1);
      expect(manager.session?.tokens.accessToken, 'access-2');
    });

    test('校验失败且刷新失败时进入未认证', () async {
      await store.save(
        AuthSession(tokens: _tokens(), user: _user(), serverId: _server.id),
      );
      repository.validateResult = false;
      repository.refreshHandler = (token) async =>
          throw const AuthError('expired');

      final state = await manager.restore(
        server: _server,
        isSessionForServer: (_) => true,
      );

      expect(state, AuthState.unauthenticated);
      expect(manager.session, isNull);
    });

    test('访问令牌已过期时先刷新再校验', () async {
      await store.save(
        AuthSession(
          tokens: _tokens(ttl: const Duration(seconds: -10)),
          user: _user(),
          serverId: _server.id,
        ),
      );
      repository.nextTokens = _tokens(access: 'access-2');

      final state = await manager.restore(
        server: _server,
        isSessionForServer: (_) => true,
      );

      expect(state, AuthState.authenticated);
      expect(repository.refreshCalls, 1);
      expect(manager.session?.tokens.accessToken, 'access-2');
    });

    test('网络异常时保留本地会话而不是强制登出', () async {
      await store.save(
        AuthSession(tokens: _tokens(), user: _user(), serverId: _server.id),
      );
      repository.validateError = const NetworkError('offline');

      final state = await manager.restore(
        server: _server,
        isSessionForServer: (_) => true,
      );

      expect(state, AuthState.authenticated);
      expect(manager.session, isNotNull);
    });
  });

  group('SessionManager 生命周期', () {
    test('回到前台时按需刷新', () async {
      repository.loginHandler = () => AuthResult(
        tokens: _tokens(ttl: const Duration(seconds: 5)),
        user: _user(),
      );
      await manager.login(
        server: _server,
        credentials: const AuthCredentials(username: 'a', password: 'b'),
      );
      repository.nextTokens = _tokens(access: 'access-resumed');
      await manager.onResumed();
      expect(repository.refreshCalls, 1);
      expect(manager.session?.tokens.accessToken, 'access-resumed');
    });

    test('未登录时回到前台不做任何请求', () async {
      await manager.onResumed();
      expect(repository.refreshCalls, 0);
    });
  });

  group('AuthTokens', () {
    test('shouldRefreshAt 覆盖刷新窗口', () {
      final now = DateTime(2026, 1, 1, 12);
      final tokens = AuthTokens(
        accessToken: 'a',
        expiresAt: now.add(const Duration(seconds: 30)),
      );
      expect(tokens.shouldRefreshAt(now, const Duration(seconds: 60)), isTrue);
      expect(tokens.shouldRefreshAt(now, const Duration(seconds: 10)), isFalse);
    });

    test('无过期时间时不主动刷新', () {
      const tokens = AuthTokens(accessToken: 'a');
      expect(
        tokens.shouldRefreshAt(DateTime.now(), const Duration(hours: 1)),
        isFalse,
      );
      expect(tokens.isExpiredAt(DateTime.now()), isFalse);
    });

    test('isExpiredAt 判定过期', () {
      final now = DateTime(2026, 1, 1, 12);
      final tokens = AuthTokens(
        accessToken: 'a',
        expiresAt: now.subtract(const Duration(seconds: 1)),
      );
      expect(tokens.isExpiredAt(now), isTrue);
    });
  });
}
