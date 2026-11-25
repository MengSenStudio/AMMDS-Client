import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import 'app/app.dart';
import 'app/app_container.dart';
import 'core/constants/app_constants.dart';
import 'core/l10n/l10n.dart';
import 'core/logging/app_logger.dart';
import 'core/platform/desktop_shell.dart';
import 'core/storage/storage_impl.dart';

/// 应用入口。
///
/// 依据文档 #91 / #104：`main.dart` 只负责「创建依赖 + 挂载应用」，
/// 真正的初始化流程全部交给 `BootstrapManager`。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorHandlers();

  // 存储实现按平台选择：桌面 / 移动落盘，Web 使用内存实现（见 storage_impl.dart）。
  final preferencesStorage = createPreferencesStorage();
  final secureStorage = createSecureStorage();
  AppLogger.info(
    'main',
    'starting ${AppConstants.appId} ${AppConstants.appVersion} '
        '(${AppConstants.environment.name})',
  );

  // 桌面外壳（托盘图标 / 关闭即最小化 / 开机自启）只对桌面平台生效，
  // Web 与移动端为空实现，调用是安全的空操作。
  await _initializeDesktopShell();

  runApp(
    ProviderScope(
      overrides: <Override>[
        preferencesStorageProvider.overrideWithValue(preferencesStorage),
        secureStorageProvider.overrideWithValue(secureStorage),
      ],
      child: const AmmdsClientApp(),
    ),
  );
}

/// 初始化桌面外壳。
///
/// 初始化失败**不能**阻止应用启动：托盘 / 开机自启属于增强能力，
/// 失败时只记录日志，其余功能照常可用。
Future<void> _initializeDesktopShell() async {
  final l10n = _resolveShellLocalizations();
  try {
    await desktopShell.initialize(
      appName: l10n.appName,
      labels: TrayMenuLabels(
        showWindow: l10n.trayShowWindow,
        autoStartEnable: l10n.trayAutoStartEnable,
        autoStartDisable: l10n.trayAutoStartDisable,
        website: l10n.trayWebsite,
        websiteUrl: AppConstants.websiteUrl,
        help: l10n.trayHelp,
        helpUrl: AppConstants.helpUrl,
        version: l10n.trayVersion(AppConstants.appVersion),
        exit: l10n.trayExit,
      ),
    );
  } on Object catch (error, stackTrace) {
    AppLogger.error(
      'main',
      'desktop shell initialization failed',
      error,
      stackTrace,
    );
  }
}

/// 解析原生外壳使用的文案。
///
/// 托盘菜单是原生菜单，在 `runApp` 之前创建，取不到 `BuildContext`，
/// 因此按系统语言解析一次；应用内切换语言不会重建原生菜单。
AppLocalizations _resolveShellLocalizations() {
  final languageCode = PlatformDispatcher.instance.locale.languageCode;
  return lookupAppLocalizations(
    languageCode == 'en' ? const Locale('en') : const Locale('zh'),
  );
}

void _installErrorHandlers() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    AppLogger.error(
      'FlutterError',
      details.exceptionAsString(),
      details.exception,
      details.stack,
    );
    // 开发环境保留 Flutter 默认的错误界面，便于定位问题。
    if (kDebugMode) {
      previous?.call(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.fatal(
      'UncaughtException',
      'unhandled platform error',
      error,
      stack,
    );
    return true;
  };
}
