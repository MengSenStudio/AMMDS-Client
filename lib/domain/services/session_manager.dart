import 'dart:async';

import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../core/storage/storage.dart';
import '../../domain/entities/auth.dart';
import '../../domain/entities/server.dart';
import '../../domain/repositories/repositories.dart';

/// 会话持久化（文档 #24 / #88）。
///
/// 令牌与用户信息只写入 [SecureStorage]，普通配置文件不承载敏感数据。
final class SessionStore {
  /// 创建实例。
  SessionStore({required this.secureStorage});

  /// 安全存储。
  final SecureStorage secureStorage;

  /// 保存会话。
  Future<void> save(AuthSession session) async {
    await secureStorage.write(
      StorageKeys.accessToken,
      session.tokens.accessToken,
    );
    final refresh = session.tokens.refreshToken;
    if (refresh == null || refresh.isEmpty) {
      await secureStorage.delete(StorageKeys.refreshToken);
    } else {
      await secureStorage.write(StorageKeys.refreshToken, refresh);
    }
    await _writeDate(
      StorageKeys.accessTokenExpiresAt,
      session.tokens.expiresAt,
    );
    await _writeDate(
      StorageKeys.refreshTokenExpiresAt,
      session.tokens.refreshExpiresAt,
    );
    await secureStorage.write(StorageKeys.sessionServerId, session.serverId);
    await secureStorage.write(
      StorageKeys.currentUser,
      _encodeUser(session.user),
    );
  }

  /// 读取会话。
  Future<AuthSession?> read() async {
    final accessToken = await secureStorage.read(StorageKeys.accessToken);
    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }
    final serverId =
        await secureStorage.read(StorageKeys.sessionServerId) ?? '';
    final user = _decodeUser(await secureStorage.read(StorageKeys.currentUser));
    return AuthSession(
      tokens: AuthTokens(
        accessToken: accessToken,
        refreshToken: await secureStorage.read(StorageKeys.refreshToken),
        expiresAt: await _readDate(StorageKeys.accessTokenExpiresAt),
        refreshExpiresAt: await _readDate(StorageKeys.refreshTokenExpiresAt),
      ),
      user: user,
      serverId: serverId,
    );
  }

  /// 清除会话（Token 失效后的状态清理，文档 #29）。
  Future<void> clear() async {
    for (final key in const <String>[
      StorageKeys.accessToken,
      StorageKeys.refreshToken,
      StorageKeys.accessTokenExpiresAt,
      StorageKeys.refreshTokenExpiresAt,
      StorageKeys.currentUser,
      StorageKeys.sessionServerId,
    ]) {
      await secureStorage.delete(key);
    }
  }

  Future<void> _writeDate(String key, DateTime? value) async {
    if (value == null) {
      await secureStorage.delete(key);
      return;
    }
    await secureStorage.write(key, value.toIso8601String());
  }

  Future<DateTime?> _readDate(String key) async {
    final raw = await secureStorage.read(key);
    if (raw == null) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  String _encodeUser(UserProfile user) {
    final buffer = StringBuffer()
      ..write(user.id)
      ..write('\u0001')
      ..write(user.username)
      ..write('\u0001')
      ..write(user.nickname ?? '')
      ..write('\u0001')
      ..write(user.avatarUrl?.toString() ?? '')
      ..write('\u0001')
      ..write(user.permissions.join(','));
    return buffer.toString();
  }

  UserProfile _decodeUser(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const UserProfile(id: '', username: '');
    }
    final parts = raw.split('\u0001');
    if (parts.length < 2) {
      return const UserProfile(id: '', username: '');
    }
    final permissions = parts.length > 4 && parts[4].isNotEmpty
        ? parts[4].split(',')
        : const <String>[];
    final avatar = parts.length > 3 && parts[3].isNotEmpty ? parts[3] : null;
    return UserProfile(
      id: parts[0],
      username: parts[1],
      nickname: parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null,
      avatarUrl: avatar == null ? null : Uri.tryParse(avatar),
      permissions: permissions,
    );
  }
}

/// 会话管理器（文档 #88 / #89 / #54 / #28）。
///
/// * 统一持有令牌，业务页面不得自行操作 Token。
/// * 刷新采用「同一时间只有一个刷新请求」的共享 Future。
/// * 刷新窗口内的请求会触发主动刷新（请求驱动，而非定时器）。
///
/// 注意：[resolveAuthRepository] 是**延迟解析**函数而不是直接依赖。
/// 因为认证仓库需要网络层，而网络层的鉴权拦截器又需要本管理器来取用/刷新令牌，
/// 若在构造期相互持有会形成环形依赖（文档 #92 的依赖入口需要保持无环）。
final class SessionManager {
  /// 创建管理器。
  SessionManager({
    required this.resolveAuthRepository,
    required this.sessionStore,
    this.refreshWindow = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 延迟解析认证仓库。
  final AuthRepository Function() resolveAuthRepository;

  /// 会话持久化。
  final SessionStore sessionStore;

  /// 提前刷新窗口。
  final Duration refreshWindow;

  /// 认证仓库（按需解析）。
  AuthRepository get authRepository => resolveAuthRepository();

  final DateTime Function() _clock;
  final StreamController<AuthState> _stateController =
      StreamController<AuthState>.broadcast();

  AuthState _state = AuthState.unknown;
  AuthSession? _session;
  ServerProfile? _server;
  Future<String?>? _refreshInFlight;
  void Function(Object error)? _onAuthenticationLost;

  /// 认证状态流。
  Stream<AuthState> get stateStream => _stateController.stream;

  /// 当前认证状态。
  AuthState get state => _state;

  /// 当前会话。
  AuthSession? get session => _session;

  /// 当前用户。
  UserProfile? get currentUser => _session?.user;

  /// 当前服务端。
  ServerProfile? get currentServer => _server;

  /// 是否已认证。
  bool isAuthenticated() =>
      _state == AuthState.authenticated && _session != null;

  /// 注册「认证彻底失效」回调（清空状态后跳转登录页）。
  void onAuthenticationLost(void Function(Object error) callback) {
    _onAuthenticationLost = callback;
  }

  /// 会话恢复（启动时调用，文档 #55）。
  ///
  /// 注意：本地存在 Token 不代表会话有效，必须实际校验。
  Future<AuthState> restore({
    required ServerProfile server,
    required bool Function(AuthSession session) isSessionForServer,
  }) async {
    _server = server;
    _setState(AuthState.checking);
    final stored = await sessionStore.read();
    if (stored == null || !isSessionForServer(stored)) {
      _session = null;
      _setState(AuthState.unauthenticated);
      return _state;
    }
    _session = stored;

    // 访问令牌已过期：先尝试刷新。
    if (stored.tokens.isExpiredAt(_clock())) {
      AppLogger.info('SessionManager', 'access token expired, refreshing');
      final refreshed = await refresh();
      if (refreshed == null) {
        _setState(AuthState.unauthenticated);
        return _state;
      }
    } else {
      // 未过期也要实际校验，不能仅凭本地 Token 判定有效（文档 #54）。
      try {
        final valid = await authRepository.validateSession(
          server: server,
          accessToken: stored.tokens.accessToken,
        );
        if (!valid) {
          final refreshed = await refresh();
          if (refreshed == null) {
            await _clearSession();
            _setState(AuthState.unauthenticated);
            return _state;
          }
        }
      } on Object catch (error) {
        // 网络问题不应直接判定会话失效，保留本地会话并标记校验中。
        AppLogger.warning(
          'SessionManager',
          'session validation failed, keeping local session',
          error,
        );
        _setState(AuthState.authenticated);
        return _state;
      }
    }

    await _refreshUserProfile();
    _setState(AuthState.authenticated);
    return _state;
  }

  /// 登录（文档 #19）。
  Future<AuthSession> login({
    required ServerProfile server,
    required AuthCredentials credentials,
  }) async {
    _server = server;
    _setState(AuthState.checking);
    try {
      final result = await authRepository.login(
        server: server,
        credentials: credentials,
      );
      final session = AuthSession(
        tokens: result.tokens,
        user: result.user,
        serverId: server.id,
      );
      _session = session;
      await sessionStore.save(session);
      _setState(AuthState.authenticated);
      return session;
    } on Object {
      _setState(AuthState.unauthenticated);
      rethrow;
    }
  }

  /// 登出（文档 #23）。
  Future<void> logout({bool notifyServer = true}) async {
    final session = _session;
    final server = _server;
    if (notifyServer && session != null && server != null) {
      try {
        await authRepository.logout(
          server: server,
          accessToken: session.tokens.accessToken,
        );
      } on Object catch (error) {
        AppLogger.warning('SessionManager', 'server logout failed', error);
      }
    }
    await _clearSession();
    _setState(AuthState.unauthenticated);
  }

  /// 读取当前访问令牌（供网络拦截器使用）。
  ///
  /// 若令牌接近过期，会在此处触发一次刷新（请求驱动，文档 #26 / #27）。
  Future<String?> currentAccessToken() async {
    final session = _session;
    if (session == null) {
      return null;
    }
    if (session.tokens.shouldRefreshAt(_clock(), refreshWindow)) {
      final refreshed = await refresh();
      return refreshed ?? session.tokens.accessToken;
    }
    return session.tokens.accessToken;
  }

  /// 刷新令牌（文档 #28：并发调用共享同一个刷新 Future）。
  Future<String?> refresh() {
    final existing = _refreshInFlight;
    if (existing != null) {
      return existing;
    }
    final future = _performRefresh();
    _refreshInFlight = future;
    return future;
  }

  Future<String?> _performRefresh() async {
    try {
      final session = _session;
      final server = _server;
      if (session == null || server == null) {
        return null;
      }
      final refreshToken = session.tokens.refreshToken;
      if (refreshToken == null || refreshToken.isEmpty) {
        AppLogger.info('SessionManager', 'no refresh token available');
        await _handleRefreshFailure(const AuthError('Missing refresh token'));
        return null;
      }
      try {
        final tokens = await authRepository.refresh(
          server: server,
          refreshToken: refreshToken,
        );
        final updated = session.copyWith(
          tokens: tokens.copyWith(
            refreshToken: tokens.refreshToken ?? refreshToken,
          ),
        );
        _session = updated;
        await sessionStore.save(updated);
        _setState(AuthState.authenticated);
        AppLogger.info('SessionManager', 'access token refreshed');
        return tokens.accessToken;
      } on Object catch (error) {
        await _handleRefreshFailure(error);
        return null;
      }
    } finally {
      _refreshInFlight = null;
    }
  }

  /// 应用回到前台时的会话检查（文档 #62 / #63）。
  Future<void> onResumed() async {
    if (_session == null) {
      return;
    }
    if (_session!.tokens.shouldRefreshAt(_clock(), refreshWindow)) {
      await refresh();
    }
  }

  /// 释放资源。
  Future<void> dispose() async {
    await _stateController.close();
  }

  Future<void> _handleRefreshFailure(Object error) async {
    AppLogger.warning('SessionManager', 'token refresh failed', error);
    await _clearSession();
    _setState(AuthState.expired);
    _onAuthenticationLost?.call(error);
  }

  Future<void> _refreshUserProfile() async {
    final session = _session;
    final server = _server;
    if (session == null || server == null) {
      return;
    }
    try {
      final user = await authRepository.fetchProfile(
        server: server,
        accessToken: session.tokens.accessToken,
      );
      final updated = session.copyWith(user: user);
      _session = updated;
      await sessionStore.save(updated);
    } on Object catch (error) {
      AppLogger.debug(
        'SessionManager',
        'profile refresh skipped: ${AppLogger.sanitize('$error')}',
      );
    }
  }

  Future<void> _clearSession() async {
    _session = null;
    await sessionStore.clear();
  }

  void _setState(AuthState state) {
    _state = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }
}
