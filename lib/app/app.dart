import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../core/l10n/l10n.dart';
import '../core/logging/app_logger.dart';
import '../core/theme/app_theme.dart';
import 'app_container.dart';
import 'app_router.dart';

/// 客户端根组件（文档 #5 / #7 / #12 / #92）。
class AmmdsClientApp extends ConsumerStatefulWidget {
  /// 创建组件。
  const AmmdsClientApp({super.key});

  @override
  ConsumerState<AmmdsClientApp> createState() => _AmmdsClientAppState();
}

class _AmmdsClientAppState extends ConsumerState<AmmdsClientApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 多主题切换需要 TDesign 显式开启（文档 #5.1）。
    TDTheme.needMultiTheme();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreferences());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // 回到前台时检查会话（文档 #62 / #63）。
      unawaited(ref.read(sessionManagerProvider).onResumed());
    }
  }

  Future<void> _loadPreferences() async {
    await ref.read(themeModeProvider.notifier).load();
    await ref.read(localeProvider.notifier).load();
    AppLogger.info('AmmdsClientApp', 'preferences loaded');
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final platformBrightness = MediaQuery.platformBrightnessOf(context);

    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) => TDTheme(
        data: AppTheme.tdesignData(themeMode, platformBrightness),
        systemData: AppTheme.systemTheme(themeMode, platformBrightness),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
