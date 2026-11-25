import 'dart:async';

import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/auth.dart';
import '../../domain/entities/server.dart';
import 'server_manager.dart';
import 'session_manager.dart';

/// 启动阶段（文档 #13 / #91 / #104）。
enum BootstrapStage {
  /// 未开始。
  idle,

  /// 加载本地配置。
  loadingConfig,

  /// 初始化存储。
  initializingStorage,

  /// 初始化网络。
  initializingNetwork,

  /// 恢复会话。
  restoringSession,

  /// 连接服务端。
  connectingServer,

  /// 完成。
  completed,
}

/// 启动结果：决定进入 Main 还是 Login（文档 #104）。
enum BootstrapDestination {
  /// 进入登录页。
  login,

  /// 进入主界面。
  main,
}

/// 启动状态。
final class BootstrapState {
  /// 创建状态。
  const BootstrapState({
    this.stage = BootstrapStage.idle,
    this.destination,
    this.message,
    this.error,
    this.server,
  });

  /// 当前阶段。
  final BootstrapStage stage;

  /// 目标页面（完成后才有值）。
  final BootstrapDestination? destination;

  /// 附加描述。
  final String? message;

  /// 启动过程中的非致命错误。
  final Object? error;

  /// 当前服务端。
  final ServerProfile? server;

  /// 是否已完成。
  bool get isCompleted => stage == BootstrapStage.completed;
}

/// 启动管理器（文档 #91）。
///
/// 把 `main.dart` 中的初始化逻辑集中到一处：
///
/// ```text
/// BootstrapManager
/// ├── initializeStorage()
/// ├── initializeLocale()
/// ├── initializeTheme()
/// ├── initializeNetwork()
/// ├── restoreSession()
/// └── connectServer()
/// ```
final class BootstrapManager {
  /// 创建管理器。
  BootstrapManager({
    required this.serverManager,
    required this.sessionManager,
    this.minimumSplashDuration = const Duration(milliseconds: 600),
  });

  /// 服务端管理器。
  final ServerManager serverManager;

  /// 会话管理器。
  final SessionManager sessionManager;

  /// 开屏最短展示时长（避免闪烁）。
  final Duration minimumSplashDuration;

  final StreamController<BootstrapState> _controller =
      StreamController<BootstrapState>.broadcast();

  BootstrapState _state = const BootstrapState();
  Future<BootstrapState>? _inFlight;

  /// 状态流。
  Stream<BootstrapState> get stateStream => _controller.stream;

  /// 当前状态。
  BootstrapState get state => _state;

  /// 执行启动流程（幂等：重复调用复用同一次执行）。
  Future<BootstrapState> start() {
    final existing = _inFlight;
    if (existing != null) {
      return existing;
    }
    final future = _run();
    _inFlight = future;
    return future;
  }

  Future<BootstrapState> _run() async {
    final startedAt = DateTime.now();
    try {
      _emit(const BootstrapState(stage: BootstrapStage.loadingConfig));
      await serverManager.load();

      _emit(const BootstrapState(stage: BootstrapStage.initializingStorage));
      await Future<void>.delayed(Duration.zero);

      _emit(const BootstrapState(stage: BootstrapStage.initializingNetwork));
      final server = serverManager.activeServer;

      _emit(
        BootstrapState(stage: BootstrapStage.restoringSession, server: server),
      );

      if (server == null) {
        await _finishSplash(startedAt);
        return _complete(BootstrapDestination.login);
      }

      _emit(
        BootstrapState(stage: BootstrapStage.connectingServer, server: server),
      );

      final connected = await _tryConnect(server);
      if (!connected) {
        await _finishSplash(startedAt);
        return _complete(BootstrapDestination.login);
      }

      final active = serverManager.activeServer ?? server;
      final authState = await sessionManager.restore(
        server: active,
        isSessionForServer: (session) =>
            session.serverId.isEmpty || session.serverId == active.id,
      );
      await _finishSplash(startedAt);
      return _complete(
        authState == AuthState.authenticated
            ? BootstrapDestination.main
            : BootstrapDestination.login,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'BootstrapManager',
        'bootstrap failed',
        error,
        stackTrace,
      );
      await _finishSplash(startedAt);
      final state = BootstrapState(
        stage: BootstrapStage.completed,
        destination: BootstrapDestination.login,
        error: error,
        server: serverManager.activeServer,
      );
      _emit(state);
      return state;
    } finally {
      _inFlight = null;
    }
  }

  /// 重新执行启动流程（从设置页返回登录时使用）。
  Future<BootstrapState> restart() {
    _inFlight = null;
    return start();
  }

  /// 释放资源。
  Future<void> dispose() async {
    await _controller.close();
  }

  Future<bool> _tryConnect(ServerProfile server) async {
    try {
      final result = await serverManager.testConnection(server);
      if (!result.success) {
        AppLogger.warning(
          'BootstrapManager',
          'server unavailable (${result.reason?.name}), falling back to login',
        );
        return false;
      }
      await serverManager.connect(server);
      return true;
    } on ServerError catch (error) {
      AppLogger.warning(
        'BootstrapManager',
        'server incompatible or refused: ${error.message}',
      );
      return false;
    } on Object catch (error) {
      AppLogger.warning(
        'BootstrapManager',
        'connect server failed: ${classifyConnectionFailure(error).name}',
      );
      return false;
    }
  }

  Future<void> _finishSplash(DateTime startedAt) async {
    final elapsed = DateTime.now().difference(startedAt);
    final remaining = minimumSplashDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  BootstrapState _complete(BootstrapDestination destination) {
    final state = BootstrapState(
      stage: BootstrapStage.completed,
      destination: destination,
      server: serverManager.activeServer,
    );
    _emit(state);
    return state;
  }

  void _emit(BootstrapState state) {
    _state = state;
    if (!_controller.isClosed) {
      _controller.add(state);
    }
  }
}
