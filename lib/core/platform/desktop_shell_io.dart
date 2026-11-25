import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../constants/app_assets.dart';
import '../constants/app_constants.dart';
import '../logging/app_logger.dart';
import 'desktop_shell.dart';

/// 桌面外壳实现（IO 平台）。
///
/// * 窗口：`window_manager` 拦截关闭事件并隐藏窗口，托盘菜单可重新显示；
/// * 托盘：`tray_manager` 的原生 API（`TrayIcon` / `Menu` / `MenuItem`）；
/// * 开机自启：`launch_at_startup`，Windows 写入注册表 `Run` 项。
///
/// Android / iOS 同样编译本文件（它们没有 `dart:library.js_interop` 分支），
/// 但 [isSupported] 为 false，所有能力退化为空操作。
final class DesktopShellIo with WindowListener implements DesktopShell {
  /// 日志标签。
  static const String _logTag = 'DesktopShell';

  /// 托盘图标在托盘区显示的边长（逻辑像素；macOS 会按此缩放）。
  static const double _trayIconSize = 18;

  TrayIcon? _trayIcon;
  Menu? _contextMenu;

  /// 应用名与托盘菜单文案（[initialize] 时由调用方传入）。
  ///
  /// 菜单文案依赖开机自启的当前状态，切换后需要整份重建菜单，因此这里留存。
  String _appName = '';
  TrayMenuLabels? _labels;

  /// 已创建的菜单项与它们的监听器（`null` 表示该项只作展示、没有回调）。
  ///
  /// 必须持有引用：原生句柄在对象被回收时会释放，菜单项消失后菜单即失效；
  /// 释放时也按「先菜单项、后菜单」的顺序（与 `tray_manager` 内部一致）。
  final List<(MenuItem, ListenerId?)> _menuItems =
      <(MenuItem, ListenerId?)>[];

  /// 是否已接管原生关闭事件（接管后「关闭」= 隐藏到托盘，而非退出）。
  bool _closeIntercepted = false;

  /// 是否已完成 `launchAtStartup.setup`；未完成时开机自启不可用。
  bool _autoStartReady = false;

  /// 是否正在退出（避免关闭事件与托盘退出相互触发）。
  bool _quitting = false;

  @override
  bool get isSupported =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Future<void> initialize({
    required String appName,
    required TrayMenuLabels labels,
  }) async {
    if (!isSupported || _closeIntercepted) {
      return;
    }
    _appName = appName;
    _labels = labels;
    await windowManager.ensureInitialized();

    // 「关闭即最小化到托盘」：拦截原生关闭信号，由 [onWindowClose] 改为隐藏窗口。
    await windowManager.setPreventClose(true);
    _closeIntercepted = true;
    windowManager.addListener(this);
    await windowManager.setTitle(appName);

    // 开机自启：注册表项名使用稳定的应用标识（而非本地化名称），
    // 避免切换语言后残留旧的自启项。必须先于托盘创建完成，
    // 因为托盘菜单需要读取当前开关状态来显示「启用 / 禁用」。
    launchAtStartup.setup(
      appName: AppConstants.appId,
      appPath: Platform.resolvedExecutable,
    );
    _autoStartReady = true;

    await _createTray();

    AppLogger.info(_logTag, 'desktop shell initialized (tray + close to tray)');
  }

  @override
  Future<bool> isAutoStartEnabled() async {
    if (!_autoStartReady) {
      return false;
    }
    try {
      return await launchAtStartup.isEnabled();
    } on Object catch (error) {
      AppLogger.warning(_logTag, 'unable to read the auto start state', error);
      return false;
    }
  }

  @override
  Future<void> setAutoStart(bool enabled) async {
    if (!isSupported) {
      return;
    }
    if (!_autoStartReady) {
      throw StateError('desktop shell is not initialized: auto start');
    }
    final changed = enabled
        ? await launchAtStartup.enable()
        : await launchAtStartup.disable();
    if (!changed) {
      throw StateError('auto start was not changed to $enabled');
    }
    AppLogger.info(_logTag, 'auto start switched to $enabled');
  }

  @override
  Future<void> dispose() async {
    _disposeTray();
    if (!_closeIntercepted) {
      return;
    }
    _closeIntercepted = false;
    windowManager.removeListener(this);
    // 解除关闭拦截，否则后续的销毁会被自身拦截。
    await windowManager.setPreventClose(false);
  }

  /// 显示并聚焦主窗口（托盘左键点击与「显示主窗口」菜单项共用）。
  Future<void> showMainWindow() async {
    if (!isSupported) {
      return;
    }
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onWindowClose() {
    if (!_closeIntercepted || _quitting) {
      return;
    }
    // 用户点击关闭按钮：隐藏窗口到托盘，而不是退出应用（用户已确认该行为）。
    unawaited(windowManager.hide());
    AppLogger.info(_logTag, 'window hidden to tray instead of closing');
  }

  /// 创建托盘图标与右键菜单。
  Future<void> _createTray() async {
    if (!TrayManager.instance.isSupported()) {
      AppLogger.warning(_logTag, 'tray icon is not supported here');
      return;
    }
    final trayIcon = TrayIcon.create();
    if (trayIcon == null) {
      AppLogger.warning(_logTag, 'unable to create the tray icon');
      return;
    }
    _trayIcon = trayIcon;

    // Windows 的托盘图标由 nativeapi 交给 GDI+ 解码：`.ico` 若使用 PNG 压缩帧，
    // GDI+ 会解出一张全透明位图，托盘里就成了「有位置但空白」的图标。因此
    // Windows 使用 DIB（未压缩位图）帧的 `logo.ico`；macOS / Linux 不支持
    // `.ico`，改用同一套品牌资源的透明 PNG。
    final iconPath = Platform.isWindows
        ? AppAssets.appIcon
        : AppAssets.logoHeader;
    trayIcon
      ..icon = ImageAsset.fromAsset(iconPath)
      ..iconSize = const Size(_trayIconSize, _trayIconSize)
      ..setTooltip(_appName);

    // 左键点击托盘图标默认显示主窗口（Linux 的点击由面板接管，不会上报）。
    trayIcon.addListener((event) {
      if (event is TrayIconClickedEvent ||
          event is TrayIconDoubleClickedEvent) {
        unawaited(showMainWindow());
      }
    });

    await _refreshTrayMenu();

    trayIcon
      // 原生实现默认**不**随鼠标事件弹出菜单，必须显式指定由右键触发。
      ..setContextMenuTrigger(ContextMenuTrigger.rightClicked)
      ..setVisible(true);
  }

  /// 重建托盘右键菜单。
  ///
  /// 菜单按用途分三组（见 [TrayMenuLabels]）：主窗口 / 开机自启、官网 / 帮助 /
  /// 版本号、退出。其中「开机自启」的文案取决于当前开关状态，切换后需要
  /// 整份重建——这样就不依赖原生菜单项自身的可变文案能力。
  Future<void> _refreshTrayMenu() async {
    final trayIcon = _trayIcon;
    final labels = _labels;
    if (trayIcon == null || labels == null) {
      return;
    }
    _disposeMenu();

    final menu = Menu.create();
    if (menu == null) {
      AppLogger.warning(_logTag, 'unable to create the tray context menu');
      return;
    }
    _contextMenu = menu;

    final autoStartEnabled = await isAutoStartEnabled();
    final showWindowItem = MenuItem.createWithLabelAndType(
      labels.showWindow,
      MenuItemType.normal,
    );
    final autoStartItem = MenuItem.createWithLabelAndType(
      autoStartEnabled ? labels.autoStartDisable : labels.autoStartEnable,
      MenuItemType.normal,
    );
    final websiteItem = MenuItem.createWithLabelAndType(
      labels.website,
      MenuItemType.normal,
    );
    final helpItem = MenuItem.createWithLabelAndType(
      labels.help,
      MenuItemType.normal,
    );
    final versionItem = MenuItem.createWithLabelAndType(
      labels.version,
      MenuItemType.normal,
    );
    if (versionItem != null) {
      // 版本号只作展示，禁用点击（灰色显示，原生菜单的标准 disabled 样式）。
      versionItem.isEnabled = false;
    }
    final exitItem = MenuItem.createWithLabelAndType(
      labels.exit,
      MenuItemType.normal,
    );
    if (showWindowItem == null ||
        autoStartItem == null ||
        websiteItem == null ||
        helpItem == null ||
        versionItem == null ||
        exitItem == null) {
      AppLogger.warning(_logTag, 'unable to create the tray menu items');
      return;
    }

    _menuItems.addAll(<(MenuItem, ListenerId?)>[
      (
        showWindowItem,
        showWindowItem.addListener((event) {
          if (event is MenuItemClickedEvent) {
            unawaited(showMainWindow());
          }
        }),
      ),
      (
        autoStartItem,
        autoStartItem.addListener((event) {
          if (event is MenuItemClickedEvent) {
            // 切换后要重建整份菜单，而菜单项的原生回调此刻仍在栈上：
            // 推迟到回调返回之后再重建，避免销毁正在处理点击的菜单项。
            Timer.run(() => unawaited(_toggleAutoStart()));
          }
        }),
      ),
      (
        websiteItem,
        websiteItem.addListener((event) {
          if (event is MenuItemClickedEvent) {
            unawaited(_openExternal(labels.websiteUrl));
          }
        }),
      ),
      (
        helpItem,
        helpItem.addListener((event) {
          if (event is MenuItemClickedEvent) {
            unawaited(_openExternal(labels.helpUrl));
          }
        }),
      ),
      // 「版本号」只做展示，不注册点击回调。
      (versionItem, null),
      (
        exitItem,
        exitItem.addListener((event) {
          if (event is MenuItemClickedEvent) {
            // 不在菜单项回调内直接退出：先让原生菜单完成关闭，
            // 再销毁托盘与窗口。
            Timer.run(() => unawaited(_quit()));
          }
        }),
      ),
    ]);

    menu
      ..addItem(showWindowItem)
      ..addItem(autoStartItem)
      ..addSeparator()
      ..addItem(websiteItem)
      ..addItem(helpItem)
      ..addItem(versionItem)
      ..addSeparator()
      ..addItem(exitItem);

    trayIcon.setContextMenu(menu);
  }

  /// 切换开机自启，并重建菜单让文案反映新的状态。
  ///
  /// 托盘菜单没有可用的界面反馈（原生菜单之外没有 `BuildContext`），
  /// 失败时只记录日志。
  Future<void> _toggleAutoStart() async {
    final next = !await isAutoStartEnabled();
    try {
      await setAutoStart(next);
      AppLogger.info(_logTag, 'auto start switched to $next from the tray menu');
    } on Object catch (error) {
      AppLogger.warning(
        _logTag,
        'unable to switch auto start from the tray menu',
        error,
      );
    }
    await _refreshTrayMenu();
  }

  /// 用系统默认浏览器打开链接（官网 / 帮助）。
  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object catch (error) {
      AppLogger.warning(_logTag, 'unable to open $url', error);
    }
  }

  /// 释放托盘菜单（先菜单项、后菜单，与 `tray_manager` 内部顺序一致）。
  void _disposeMenu() {
    for (final (item, listenerId) in _menuItems) {
      if (listenerId != null) {
        item.removeListener(listenerId);
      }
      item.dispose();
    }
    _menuItems.clear();
    _contextMenu?.dispose();
    _contextMenu = null;
  }

  /// 释放托盘图标与菜单。
  void _disposeTray() {
    _trayIcon?.dispose();
    _trayIcon = null;
    _disposeMenu();
  }

  /// 真正退出应用（仅由托盘菜单「退出」触发）。
  Future<void> _quit() async {
    if (_quitting) {
      return;
    }
    _quitting = true;
    AppLogger.info(_logTag, 'quitting from the tray menu');
    await dispose();
    try {
      // 关闭拦截已解除，销毁窗口即可结束进程。
      await windowManager.destroy();
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        _logTag,
        'unable to destroy the window',
        error,
        stackTrace,
      );
    } finally {
      // 兜底：窗口销毁失败时也要结束进程，避免托盘已移除却无法退出。
      exit(0);
    }
  }
}

/// 全局桌面外壳实例（应用启动时初始化一次，见 `main.dart`）。
final DesktopShell desktopShell = DesktopShellIo();
