import 'package:flutter/foundation.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/storage/credential_store.dart';
import '../../../../domain/entities/auth.dart';
import '../../../../domain/entities/server.dart';
import '../../../../domain/services/server_manager.dart';
import '../../../../domain/services/session_manager.dart';

/// 登录页控制器（文档 #15 / #56 / #57 / #58）。
///
/// 承担三件事：
/// 1. **持续发现**内网服务端（服务端广播 + 客户端主动探测，见
///    [ServerManager.startWatching]），把结果交给 UI 用于预填地址；
/// 2. **记住密码**的读写（凭据只进安全存储）；
/// 3. 登录：把「地址 + 账号 + 密码」解析成服务端档案并建立会话。
///
/// UI 只负责渲染状态与转发用户意图，不处理协议与存储细节。
final class LoginController extends ChangeNotifier {
  /// 创建控制器。
  LoginController({
    required this.serverManager,
    required this.sessionManager,
    required this.credentialStore,
  });

  /// 服务端管理器。
  final ServerManager serverManager;

  /// 会话管理器。
  final SessionManager sessionManager;

  /// 「记住密码」凭据存取。
  final CredentialStore credentialStore;

  bool _disposed = false;
  bool _submitting = false;
  bool _discoveryFailed = false;
  bool _rememberPassword = false;
  List<ServerProfile> _discovered = const <ServerProfile>[];
  String? _rememberedUsername;
  String? _rememberedPassword;
  Object? _error;

  /// 是否正在搜索（尚无结果且未失败）。
  ///
  /// 持续发现模式会一直监听，因此「暂时没找到」等价于「还在找」。
  bool get discovering => _discovered.isEmpty && !_discoveryFailed;

  /// 当前平台的局域网发现能力是否可用。
  ///
  /// Web 端浏览器沙箱不支持 UDP，此值为 false；界面应改为提示用户手填地址。
  bool get discoverySupported => serverManager.discoverySupported;

  /// 是否正在提交登录。
  bool get submitting => _submitting;

  /// 当前仍没有发现任何服务端。
  bool get discoveryFailed => _discoveryFailed;

  /// 已发现的服务端。
  ///
  /// 只包含**本次会话通过网络发现到的**服务端。这里刻意不回填已保存的档案：
  /// 历史档案只代表「曾经连过」，拿它当发现结果会让登录页在完全没有搜到任何
  /// 服务端时显示「发现 N 个服务端」，与实际的发现状态矛盾。
  List<ServerProfile> get discovered => List.unmodifiable(_discovered);

  /// 已记住的用户名（未开启「记住密码」时为 null）。
  String? get rememberedUsername => _rememberedUsername;

  /// 已记住的密码（未开启「记住密码」时为 null）。
  String? get rememberedPassword => _rememberedPassword;

  /// 是否启用「记住密码」。
  bool get rememberPassword => _rememberPassword;

  /// 最近一次错误。
  Object? get error => _error;

  /// 是否可以提交登录。
  bool get canSubmit => !_submitting;

  /// 初始化：载入已记住的凭据。
  ///
  /// 发现结果不预置历史档案，只由 [_onServerFound] 在真实发现时写入
  /// （见 [discovered] 的说明）。
  Future<void> initialize() async {
    try {
      final saved = await credentialStore.read();
      if (saved != null) {
        _rememberedUsername = saved.username;
        _rememberedPassword = saved.password;
        _rememberPassword = true;
        _notify();
      }
    } on Object catch (error) {
      AppLogger.warning('LoginController', 'read remembered credentials failed', error);
    }
  }

  /// 开始持续发现（直到 [stopDiscovery]）。
  Future<void> startDiscovery() async {
    if (serverManager.isWatching) {
      return;
    }
    _discoveryFailed = false;
    _error = null;
    _notify();
    try {
      await serverManager.startWatching(onServerFound: _onServerFound);
    } on Object catch (error) {
      AppLogger.warning('LoginController', 'start discovery failed', error);
      _error = error;
      _discoveryFailed = true;
    } finally {
      _notify();
    }
  }

  /// 停止持续发现（页面销毁时调用，避免持续占用 UDP 端口与电量）。
  Future<void> stopDiscovery() async {
    try {
      await serverManager.stopWatching(listener: _onServerFound);
    } on Object catch (error) {
      AppLogger.warning('LoginController', 'stop discovery failed', error);
    }
    _discoveryFailed = _discovered.isEmpty && _error != null;
    _notify();
  }

  /// 发现回调：增量合并结果，供 UI 预填地址与展示数量。
  void _onServerFound(ServerProfile server) {
    final merged = <String, ServerProfile>{
      for (final item in _discovered) item.id: item,
      server.id: server,
    };
    _discovered = merged.values.toList(growable: false);
    _discoveryFailed = false;
    _notify();
  }

  /// 切换「记住密码」。
  ///
  /// 关闭时立即删除安全存储中的凭据；打开时在下次登录成功后写入。
  Future<void> setRememberPassword(bool value) async {
    _rememberPassword = value;
    if (!value) {
      _rememberedUsername = null;
      _rememberedPassword = null;
      try {
        await credentialStore.clear();
      } on Object catch (error) {
        AppLogger.warning('LoginController', 'clear credentials failed', error);
      }
    }
    _notify();
  }

  /// 登录。
  ///
  /// [address] 为用户在表单中填写的服务端地址；若与已发现/已保存的服务端匹配，
  /// 会复用既有档案（保留服务端下发的 `server_id`），否则按手动输入新建档案。
  Future<AuthSession?> login({
    required String address,
    required String username,
    required String password,
  }) async {
    if (_submitting) {
      return null;
    }
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty) {
      _setError(const ValidationError('Username is required'));
      return null;
    }
    if (password.isEmpty) {
      _setError(const ValidationError('Password is required'));
      return null;
    }
    final server = resolveServer(address);
    if (server == null) {
      _setError(const ValidationError('No server selected'));
      return null;
    }

    _submitting = true;
    _error = null;
    _notify();
    try {
      await serverManager.saveServer(server, makeActive: true);
      final session = await sessionManager.login(
        server: server,
        credentials: AuthCredentials(
          username: trimmedUsername,
          password: password,
        ),
      );
      await _persistCredentials(trimmedUsername, password);
      return session;
    } on Object catch (error) {
      AppLogger.warning('LoginController', 'login failed', error);
      _error = error;
      return null;
    } finally {
      _submitting = false;
      _notify();
    }
  }

  /// 把用户填写的地址解析为服务端档案。
  ///
  /// 优先复用已发现/已保存的档案（同一服务端在不同网络下 IP 可能变化，
  /// 但 `server_id` 不变，因此必须优先按端点匹配既有档案而不是直接新建）；
  /// 地址为空时回退到当前服务端。
  ServerProfile? resolveServer(String address) {
    final trimmed = address.trim();
    if (trimmed.isEmpty) {
      return serverManager.activeServer;
    }
    final parsed = ServerAddressInput.parse(trimmed);
    if (parsed == null) {
      return null;
    }
    for (final profile in serverManager.profiles) {
      if (profile.protocol == parsed.protocol &&
          profile.host == parsed.host &&
          profile.port == parsed.port) {
        return profile;
      }
    }
    return ServerManager.profileFromManualInput(address: trimmed);
  }

  /// 清除错误。
  void clearError() {
    if (_error == null) {
      return;
    }
    _error = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _persistCredentials(String username, String password) async {
    try {
      if (_rememberPassword) {
        await credentialStore.save(
          RememberedCredentials(username: username, password: password),
        );
        _rememberedUsername = username;
        _rememberedPassword = password;
        return;
      }
      await credentialStore.clear();
    } on Object catch (error) {
      AppLogger.warning('LoginController', 'persist credentials failed', error);
    }
  }

  void _setError(Object error) {
    _error = error;
    _notify();
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }
}
