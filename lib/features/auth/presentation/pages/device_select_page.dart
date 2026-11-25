import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../../../../app/app_container.dart';
import '../../../../app/navigation.dart';
import '../../../../app/route_paths.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../domain/entities/server.dart';
import '../../../../domain/services/server_manager.dart';
import '../../../../shared/states/async_state.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/app_state_views.dart';
import '../widgets/server_list_tile.dart';

/// 服务端发现 / 选择页面（文档 #12 / #53 / #57）。
///
/// 登录页的「发现内网服务器」与设置页的「切换服务器」都进入本页。
/// 页面使用**持续发现**：同时接收服务端周期广播并周期性主动探测，
/// 因此服务端稍后上线也会自动出现在列表中，不依赖「打开页面的那一次扫描」。
///
/// 页面分为两个区域：
///
/// ```text
/// ┌──────────────────────────────┐
/// │ 状态文案              [重新搜索] │  搜索结果数量 / 搜索中
/// ├──────────────────────────────┤
/// │ 搜索结果                       │  本次网络中发现的服务端（按 server_id 去重）
/// │  ├ AMMDS Test Server          │
/// │  └ ...                        │
/// │ 历史服务端                     │  仅包含「连接成功过」的服务端
/// │  └ 家里的小主机                │
/// └──────────────────────────────┘
/// ```
class DeviceSelectPage extends ConsumerStatefulWidget {
  /// 创建页面。
  const DeviceSelectPage({super.key});

  @override
  ConsumerState<DeviceSelectPage> createState() => _DeviceSelectPageState();
}

class _DeviceSelectPageState extends ConsumerState<DeviceSelectPage> {
  /// 「重新搜索」加载态的最短可见时长。
  ///
  /// UDP 探测几乎瞬时返回，若只按真实耗时切换加载态，用户完全看不到反馈，
  /// 会误以为按钮没反应；因此给加载态一个下限，让「正在搜索」可被感知。
  static const Duration _minRescanFeedback = Duration(milliseconds: 900);

  bool _initializing = true;
  bool _rescanning = false;
  bool _failed = false;

  /// 被跳过的「伪服务端」数量（如热点网关），用于给出提示。
  int _skipped = 0;

  /// 本次会话发现到的服务端（搜索结果）。
  List<ServerProfile> _results = const <ServerProfile>[];

  /// 历史服务端（连接成功过的档案）。
  List<ServerProfile> _history = const <ServerProfile>[];

  /// 管理器引用。
  ///
  /// 在 `dispose` 中访问 `ref` 是不允许的（组件即将卸载），因此提前持有。
  late final ServerManager _manager = ref.read(serverManagerProvider);

  /// 注册到服务端管理器的发现回调（停止监听时需要传入同一个引用）。
  late final void Function(ServerProfile server) _onServerFound = _mergeFound;

  @override
  void initState() {
    super.initState();
    _history = _historyOf(_manager);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startWatching());
  }

  @override
  void dispose() {
    unawaited(_manager.stopWatching(listener: _onServerFound));
    super.dispose();
  }

  /// 历史服务端：仅包含**用户连接成功过**的档案。
  ///
  /// 发现过程中落盘的档案只代表「网络里存在」，没有
  /// [ServerProfile.lastConnectedAt]，因此不会进入历史列表，
  /// 也就不会与搜索结果重复展示。
  static List<ServerProfile> _historyOf(ServerManager manager) {
    final list = manager.profiles
        .where(
          (profile) =>
              profile.lastConnectedAt != null &&
              !ServerManager.isIgnoredHost(profile.host),
        )
        .toList();
    list.sort(
      (a, b) => b.lastConnectedAt!.compareTo(a.lastConnectedAt!),
    );
    return List<ServerProfile>.unmodifiable(list);
  }

  /// 按 server_id 合并发现结果，避免同一服务端重复展示。
  void _mergeFound(ServerProfile server) {
    if (!mounted) {
      return;
    }
    if (ServerManager.isIgnoredHost(server.host)) {
      setState(() => _skipped += 1);
      return;
    }
    setState(() {
      _results = _dedupe(<ServerProfile>[
        ..._results.where((item) => item.id != server.id),
        server,
      ]);
      _failed = false;
    });
  }

  /// 按 id 去重并过滤掉需要跳过的地址。
  static List<ServerProfile> _dedupe(List<ServerProfile> items) {
    final byId = <String, ServerProfile>{};
    for (final item in items) {
      if (ServerManager.isIgnoredHost(item.host)) {
        continue;
      }
      byId[item.id] = item;
    }
    return List<ServerProfile>.unmodifiable(byId.values);
  }

  /// 搜索结果：排除已经在「历史服务端」中的条目，避免同一服务端出现两次。
  List<ServerProfile> get _visibleResults {
    final historyIds = _history.map((profile) => profile.id).toSet();
    return _results
        .where((profile) => !historyIds.contains(profile.id))
        .toList(growable: false);
  }

  Future<void> _startWatching() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _initializing = true;
      _failed = false;
    });
    try {
      await _manager.startWatching(onServerFound: _onServerFound);
      if (!mounted) {
        return;
      }
      setState(() {
        _history = _historyOf(_manager);
        _failed = _results.isEmpty && !_manager.isWatching;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _failed = true);
      AppToast.failure(context, localizeError(context, error));
    } finally {
      if (mounted) {
        setState(() => _initializing = false);
      }
    }
  }

  /// 重新搜索：立即补发一次主动探测，并保证加载态可被看见。
  ///
  /// 若监听已被意外停止（例如上一次搜索抛错），这里会重新拉起监听，
  /// 因此「移除服务器后再搜索」也能正常刷新列表。
  Future<void> _rescan() async {
    if (_rescanning) {
      return;
    }
    setState(() => _rescanning = true);
    final startedAt = DateTime.now();
    try {
      if (!_manager.isWatching) {
        await _manager.startWatching(onServerFound: _onServerFound);
      } else {
        await _manager.probeNow();
      }
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed < _minRescanFeedback) {
        await Future<void>.delayed(_minRescanFeedback - elapsed);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _history = _historyOf(_manager);
        _failed = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.failure(context, localizeError(context, error));
    } finally {
      if (mounted) {
        setState(() => _rescanning = false);
      }
    }
  }

  Future<void> _select(ServerProfile profile) async {
    // 选择服务端时真正发起一次 [ServerManager.connect]：先 GET
    // `/api/client/v1/health` 验证连通性，通过才保存为当前服务端并跳转登录页。
    // 失败时给出错误反馈并停留：避免拿着一个连不上的地址却显示「连接成功」。
    try {
      await _manager.connect(profile);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.failure(context, localizeError(context, error));
      return;
    }
    if (!mounted) {
      return;
    }
    AppToast.success(context, context.l10n.connectSuccess);
    // 把选中的服务端作为 push 返回值传回给发起方（登录页）：
    // 登录页据此把地址回填到输入框，避免「选完了地址还是空的」歧义。
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop<ServerProfile>(profile);
    } else {
      GoRouter.of(context).go(RoutePaths.login);
    }
  }

  Future<void> _remove(ServerProfile profile) async {
    await _manager.removeServer(profile.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _history = _historyOf(_manager);
      // 被移除的服务端若仍在网内，可通过「重新搜索」重新出现在搜索结果区
      _results = _results
          .where((item) => item.id != profile.id)
          .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final results = _visibleResults;
    final supported = _manager.discoverySupported;
    final busy = _initializing || _rescanning;
    return Scaffold(
      appBar: TDNavBar(
        title: l10n.selectServer,
        backgroundColor: colors.surface,
        useDefaultBack: false,
        leftBarItems: appBackBarItems(context, RoutePaths.login),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    !supported
                        ? l10n.discoveryUnsupported
                        : busy
                        ? l10n.discovering
                        : results.isEmpty
                        ? l10n.discoveryNotFound
                        : l10n.discoveryFoundCount(results.length),
                    style: AppTypography.body.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                TDButton(
                  text: l10n.rescan,
                  size: TDButtonSize.small,
                  type: TDButtonType.outline,
                  theme: TDButtonTheme.primary,
                  // 平台不支持 UDP 发现时（Web），重新搜索不可能有结果，直接禁用。
                  disabled: busy || !supported,
                  iconWidget: _rescanning
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: colors.brand,
                          ),
                        )
                      : null,
                  onTap: _rescan,
                ),
              ],
            ),
          ),
          if (_rescanning)
            LinearProgressIndicator(
              minHeight: 2,
              color: colors.brand,
              backgroundColor: colors.surfaceVariant,
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              children: <Widget>[
                _SectionHeader(
                  title: l10n.discoveryResultsTitle,
                  trailing: results.isEmpty ? null : '${results.length}',
                ),
                if (_skipped > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      l10n.discoverySkippedHint,
                      style: AppTypography.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ..._buildResults(context, results),
                const SizedBox(height: AppSpacing.lg),
                _SectionHeader(
                  title: l10n.discoveryHistoryTitle,
                  trailing: _history.isEmpty ? null : '${_history.length}',
                ),
                ..._buildHistory(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 搜索结果区内容：加载中 / 平台不支持 / 失败 / 空态 / 列表。
  List<Widget> _buildResults(BuildContext context, List<ServerProfile> results) {
    final l10n = context.l10n;
    if (results.isEmpty) {
      if (!_manager.discoverySupported) {
        return <Widget>[_EmptyHint(text: l10n.discoveryUnsupportedHint)];
      }
      if (_initializing) {
        return <Widget>[AppLoading(message: l10n.discovering)];
      }
      return <Widget>[
        _EmptyHint(
          text: _failed ? l10n.discoveryFailed : l10n.discoveryNotFound,
        ),
      ];
    }
    return <Widget>[
      for (final profile in results)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _CellCard(
            child: ServerListTile(
              profile: profile,
              selected:
                  ref.watch(serverManagerProvider).activeServer?.id ==
                  profile.id,
              onTap: () => _select(profile),
            ),
          ),
        ),
    ];
  }

  /// 历史服务端区内容：空态或列表（含移除按钮）。
  List<Widget> _buildHistory(BuildContext context) {
    final l10n = context.l10n;
    if (_history.isEmpty) {
      return <Widget>[_EmptyHint(text: l10n.discoveryHistoryEmpty)];
    }
    final activeId = ref.watch(serverManagerProvider).activeServer?.id;
    return <Widget>[
      for (final profile in _history)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _CellCard(
            child: ServerListTile(
              profile: profile,
              selected: activeId == profile.id,
              onTap: () => _select(profile),
              onRemove: () => unawaited(_remove(profile)),
            ),
          ),
        ),
    ];
  }
}

/// 单元格卡片容器：给 [TDCell] 补上圆角与裁剪。
///
/// 单元格本身不绘制圆角，单条展示时由外层容器统一给出，
/// 与组件库卡片列表的观感保持一致。
class _CellCard extends StatelessWidget {
  const _CellCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(AppRadius.lg),
    child: child,
  );
}

/// 分区标题。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: AppTypography.subtitle.copyWith(color: colors.textPrimary),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            TDTag(
              trailing!,
              theme: TDTagTheme.primary,
              size: TDTagSize.small,
              shape: TDTagShape.round,
              isLight: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// 分区为空时的说明文字。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Text(
      text,
      style: AppTypography.bodySmall.copyWith(
        color: context.appColors.textTertiary,
      ),
    ),
  );
}
