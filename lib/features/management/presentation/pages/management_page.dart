import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../../../../app/app_container.dart';
import '../../../../app/navigation.dart';
import '../../../../app/route_paths.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/api/server_dialect.dart';
import '../../../../domain/entities/auth.dart';
import '../../../../domain/entities/server.dart';
import '../../../../shared/layouts/responsive.dart';
import '../../../../shared/states/async_state.dart';
import '../../../../shared/widgets/app_feedback.dart';

/// 管理模块页面（文档 #34 / #41 / #42）。
///
/// 管理是客户端四大入口之一，承担：
///
/// * **个人信息**：账号资料、角色、登录状态与退出登录；
/// * **服务器**：当前服务端、重新发现、切换、连接测试；
/// * **应用配置**：主题、语言、日志级别、开机自启（仅桌面平台）；
/// * **关于**：版本、客户端标识与发现协议。
class ManagementPage extends ConsumerStatefulWidget {
  /// 创建页面。
  const ManagementPage({super.key});

  @override
  ConsumerState<ManagementPage> createState() => _ManagementPageState();
}

class _ManagementPageState extends ConsumerState<ManagementPage> {
  bool _testing = false;
  bool _refreshing = false;

  /// 开机自启开关状态；null 表示尚未读取完成（此时开关不可操作）。
  bool? _autoStart;

  /// 是否正在写入开机自启设置。
  bool _autoStartBusy = false;

  @override
  void initState() {
    super.initState();
    _loadAutoStart();
  }

  /// 读取当前的开机自启状态（仅桌面平台有该能力）。
  Future<void> _loadAutoStart() async {
    if (!ref.read(desktopShellProvider).isSupported) {
      return;
    }
    final enabled = await ref.read(desktopShellProvider).isAutoStartEnabled();
    if (!mounted) {
      return;
    }
    setState(() => _autoStart = enabled);
  }

  /// 写入开机自启设置：写入失败必须给出失败提示，不能静默。
  Future<void> _setAutoStart(bool enabled) async {
    if (_autoStartBusy) {
      return;
    }
    final l10n = context.l10n;
    setState(() => _autoStartBusy = true);
    try {
      await ref.read(desktopShellProvider).setAutoStart(enabled);
      if (!mounted) {
        return;
      }
      setState(() {
        _autoStart = enabled;
        _autoStartBusy = false;
      });
      AppToast.success(
        context,
        enabled ? l10n.autoStartEnabled : l10n.autoStartDisabled,
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _autoStartBusy = false);
      AppLogger.warning('ManagementPage', 'set auto start failed', error);
      AppToast.failure(context, l10n.autoStartFailed);
    }
  }

  Future<void> _refreshProfile() async {
    final session = ref.read(sessionManagerProvider);
    final server = session.currentServer;
    if (server == null || !session.isAuthenticated()) {
      AppToast.warning(context, context.l10n.profileGuest);
      return;
    }
    setState(() => _refreshing = true);
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .fetchProfile(
            server: server,
            accessToken: session.session!.tokens.accessToken,
          );
      final current = session.session!;
      await ref.read(sessionStoreProvider).save(current.copyWith(user: user));
      if (!mounted) {
        return;
      }
      AppToast.success(context, context.l10n.profileRefreshSuccess);
      setState(() {});
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.failure(context, localizeError(context, error));
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _testConnection() async {
    final server = ref.read(activeServerProvider).value;
    if (server == null) {
      AppToast.warning(context, context.l10n.noServerConfigured);
      return;
    }
    setState(() => _testing = true);
    final result = await ref.read(serverManagerProvider).testConnection(server);
    if (!mounted) {
      return;
    }
    setState(() => _testing = false);
    if (result.success) {
      AppToast.success(context, context.l10n.serverConnectionSuccess);
      return;
    }
    AppToast.failure(
      context,
      localizeConnectionFailure(context, result.reason),
    );
  }

  Future<void> _logout() async {
    final l10n = context.l10n;
    final confirmed = await AppDialog.confirm(
      context,
      title: l10n.logoutConfirmTitle,
      content: l10n.logoutConfirmMessage,
      confirmText: l10n.confirm,
      cancelText: l10n.cancel,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await ref.read(sessionManagerProvider).logout();
    if (!mounted) {
      return;
    }
    AppToast.success(context, l10n.logoutSuccess);
    context.go(RoutePaths.login);
  }

  Future<void> _setLogLevel(LogLevel level) async {
    AppLogger.minimumLogLevel = level;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final session = ref.watch(sessionManagerProvider);
    final user = session.currentUser;
    final server = ref.watch(activeServerProvider).value;

    return Scaffold(
      appBar: TDNavBar(
        title: l10n.managementTitle,
        backgroundColor: colors.surface,
        // 管理页由页面右上角头像 push 进入；深链直接进入时回退到影视列表。
        useDefaultBack: false,
        leftBarItems: appBackBarItems(context, RoutePaths.media),
      ),
      body: ResponsiveBuilder(
        builder: (context, size) => ListView(
          padding: EdgeInsets.symmetric(
            horizontal: size.isMobile ? AppSpacing.lg : AppSpacing.xl,
            vertical: AppSpacing.lg,
          ),
          children: <Widget>[
            _SectionCard(
              title: l10n.managementProfile,
              subtitle: l10n.managementProfileDesc,
              trailing: TDButton(
                text: l10n.profileRefresh,
                size: TDButtonSize.small,
                type: TDButtonType.text,
                theme: TDButtonTheme.primary,
                disabled: _refreshing,
                onTap: _refreshProfile,
              ),
              child: _buildProfile(context, user, session.isAuthenticated()),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionCard(
              title: l10n.managementServer,
              subtitle: l10n.managementServerDesc,
              child: _buildServer(context, server),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionCard(
              title: l10n.managementApp,
              subtitle: l10n.managementAppDesc,
              child: _buildAppSettings(context),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionCard(
              title: l10n.managementAbout,
              child: _buildAbout(context, server),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }

  Widget _buildProfile(
    BuildContext context,
    UserProfile? user,
    bool authenticated,
  ) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final displayName = authenticated && user != null
        ? user.displayName
        : l10n.profileGuest;
    final avatar = user?.avatarUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            SizedBox(
              width: 64,
              height: 64,
              child: ClipOval(
                child: avatar == null
                    ? Container(
                        color: colors.brandSubtle,
                        alignment: Alignment.center,
                        child: Image.asset(
                          AppAssets.logo,
                          width: 40,
                          height: 40,
                          fit: BoxFit.contain,
                        ),
                      )
                    : Image.network(
                        avatar.toString(),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: colors.brandSubtle,
                          alignment: Alignment.center,
                          child: Icon(
                            TDIcons.user,
                            color: colors.brand,
                            size: 28,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    displayName,
                    style: AppTypography.title.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    authenticated
                        ? (user?.username ?? l10n.unknown)
                        : l10n.settingsSignedOut,
                    style: AppTypography.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _InfoRow(label: l10n.profileUsername, value: user?.username),
        _InfoRow(label: l10n.profileNickname, value: user?.nickname),
        _InfoRow(
          label: l10n.profileRole,
          value: _roleLabel(context, user?.role),
        ),
        _InfoRow(label: l10n.profileEmail, value: user?.email),
        _InfoRow(label: l10n.profilePhone, value: user?.phone),
        _InfoRow(
          label: l10n.profileRegisteredAt,
          value: _formatTime(user?.registeredAt),
        ),
        _InfoRow(
          label: l10n.profileLastLoginAt,
          value: _formatTime(user?.lastLoginAt),
        ),
        _InfoRow(
          label: l10n.accountEnabled,
          value: authenticated
              ? (user?.enabled ?? true
                    ? l10n.accountEnabledYes
                    : l10n.accountEnabledNo)
              : null,
        ),
        if (authenticated) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          TDButton(
            text: l10n.logout,
            isBlock: true,
            type: TDButtonType.outline,
            theme: TDButtonTheme.danger,
            onTap: _logout,
          ),
        ],
      ],
    );
  }

  Widget _buildServer(BuildContext context, ServerProfile? server) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final dialect = server == null ? null : ServerDialect.fromProfile(server);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _InfoRow(label: l10n.currentServer, value: server?.displayAddress),
        _InfoRow(label: l10n.serverName, value: server?.name),
        _InfoRow(label: l10n.serverVersion, value: server?.serverVersion),
        _InfoRow(label: l10n.apiVersion, value: server?.apiVersion),
        _InfoRow(
          label: l10n.serverDialect,
          value: dialect == null
              ? null
              : dialect == ServerDialect.ammdsPublic
              ? l10n.serverDialectPublic
              : l10n.serverDialectClientV1,
        ),
        _InfoRow(
          label: l10n.httpsEnabled,
          value: server == null ? null : (server.isHttps ? l10n.yes : l10n.no),
        ),
        if (server != null && server.capabilities.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.discoveryCapabilities,
            style: AppTypography.caption.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: server.capabilities.entries
                .where((entry) => entry.value)
                .map(
                  (entry) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      _capabilityLabel(context, entry.key),
                      style: AppTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            TDButton(
              text: _testing
                  ? l10n.serverConnectionTesting
                  : l10n.serverConnectionTest,
              size: TDButtonSize.small,
              type: TDButtonType.outline,
              theme: TDButtonTheme.primary,
              disabled: _testing,
              onTap: _testConnection,
            ),
            TDButton(
              text: l10n.serverSwitchNow,
              size: TDButtonSize.small,
              type: TDButtonType.outline,
              theme: TDButtonTheme.primary,
              // 服务端发现页是子页面，必须 push，否则返回时无路可退。
              onTap: () => context.push(RoutePaths.deviceDiscovery),
            ),
            TDButton(
              text: l10n.serverDiscoverNow,
              size: TDButtonSize.small,
              type: TDButtonType.text,
              theme: TDButtonTheme.primary,
              onTap: () => context.push(RoutePaths.deviceDiscovery),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAppSettings(BuildContext context) {
    final l10n = context.l10n;
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final currentLevel = AppLogger.minimumLogLevel;
    // 开机自启是桌面专属能力：Web 与移动端不展示该设置项。
    final shell = ref.watch(desktopShellProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (shell.isSupported) _buildAutoStartRow(context),
        _ChoiceRow(
          label: l10n.appTheme,
          options: <_Choice>[
            _Choice(
              l10n.themeFollowSystem,
              themeMode == ThemeMode.system,
              () =>
                  ref.read(themeModeProvider.notifier).update(ThemeMode.system),
            ),
            _Choice(
              l10n.themeLight,
              themeMode == ThemeMode.light,
              () =>
                  ref.read(themeModeProvider.notifier).update(ThemeMode.light),
            ),
            _Choice(
              l10n.themeDark,
              themeMode == ThemeMode.dark,
              () => ref.read(themeModeProvider.notifier).update(ThemeMode.dark),
            ),
          ],
        ),
        _ChoiceRow(
          label: l10n.appLanguage,
          options: <_Choice>[
            _Choice(
              l10n.themeFollowSystem,
              locale == null,
              () => ref.read(localeProvider.notifier).update(null),
            ),
            _Choice(
              l10n.languageChinese,
              locale?.languageCode == 'zh',
              () =>
                  ref.read(localeProvider.notifier).update(const Locale('zh')),
            ),
            _Choice(
              l10n.languageEnglish,
              locale?.languageCode == 'en',
              () =>
                  ref.read(localeProvider.notifier).update(const Locale('en')),
            ),
          ],
        ),
        _ChoiceRow(
          label: l10n.appLogLevel,
          options: <_Choice>[
            _Choice(
              l10n.logLevelDebug,
              currentLevel == LogLevel.debug,
              () => _setLogLevel(LogLevel.debug),
            ),
            _Choice(
              l10n.logLevelInfo,
              currentLevel == LogLevel.info,
              () => _setLogLevel(LogLevel.info),
            ),
            _Choice(
              l10n.logLevelWarning,
              currentLevel == LogLevel.warning,
              () => _setLogLevel(LogLevel.warning),
            ),
            _Choice(
              l10n.logLevelError,
              currentLevel == LogLevel.error,
              () => _setLogLevel(LogLevel.error),
            ),
          ],
        ),
      ],
    );
  }

  /// 开机自启开关行。
  ///
  /// 标签宽度与 [_ChoiceRow] / [_InfoRow] 对齐；
  /// 读取完成前与写入过程中开关不可操作，避免界面状态与实际写入不一致。
  Widget _buildAutoStartRow(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              l10n.autoStart,
              style: AppTypography.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          TDSwitch(
            isOn: _autoStart ?? false,
            size: TDSwitchSize.small,
            enable: _autoStart != null && !_autoStartBusy,
            onChanged: (next) {
              _setAutoStart(next);
              return next;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAbout(BuildContext context, ServerProfile? server) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _InfoRow(
          label: l10n.aboutClientVersion,
          value: AppConstants.appVersion,
        ),
        _InfoRow(label: l10n.aboutClientId, value: AppConstants.appId),
        _InfoRow(label: l10n.aboutProtocol, value: l10n.aboutProtocolValue),
        _InfoRow(label: l10n.aboutLicense, value: l10n.aboutLicenseValue),
        _InfoRow(label: l10n.aboutProject, value: l10n.aboutProjectValue),
        if (server != null)
          _InfoRow(label: l10n.serverVersion, value: server.serverVersion),
      ],
    );
  }

  static String? _formatTime(DateTime? value) {
    if (value == null) {
      return null;
    }
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static String? _roleLabel(BuildContext context, String? role) {
    if (role == null || role.isEmpty) {
      return null;
    }
    final l10n = context.l10n;
    return switch (role.toUpperCase()) {
      'ADMIN' || 'SUPERADMIN' => l10n.roleAdmin,
      'USER' => l10n.roleUser,
      _ => role,
    };
  }

  static String _capabilityLabel(BuildContext context, String capability) {
    final l10n = context.l10n;
    return switch (capability.toLowerCase()) {
      'media' => l10n.capabilityMedia,
      'people' => l10n.capabilityPeople,
      'novel' || 'novels' => l10n.capabilityNovel,
      'comic' || 'comics' => l10n.capabilityComic,
      _ => capability,
    };
  }
}

/// 管理页分组卡片。
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LayoutBuilder(
            builder: (context, constraints) {
              final titleBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: AppTypography.title.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: AppTypography.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                ],
              );
              final action = trailing;
              if (action == null) {
                return titleBlock;
              }
              // 窄屏（手机）下把操作按钮换行到标题下方，避免横向溢出。
              if (constraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    titleBlock,
                    const SizedBox(height: AppSpacing.sm),
                    action,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: titleBlock),
                  const SizedBox(width: AppSpacing.md),
                  action,
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// 标签 + 取值行。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final text = (value == null || value!.isEmpty)
        ? context.l10n.profileNotAvailable
        : value!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单选项。
class _Choice {
  const _Choice(this.label, this.selected, this.onSelect);

  final String label;
  final bool selected;
  final VoidCallback onSelect;
}

/// 一组互斥选项。
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.label, required this.options});

  final String label;
  final List<_Choice> options;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: options
                  .map(
                    (option) => InkWell(
                      onTap: option.onSelect,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: option.selected
                              ? colors.brandSubtle
                              : colors.surfaceVariant,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: option.selected
                                ? colors.brand
                                : colors.divider,
                          ),
                        ),
                        child: Text(
                          option.label,
                          style: AppTypography.caption.copyWith(
                            color: option.selected
                                ? colors.brand
                                : colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}
