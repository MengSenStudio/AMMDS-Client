import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../../../../app/app_container.dart';
import '../../../../app/route_paths.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../domain/entities/server.dart';
import '../../../../shared/layouts/responsive.dart';
import '../../../../shared/states/async_state.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../controllers/login_controller.dart';
import '../widgets/login_settings_sheet.dart';

/// 登录页面（文档 #15 / #56 / #57 / #58）。
///
/// 布局与设计参考 `docs/设计参考/登录参考页面.png` 一致：
///
/// ```text
///                                   ⚙ 设置（右上角）
///              应用 Logo
///              应用名称
///        ┌──────────────────────┐
///        │ 服务端地址            │
///        │ 账户                 │
///        │ 密码                 │
///        └──────────────────────┘
///        记住密码        忘记密码？
///        [        登录        ]
///
///        发现内网服务器 →（进入服务端选择页）
/// ```
///
/// 服务端列表不再内嵌在登录页：发现结果用于**自动预填地址**，
/// 选择服务端则由底部的「发现内网服务器」进入独立页面完成。
class LoginPage extends ConsumerStatefulWidget {
  /// 创建页面。
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  late final LoginController _controller;
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  /// 仅在测试中用于观察页面状态（文档 #79 Widget Test）。
  @visibleForTesting
  LoginController get controller => _controller;

  @override
  void initState() {
    super.initState();
    _controller = LoginController(
      serverManager: ref.read(serverManagerProvider),
      sessionManager: ref.read(sessionManagerProvider),
      credentialStore: ref.read(credentialStoreProvider),
    );
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    unawaited(_controller.stopDiscovery());
    _controller.dispose();
    _addressController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 初始化：已保存的服务端、已记住的凭据，然后开始持续发现。
  Future<void> _bootstrap() async {
    await _controller.initialize();
    if (!mounted) {
      return;
    }
    final rememberedUsername = _controller.rememberedUsername;
    final rememberedPassword = _controller.rememberedPassword;
    if (rememberedUsername != null && rememberedUsername.isNotEmpty) {
      _usernameController.text = rememberedUsername;
    }
    if (rememberedPassword != null && rememberedPassword.isNotEmpty) {
      _passwordController.text = rememberedPassword;
    }
    _prefillAddress(
      ref.read(activeServerProvider).value?.displayAddress,
    );
    setState(() {});
    await _controller.startDiscovery();
  }

  /// 自动填入服务端地址（不会清空用户已经输入的内容）。
  void _prefillAddress(String? address) {
    if (address == null || address.isEmpty) {
      return;
    }
    if (_addressController.text.trim() == address) {
      return;
    }
    _addressController.text = address;
  }

  Future<void> _submit() async {
    final session = await _controller.login(
      address: _addressController.text,
      username: _usernameController.text,
      password: _passwordController.text,
    );
    if (!mounted) {
      return;
    }
    if (session != null) {
      context.go(RoutePaths.media);
      return;
    }
    final error = _controller.error;
    if (error is ValidationError) {
      AppToast.warning(context, _validationMessage(error));
      return;
    }
    AppToast.failure(context, localizeError(context, error));
  }

  String _validationMessage(ValidationError error) {
    final l10n = context.l10n;
    return switch (error.message) {
      'Username is required' => l10n.authErrorUsernameRequired,
      'Password is required' => l10n.authErrorPasswordRequired,
      'No server selected' => l10n.missingServerAddress,
      _ => l10n.validationError,
    };
  }

  /// 打开「忘记密码」底部面板。
  ///
  /// 与右上角设置使用同一种承载方式（底部弹窗），而不是弹出的对话框，
  /// 保证登录页的两种辅助信息入口形态一致。
  Future<void> _showForgotPassword() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ForgotPasswordSheet(),
  );

  @override
  Widget build(BuildContext context) {
    // 发现到新的服务端、或从服务端选择页返回时，自动同步地址输入框。
    // 去掉 id 比较：同一服务端在不同网卡下应答 host 变了（id 不变），
    // 也应该把新的可访问地址刷进去；_prefillAddress 内部已有相同地址去重。
    ref.listen<AsyncValue<ServerProfile?>>(activeServerProvider, (
      previous,
      next,
    ) {
      final server = next.value;
      if (server != null) {
        _prefillAddress(server.displayAddress);
      }
    });

    return Scaffold(
      body: Stack(
        children: <Widget>[
          const _LoginBackground(),
          SafeArea(
            child: ResponsiveBuilder(
              builder: (context, size) => size.isDesktop
                  ? _buildWideLayout(context)
                  : _buildCompactLayout(context),
            ),
          ),
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: IconButton(
              tooltip: context.l10n.loginSettingsTitle,
              icon: Icon(
                TDIcons.setting,
                size: 22,
                color: context.appColors.textSecondary,
              ),
              onPressed: () => showLoginSettingsSheet(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 紧凑布局（手机）：单列居中卡片，卡片内自带品牌区。
  Widget _buildCompactLayout(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _buildCard(context, showBrand: true),
          ),
        ),
      ),
    );
  }

  /// 宽屏布局（桌面 / 平板）：左侧品牌区 + 右侧登录卡片。
  ///
  /// 品牌区使用 [AppAssets.loginBanner]（透明背景、图标 + 名称的上下结构），
  /// 卡片内不再重复品牌信息。
  Widget _buildWideLayout(BuildContext context) {
    return Row(
      children: <Widget>[
        const Expanded(flex: 5, child: _LoginBrandPanel()),
        Expanded(
          flex: 4,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxl,
                vertical: AppSpacing.xxl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) =>
                      _buildCard(context, showBrand: false),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 登录卡片：品牌区（窄屏）/ 表单 / 记住密码行 / 登录按钮 / 发现入口。
  Widget _buildCard(BuildContext context, {required bool showBrand}) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.overlay.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (showBrand) ...<Widget>[
            _buildHeader(context),
            const SizedBox(height: AppSpacing.xl),
          ],
          _buildForm(context),
          const SizedBox(height: AppSpacing.md),
          _buildRememberRow(context),
          const SizedBox(height: AppSpacing.lg),
          _buildLoginButton(context),
          const SizedBox(height: AppSpacing.lg),
          Divider(color: colors.divider, height: 1),
          const SizedBox(height: AppSpacing.lg),
          _buildDiscovery(context),
        ],
      ),
    );
  }

  /// 应用 Logo 与应用名称（透明背景图标，与卡片背景自然融合）。
  Widget _buildHeader(BuildContext context) {
    final colors = context.appColors;
    return Column(
      children: <Widget>[
        Image.asset(
          AppAssets.logoHeader,
          width: 72,
          height: 72,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Icon(
            TDIcons.secured,
            size: 52,
            color: colors.brand,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          context.l10n.appName,
          textAlign: TextAlign.center,
          style: AppTypography.headline.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          context.l10n.loginSubtitle,
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }

  /// 表单：服务端地址 / 账户 / 密码。
  Widget _buildForm(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 标签独立成行，避免 TDInput 的 leftLabel 固定宽度在窄屏造成溢出。
        _FieldLabel(text: l10n.serverAddress),
        TDInput(
          controller: _addressController,
          hintText: l10n.serverAddressHint,
          onChanged: (_) => _controller.clearError(),
        ),
        const SizedBox(height: AppSpacing.md),
        _FieldLabel(text: l10n.usernameLabel),
        TDInput(
          controller: _usernameController,
          hintText: l10n.usernameHint,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: AppSpacing.md),
        _FieldLabel(text: l10n.passwordLabel),
        TDInput(
          controller: _passwordController,
          hintText: l10n.passwordHint,
          obscureText: _obscurePassword,
          onSubmitted: (_) => _submit(),
          rightBtn: Icon(
            _obscurePassword ? TDIcons.browse_off : TDIcons.browse,
            size: 18,
            color: context.appColors.textSecondary,
          ),
          onBtnTap: () {
            setState(() => _obscurePassword = !_obscurePassword);
          },
        ),
      ],
    );
  }

  /// 记住密码与忘记密码。
  ///
  /// 两端都用弹性布局并通过 `spaceBetween` 对齐，使「忘记密码」精确贴在
  /// 表单右边缘（与输入框右边界对齐）；窄屏（360dp）与英文长文案下
  /// 两者都会收缩而不会横向溢出。
  Widget _buildRememberRow(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Flexible(
          child: InkWell(
            onTap: () => unawaited(
              _controller.setRememberPassword(!_controller.rememberPassword),
            ),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: _controller.rememberPassword,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (value) => unawaited(
                      _controller.setRememberPassword(value ?? false),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    l10n.rememberPassword,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: TextButton(
            onPressed: _showForgotPassword,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              l10n.forgotPassword,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(color: colors.brand),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      width: double.infinity,
      child: TDButton(
        text: _controller.submitting ? l10n.loggingIn : l10n.loginButton,
        isBlock: true,
        size: TDButtonSize.large,
        theme: TDButtonTheme.primary,
        disabled: !_controller.canSubmit,
        onTap: _submit,
      ),
    );
  }

  /// 底部：发现状态 + 进入「发现内网服务器」页面。
  ///
  /// 平台不支持 UDP 发现（Web）时不再展示「正在搜索…」，而是直接说明原因，
  /// 避免用户面对一个永远不会有结果的加载态。
  Widget _buildDiscovery(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final supported = _controller.discoverySupported;
    final discovered = _controller.discovered;
    final discovering = supported && _controller.discovering;

    final (icon, color, text) = !supported
        ? (TDIcons.info_circle, colors.textTertiary, l10n.discoveryUnsupported)
        : discovering
        ? (null, colors.textTertiary, l10n.discovering)
        : discovered.isEmpty
        ? (TDIcons.error_circle, colors.warning, l10n.discoveryNotFound)
        : (TDIcons.check_circle, colors.success, l10n.discoveryFoundCount(discovered.length));

    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (icon == null)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: colors.textTertiary,
                ),
              )
            else
              Icon(icon, size: 14, color: color),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        if (!supported)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              l10n.discoveryUnsupportedHint,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          // 进入服务端选择页，并把选中的服务端作为 push 返回值接收：
          // 这样登录页可以在用户选完的当下把地址回填到输入框，
          // 不用依赖 StreamProvider 异步通知（后者有时序竞态）。
          onPressed: () async {
            final selected = await context.push<ServerProfile>(
              RoutePaths.deviceDiscovery,
            );
            if (selected is ServerProfile && mounted) {
              _prefillAddress(selected.displayAddress);
            }
          },
          icon: const Icon(TDIcons.search, size: 18),
          label: Text(l10n.discoverLanServers),
        ),
      ],
    );
  }
}

/// 「忘记密码」底部面板。
///
/// 客户端无法重置服务端账号，这里只做提示与指引。
class _ForgotPasswordSheet extends StatelessWidget {
  const _ForgotPasswordSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.forgotPasswordTitle,
              style: AppTypography.title.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.forgotPasswordMessage,
              style: AppTypography.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: TDButton(
                text: l10n.close,
                isBlock: true,
                theme: TDButtonTheme.primary,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 表单字段标签。
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(
      text,
      style: AppTypography.bodySmall.copyWith(
        color: context.appColors.textSecondary,
      ),
    ),
  );
}

/// 登录页背景：品牌渐变 + 两处柔光。
///
/// 纯色背景会显得单调，这里用品牌色与页面背景做插值渐变，
/// 再叠两个径向柔光（不使用模糊滤镜，避免每帧额外开销）。
class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Positioned.fill(
      child: Stack(
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color.lerp(colors.background, colors.brand, 0.16)!,
                  colors.background,
                  Color.lerp(colors.background, colors.brandActive, 0.1)!,
                ],
                stops: const <double>[0, 0.55, 1],
              ),
            ),
            child: const SizedBox.expand(),
          ),
          Positioned(
            top: -140,
            left: -100,
            child: _Glow(
              color: colors.brand.withValues(alpha: 0.22),
              size: 340,
            ),
          ),
          Positioned(
            bottom: -180,
            right: -120,
            child: _Glow(
              color: colors.brandHover.withValues(alpha: 0.16),
              size: 420,
            ),
          ),
        ],
      ),
    );
  }
}

/// 径向柔光圆斑。
class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: <Color>[color, color.withValues(alpha: 0)],
      ),
    ),
  );
}

/// 宽屏登录页左侧品牌区。
///
/// 使用 [AppAssets.logoHeader]（**无文字、无背景**的透明品牌图标）：
/// 品牌名与说明以文本形式单独排版，避免与图片里自带的名称重复。
/// 图标与文本整体居中，与窄屏布局（卡片内品牌区居中）保持一致。
class _LoginBrandPanel extends StatelessWidget {
  const _LoginBrandPanel();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: Image.asset(
                  AppAssets.logoHeader,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    TDIcons.secured,
                    size: 96,
                    color: colors.brand,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                context.l10n.appName,
                textAlign: TextAlign.center,
                style: AppTypography.display.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.l10n.loginSubtitle,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
