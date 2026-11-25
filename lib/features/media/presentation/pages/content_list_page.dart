import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../../../../app/app_container.dart';
import '../../../../app/navigation.dart';
import '../../../../app/route_paths.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/debouncer.dart';
import '../../../../domain/entities/content.dart';
import '../../../../domain/entities/reading.dart';
import '../../../../domain/repositories/repositories.dart';
import '../../../../shared/layouts/responsive.dart';
import '../../../../shared/states/async_state.dart';
import '../../../../shared/widgets/account_avatar_button.dart';
import '../../../../shared/widgets/app_image.dart';
import '../../../../shared/widgets/app_state_views.dart';
import '../../../../shared/widgets/content_attributes.dart';
import '../../../home/presentation/pages/main_shell.dart';
import 'media_player_page.dart';

/// 内容分页控制器（文档 #68 / #94 / #95 / #96）。
///
/// 负责首屏加载、下拉刷新、触底分页、搜索防抖。
/// 依赖「按需解析仓库」的函数而不是 Riverpod 容器，
/// 便于在单元测试中直接注入假仓库。
class ContentListController extends ChangeNotifier {
  /// 创建控制器。
  ContentListController({required this.kind, required this.repositoryResolver});

  /// 内容类型。
  final ContentKind kind;

  /// 仓库解析函数（每次请求时解析，保证使用「当前服务端」）。
  final ContentRepository Function() repositoryResolver;

  final Debouncer _debouncer = Debouncer();
  final List<ContentItem> _items = <ContentItem>[];

  bool _disposed = false;
  bool _loadingInitial = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _keyword;
  Object? _error;

  /// 数据。
  List<ContentItem> get items => List.unmodifiable(_items);

  /// 首次加载中。
  bool get loadingInitial => _loadingInitial;

  /// 正在加载更多。
  bool get loadingMore => _loadingMore;

  /// 是否还有更多。
  bool get hasMore => _hasMore;

  /// 错误。
  Object? get error => _error;

  /// 关键词。
  String? get keyword => _keyword;

  /// 是否为空。
  bool get isEmpty => _items.isEmpty && !_loadingInitial && _error == null;

  int get _pageSize => 20;

  /// 首次加载。
  Future<void> load() async {
    if (_loadingInitial) {
      return;
    }
    _loadingInitial = true;
    _error = null;
    _notify();
    try {
      final result = await _fetch(1);
      _items
        ..clear()
        ..addAll(result.items);
      _page = 1;
      _hasMore = result.hasMore;
    } on Object catch (error) {
      _error = error;
      _items.clear();
      _hasMore = false;
    } finally {
      _loadingInitial = false;
      _notify();
    }
  }

  /// 下拉刷新（文档 #95）。
  Future<void> refresh() async {
    _page = 1;
    _hasMore = true;
    await load();
  }

  /// 触底加载更多。
  Future<void> loadMore() async {
    if (_loadingMore || _loadingInitial || !_hasMore) {
      return;
    }
    _loadingMore = true;
    _notify();
    try {
      final result = await _fetch(_page + 1);
      _items.addAll(result.items);
      _page += 1;
      _hasMore = result.hasMore;
      _error = null;
    } on Object catch (error) {
      _error = error;
      _hasMore = false;
    } finally {
      _loadingMore = false;
      _notify();
    }
  }

  Future<PageResult<ContentItem>> _fetch(int page) => repositoryResolver().list(
    kind,
    cursor: '$page',
    pageSize: _pageSize,
    keyword: _keyword,
  );

  /// 搜索（防抖，文档 #96）。
  void search(String value) {
    final normalized = value.trim();
    if (normalized == (_keyword ?? '')) {
      return;
    }
    _debouncer.run(() async {
      _keyword = normalized.isEmpty ? null : normalized;
      await refresh();
    });
  }

  /// 清空搜索。
  Future<void> clearSearch() async {
    _debouncer.cancel();
    _keyword = null;
    await refresh();
  }

  /// 展开详情路由。
  String detailRoute(String id) => kind.detailRoute(id);

  @override
  void dispose() {
    _disposed = true;
    _debouncer.cancel();
    super.dispose();
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }
}

/// 内容列表页面（影视 / 人物 / 小说 / 漫画共用，文档 #37 ~ #40）。
class ContentListPage extends ConsumerStatefulWidget {
  /// 创建页面。
  const ContentListPage({
    super.key,
    required this.kind,
    required this.title,
    required this.searchHint,
    this.aspectRatio = 2 / 3,
  });

  /// 内容类型。
  final ContentKind kind;

  /// 页面标题。
  final String title;

  /// 搜索占位文案。
  final String searchHint;

  /// 封面比例。
  final double aspectRatio;

  @override
  ConsumerState<ContentListPage> createState() => _ContentListPageState();
}

class _ContentListPageState extends ConsumerState<ContentListPage> {
  late final ContentListController _controller;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = ContentListController(
      kind: widget.kind,
      repositoryResolver: () => ref.read(contentRepositoryProvider),
    );
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.load());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      _controller.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final error = _controller.error;
        return Column(
          children: <Widget>[
            _buildHeader(context),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _controller.refresh,
                child: AppStateView<void>(
                  isLoading: _controller.loadingInitial,
                  isEmpty: _controller.isEmpty,
                  error: error == null ? null : localizeError(context, error),
                  emptyMessage: (_controller.keyword ?? '').isEmpty
                      ? l10n.emptyContent
                      : l10n.emptySearchResult,
                  onRetry: _controller.refresh,
                  child: ContentGrid(
                    items: _controller.items,
                    controller: _scrollController,
                    aspectRatio: widget.aspectRatio,
                    // 详情是**子页面**：必须 push 到路由栈上，
                    // 否则详情页返回时栈里没有上一页（GoError: nothing to pop）。
                    onItemTap: (item) =>
                        context.push(widget.kind.detailRoute(item.id)),
                  ),
                ),
              ),
            ),
            if (_controller.loadingMore)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  l10n.loadingMore,
                  style: AppTypography.caption.copyWith(
                    color: context.appColors.textTertiary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      color: context.appColors.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                widget.title,
                style: AppTypography.headline.copyWith(
                  color: context.appColors.textPrimary,
                ),
              ),
              const Spacer(),
              // 下拉刷新依赖触摸手势，Flutter 默认的滚动设备列表不含鼠标，
              // 桌面 / Web 用户用鼠标无法触发；这里补一个显式刷新入口，
              // 保证所有平台都能刷新列表。
              IconButton(
                tooltip: context.l10n.refresh,
                onPressed: _controller.loadingInitial
                    ? null
                    : () => _controller.refresh(),
                icon: Icon(
                  TDIcons.refresh,
                  size: 20,
                  color: context.appColors.textSecondary,
                ),
              ),
              // 右上角账号头像：进入管理模块（文档 #9）。
              const AccountAvatarButton(),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TDSearchBar(
            placeHolder: widget.searchHint,
            onTextChanged: _controller.search,
            onSubmitted: _controller.search,
            onClearClick: (_) {
              _controller.clearSearch().ignore();
              return true;
            },
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

/// 内容详情页面（文档 #37 ~ #41）。
class ContentDetailPage extends ConsumerStatefulWidget {
  /// 创建页面。
  const ContentDetailPage({
    super.key,
    required this.kind,
    required this.id,
    required this.title,
  });

  /// 内容类型。
  final ContentKind kind;

  /// 内容 ID。
  final String id;

  /// 页面标题。
  final String title;

  @override
  ConsumerState<ContentDetailPage> createState() => _ContentDetailPageState();
}

class _ContentDetailPageState extends ConsumerState<ContentDetailPage> {
  /// 章节列表每页条数。
  ///
  /// 长篇小说 / 漫画的章节可能上千条，一次性渲染会明显卡顿，
  /// 因此按「先展示一页 + 加载更多」的方式分页渲染。
  static const int _chapterPageSize = 20;

  AsyncState<ContentDetail> _state = const Initial<ContentDetail>();

  /// 上次阅读进度（小说 / 漫画，用于「继续阅读」）。
  ReadingProgress? _progress;

  /// 当前已展示的章节条数。
  int _visibleChapters = _chapterPageSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _state = const Loading<ContentDetail>();
      _visibleChapters = _chapterPageSize;
    });
    try {
      final detail = await ref
          .read(contentRepositoryProvider)
          .detail(widget.kind, widget.id);
      ReadingProgress? progress;
      if (widget.kind == ContentKind.novel || widget.kind == ContentKind.comic) {
        try {
          progress = await ref
              .read(readingRepositoryProvider)
              .readProgress(widget.kind, widget.id);
        } on Object {
          progress = null;
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _state = Success<ContentDetail>(detail);
        _progress = progress;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _state = Failure<ContentDetail>(error));
    }
  }

  /// 打开阅读器（小说 / 漫画，文档 #39 / #40）。
  void _openReader(String? chapterId) {
    final route = switch (widget.kind) {
      ContentKind.novel => RoutePaths.novelReader(widget.id, chapterId: chapterId),
      ContentKind.comic => RoutePaths.comicReader(widget.id, chapterId: chapterId),
      _ => null,
    };
    if (route == null) {
      return;
    }
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TDNavBar(
        title: widget.title,
        backgroundColor: context.appColors.surface,
        // 详情页可能通过深链直接进入（例如分享链接），此时栈里没有上一页，
        // 直接用 pop 会抛 GoError，因此回退到列表页。
        useDefaultBack: false,
        leftBarItems: appBackBarItems(context, widget.kind.listRoute),
      ),
      body: switch (_state) {
        Loading<ContentDetail>() => const AppLoading(),
        Failure<ContentDetail>(:final error) => AppErrorView(
          message: localizeError(context, error),
          onRetry: _load,
        ),
        Success<ContentDetail>(:final data) => _buildDetail(context, data),
        _ => const AppLoading(),
      },
    );
  }

  /// 可播放资源列表（影视）。
  ///
  /// 一部影视可能对应多个文件：分集 / 分段，或同一影片散落在多个目录。
  /// 文件被移动或删除属于常态，因此**不可用的文件仍然展示**（标注不可用、
  /// 不可点击），而不是直接从列表消失——否则用户会以为资源凭空少了。
  Widget _buildPlayableFiles(BuildContext context, ContentDetail detail) {
    final l10n = context.l10n;
    final colors = context.appColors;
    return Column(
      children: <Widget>[
        for (final file in detail.files)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: colors.border),
            ),
            clipBehavior: Clip.antiAlias,
            // ListTile 需要最近的 Material 祖先来决定水波纹绘制层：
            // 直接放在有色 Container 里会触发「ink splashes may be invisible」断言，
            // 这里补一层透明 Material（背景仍由外层容器提供）。
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(
              leading: Icon(
                TDIcons.play_circle,
                color: file.available ? colors.brand : colors.textTertiary,
              ),
              title: Text(
                file.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                <String?>[
                  file.resolution,
                  if (file.size != null) formatFileSize(file.size!),
                ].whereType<String>().join(' · '),
                style: AppTypography.caption.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              trailing: file.available
                  ? Icon(
                      TDIcons.chevron_right,
                      size: 18,
                      color: colors.textTertiary,
                    )
                  : Text(
                      l10n.mediaFileUnavailable,
                      style: AppTypography.caption.copyWith(
                        color: colors.warning,
                      ),
                    ),
              enabled: file.available,
              onTap: file.available
                  ? () => _openPlayer(detail, file)
                  : null,
              ),
            ),
          ),
      ],
    );
  }

  /// 打开播放页。
  ///
  /// 只把**可用**文件作为可切换的播放源传入；未选中但可用的文件仍会出现在
  /// 播放页的「切换播放源」里。
  void _openPlayer(ContentDetail detail, MediaFile file) {
    final playable = detail.files
        .where((item) => item.available)
        .toList(growable: false);
    if (playable.isEmpty) {
      return;
    }
    context.push(
      RoutePaths.mediaPlayer,
      extra: MediaPlayerArgs(
        title: detail.item.title,
        files: playable,
        fileId: file.id,
      ),
    );
  }

  Widget _buildDetail(BuildContext context, ContentDetail detail) {
    final l10n = context.l10n;
    final item = detail.item;
    final colors = context.appColors;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: <Widget>[
        ResponsiveBuilder(
          builder: (context, size) {
            final poster = AppImage(
              uri: item.coverUri,
              fallbackUri: item.coverFallbackUri,
              width: size.isDesktop ? 200 : 140,
              height: size.isDesktop ? 300 : 210,
            );
            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title,
                  style: AppTypography.headline.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                if (item.subtitle != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    item.subtitle!,
                    style: AppTypography.body.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    if (item.year != null)
                      _metaChip(context, l10n.releaseYear, '${item.year}'),
                    if (item.rating != null)
                      _metaChip(
                        context,
                        l10n.rating,
                        item.rating!.toStringAsFixed(1),
                      ),
                    if (detail.episodeCount != null)
                      _metaChip(
                        context,
                        l10n.episodeCount,
                        '${detail.episodeCount}',
                      ),
                    if (detail.author != null)
                      _metaChip(context, l10n.author, detail.author!),
                  ],
                ),
                if (item.categories.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: item.categories
                        .map(
                          (category) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surfaceVariant,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(
                              category,
                              style: AppTypography.caption.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ],
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                poster,
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: info),
              ],
            );
          },
        ),
        if (detail.files.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          Text(
            l10n.mediaFilesTitle,
            style: AppTypography.title.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.md),
          _buildPlayableFiles(context, detail),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text(
          l10n.overview,
          style: AppTypography.title.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          detail.overview ?? l10n.noOverview,
          style: AppTypography.body.copyWith(color: colors.textSecondary),
        ),
        if (detail.attributes.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          Text(
            l10n.detailSectionInfo,
            style: AppTypography.title.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.md),
          ContentAttributes(
            kind: widget.kind,
            attributes: detail.attributes,
          ),
        ],
        if (detail.gallery.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          Text(
            l10n.detailSectionGallery,
            style: AppTypography.title.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.md),
          ResponsiveBuilder(
            builder: (context, size) {
              final height = size.isDesktop ? 200.0 : 140.0;
              final width = size.isDesktop ? 300.0 : 210.0;
              return SizedBox(
                height: height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: detail.gallery.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (context, index) => AppImage(
                    uri: detail.gallery[index],
                    width: width,
                    height: height,
                  ),
                ),
              );
            },
          ),
        ],
        if (detail.related.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          Text(
            l10n.peopleRelatedContent,
            style: AppTypography.title.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 220,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: detail.related.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, index) {
                final related = detail.related[index];
                return SizedBox(
                  width: 120,
                  child: ContentCard(
                    item: related,
                    onTap: () =>
                        context.push(ContentKind.media.detailRoute(related.id)),
                  ),
                );
              },
            ),
          ),
        ],
        if (detail.chapters.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: <Widget>[
              Text(
                l10n.chapterList,
                style: AppTypography.title.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                l10n.chapterCount(detail.chapters.length),
                style: AppTypography.caption.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TDCellGroup(
            cells: detail.chapters
                .take(_visibleChapters)
                .map(
                  (chapter) => TDCell(
                    title: chapter.title,
                    arrow: _readable,
                    onClick: _readable ? (_) => _openReader(chapter.id) : null,
                  ),
                )
                .toList(growable: false),
          ),
          if (detail.chapters.length > _visibleChapters)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: TDButton(
                text: l10n.loadMoreChapters,
                isBlock: true,
                type: TDButtonType.outline,
                theme: TDButtonTheme.primary,
                onTap: () => setState(
                  () => _visibleChapters += _chapterPageSize,
                ),
              ),
            ),
        ],
        if (_readable)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_progress?.chapterTitle != null) ...<Widget>[
                  Text(
                    l10n.detailLastRead(_progress!.chapterTitle!),
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                TDButton(
                  text: _progress == null
                      ? l10n.startReading
                      : l10n.continueReading,
                  isBlock: true,
                  theme: TDButtonTheme.primary,
                  size: TDButtonSize.large,
                  disabled: detail.chapters.isEmpty,
                  onTap: () => _openReader(_progress?.chapterId),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  /// 当前内容类型是否支持阅读器。
  bool get _readable =>
      widget.kind == ContentKind.novel || widget.kind == ContentKind.comic;

  Widget _metaChip(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: context.appColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        '$label · $value',
        style: AppTypography.caption.copyWith(
          color: context.appColors.textSecondary,
        ),
      ),
    );
  }
}
