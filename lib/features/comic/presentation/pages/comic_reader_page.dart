import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../../../../app/app_container.dart';
import '../../../../app/navigation.dart';
import '../../../../app/route_paths.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/reader_palette.dart';
import '../../../../domain/entities/content.dart';
import '../../../../domain/entities/reading.dart';
import '../../../../shared/states/async_state.dart' show localizeError;
import '../../../../shared/widgets/app_state_views.dart';
import '../../../../shared/widgets/reader_immersive.dart';

/// 漫画阅读器（文档 #40）。
///
/// 数据来源完全来自服务端：
/// * 相册详情 → 章节目录（`GET /api/client/v1/comics/{id}`）；
/// * 章节图片 → `GET /api/client/v1/comics/{id}/chapters/{chapterId}`，
///   旧版服务端自动回退到 `/api/pub/comic/chapter/pages`。
///
/// 图片地址由服务端归一化为可访问 URL（客户端对旧服务端亦会本地兜底），
/// 因此可直接交给图片组件加载。
class ComicReaderPage extends ConsumerStatefulWidget {
  /// 创建页面。
  const ComicReaderPage({super.key, required this.albumId, this.chapterId});

  /// 相册 ID。
  final String albumId;

  /// 起始章节 ID；为空时从上次阅读进度或第一章开始。
  final String? chapterId;

  @override
  ConsumerState<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends ConsumerState<ComicReaderPage>
    with ReaderImmersive<ComicReaderPage> {
  final PageController _pageController = PageController();

  ComicReaderSettings _settings = const ComicReaderSettings();
  List<ContentChapter> _chapters = const <ContentChapter>[];
  ComicChapterPages? _chapterPages;
  String? _albumTitle;

  bool _loading = true;
  bool _loadingChapter = false;
  Object? _error;
  int _pageIndex = 0;

  /// 阅读时是否展示导航栏与底栏（点击图片区域切换）。
  bool _uiVisible = true;

  @override
  bool get readerUiVisible => _uiVisible;

  @override
  void setReaderUiVisible(bool visible) {
    if (!mounted || _uiVisible == visible) {
      return;
    }
    setState(() => _uiVisible = visible);
  }

  int get _chapterIndex {
    final current = _chapterPages;
    if (current == null) {
      return -1;
    }
    return _chapters.indexWhere((item) => item.id == current.chapterId);
  }

  String? get _prevChapterId {
    final index = _chapterIndex;
    if (index > 0) {
      return _chapters[index - 1].id;
    }
    return _chapterPages?.prevId;
  }

  String? get _nextChapterId {
    final index = _chapterIndex;
    if (index >= 0 && index < _chapters.length - 1) {
      return _chapters[index + 1].id;
    }
    return _chapterPages?.nextId;
  }

  @override
  void initState() {
    super.initState();
    initReaderImmersive();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _pageController.dispose();
    disposeReaderImmersive();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reading = ref.read(readingRepositoryProvider);
      final settings = await reading.readComicSettings();
      final detail = await ref
          .read(contentRepositoryProvider)
          .detail(ContentKind.comic, widget.albumId);
      if (!mounted) {
        return;
      }
      final progress = await reading.readProgress(ContentKind.comic, widget.albumId);
      final target = widget.chapterId ??
          progress?.chapterId ??
          (detail.chapters.isEmpty ? null : detail.chapters.first.id);
      setState(() {
        _settings = settings;
        _chapters = detail.chapters;
        _albumTitle = detail.item.title;
        _loading = false;
      });
      if (target == null) {
        return;
      }
      await _loadChapter(target, restorePage: progress?.page ?? 0);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// 加载章节图片。
  ///
  /// [restorePage] 为 1 基的起始页；[restoreLast] 表示定位到最后一页
  /// （回翻上一章时使用：章内页数只有在加载完成后才知道）。
  Future<void> _loadChapter(
    String chapterId, {
    int restorePage = 0,
    bool restoreLast = false,
  }) async {
    setState(() {
      _loadingChapter = true;
      _error = null;
    });
    try {
      final pages = await ref
          .read(contentRepositoryProvider)
          .comicChapterPages(widget.albumId, chapterId);
      if (!mounted) {
        return;
      }
      final lastIndex = pages.pages.isEmpty ? 0 : pages.pages.length - 1;
      final index = restoreLast
          ? lastIndex
          : (restorePage <= 0 ? 0 : (restorePage - 1).clamp(0, lastIndex));
      setState(() {
        _chapterPages = pages;
        _pageIndex = index;
        _loadingChapter = false;
      });
      // 首帧构建后 PageView 才挂载完成，此时才能定位到目标页
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) {
          return;
        }
        _pageController.jumpToPage(index);
      });
      await _saveProgress(pages, index);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loadingChapter = false;
      });
    }
  }

  Future<void> _saveProgress(ComicChapterPages pages, int pageIndex) async {
    final chapterIndex = _chapters.indexWhere(
      (item) => item.id == pages.chapterId,
    );
    await ref
        .read(readingRepositoryProvider)
        .writeProgress(
          ReadingProgress(
            kind: ContentKind.comic,
            id: widget.albumId,
            title: _albumTitle ?? pages.title,
            chapterId: pages.chapterId,
            chapterTitle: pages.title,
            chapterIndex: chapterIndex >= 0 ? chapterIndex + 1 : pages.index,
            page: pageIndex + 1,
          ),
        );
  }

  Future<void> _updateSettings(
    ComicReaderSettings Function(ComicReaderSettings current) update,
  ) async {
    final next = update(_settings);
    setState(() => _settings = next);
    await ref.read(readingRepositoryProvider).writeComicSettings(next);
  }

  /// 打开章节。[restoreLast] 为真时落在该章最后一页（回翻上一章）。
  void _openChapter(String? chapterId, {bool restoreLast = false}) {
    if (chapterId == null) {
      return;
    }
    setState(() => _loadingChapter = true);
    _loadChapter(chapterId, restoreLast: restoreLast).ignore();
  }

  void _goToPage(int index) {
    final pages = _chapterPages;
    if (pages == null || pages.pages.isEmpty) {
      return;
    }
    if (index < 0) {
      // 回翻到上一章时落在上一章的最后一页：
      // 第三章第 1 页往回翻，应当回到第二章的结尾。
      _openChapter(_prevChapterId, restoreLast: true);
      return;
    }
    if (index >= pages.pages.length) {
      _openChapter(_nextChapterId);
      return;
    }
    _pageController.animateToPage(
      index,
      duration: AppMotion.normal,
      curve: AppMotion.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(_settings.background);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: _uiVisible ? _buildAppBar(context, palette) : null,
      body: SafeArea(child: _buildBody(context, palette)),
      bottomNavigationBar: _uiVisible ? _buildBottomBar(context, palette) : null,
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, ReaderPalette palette) {
    final l10n = context.l10n;
    final pages = _chapterPages;
    return TDNavBar(
      title: pages == null || pages.title.isEmpty
          ? (_albumTitle ?? l10n.comicTitle)
          : pages.title,
      backgroundColor: palette.background,
      titleColor: palette.text,
      // 阅读器可能由深链直接进入，此时栈里没有上一页，由 popOrGo 兜底。
      useDefaultBack: false,
      leftBarItems: appBackBarItems(
        context,
        RoutePaths.comic,
        iconColor: palette.text,
      ),
      rightBarItems: <TDNavBarItem>[
        TDNavBarItem(
          icon: TDIcons.view_list,
          iconColor: palette.text,
          action: _showChapterSheet,
        ),
        TDNavBarItem(
          icon: _settings.mode == ComicReadMode.paged
              ? TDIcons.menu
              : TDIcons.image,
          iconColor: palette.text,
          action: _toggleMode,
        ),
        TDNavBarItem(
          icon: TDIcons.setting,
          iconColor: palette.text,
          action: _showSettingsSheet,
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, ReaderPalette palette) {
    if (_loading || _loadingChapter) {
      return const AppLoading();
    }
    final error = _error;
    final pages = _chapterPages;
    if (error != null && pages == null) {
      return AppErrorView(
        message: localizeError(context, error),
        onRetry: _bootstrap,
      );
    }
    if (pages == null || pages.pages.isEmpty) {
      return AppEmpty(message: context.l10n.comicReaderEmpty);
    }
    return _settings.mode == ComicReadMode.paged
        ? _buildPaged(context, pages)
        : _buildContinuous(context, pages);
  }

  /// 翻页模式：单页横向翻页，支持双指缩放与左右区域点击翻页。
  Widget _buildPaged(BuildContext context, ComicChapterPages pages) {
    return Stack(
      children: <Widget>[
        PageView.builder(
          controller: _pageController,
          itemCount: pages.pages.length,
          onPageChanged: (index) {
            setState(() => _pageIndex = index);
            // 翻页说明用户仍在操作，重置操作栏自动隐藏计时。
            keepReaderUiAlive();
            _saveProgress(pages, index).ignore();
          },
          itemBuilder: (context, index) => InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: _pageImage(pages.pages[index].imageUri, BoxFit.contain),
          ),
        ),
        Positioned.fill(
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => _goToPage(_pageIndex - 1),
                ),
              ),
              // 中间区域：点击切换导航栏 / 底栏显隐
              Expanded(
                flex: 4,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: toggleReaderUi,
                ),
              ),
              Expanded(
                flex: 3,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => _goToPage(_pageIndex + 1),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 连续滚动模式：纵向长图，按页宽填充。
  ///
  /// 与翻页模式保持一致：点击页面同样能切换操作栏显隐。
  /// 否则操作栏自动隐藏后用户没有任何可点击区域，无法再唤出返回 / 目录 / 设置。
  Widget _buildContinuous(BuildContext context, ComicChapterPages pages) {
    return ListView.builder(
      itemCount: pages.pages.length,
      itemBuilder: (context, index) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: toggleReaderUi,
        child: _pageImage(pages.pages[index].imageUri, BoxFit.fitWidth),
      ),
    );
  }

  Widget _pageImage(Uri uri, BoxFit fit) {
    return Image.network(
      uri.toString(),
      fit: fit,
      width: double.infinity,
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }
        return const SizedBox(
          height: 320,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (context, error, stackTrace) => SizedBox(
        height: 240,
        child: Center(
          child: Icon(
            TDIcons.image_error,
            size: 40,
            color: ReaderPalette.of(_settings.background).secondary,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, ReaderPalette palette) {
    final l10n = context.l10n;
    final pages = _chapterPages;
    final position = pages == null || pages.pages.isEmpty
        ? ''
        : l10n.comicPageProgress(_pageIndex + 1, pages.pages.length);
    return Container(
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TDButton(
              text: l10n.readerPrevChapter,
              type: TDButtonType.text,
              size: TDButtonSize.small,
              disabled: _prevChapterId == null,
              onTap: () => _openChapter(_prevChapterId),
            ),
          ),
          Expanded(
            child: Text(
              position,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(color: palette.secondary),
            ),
          ),
          Expanded(
            child: TDButton(
              text: l10n.readerNextChapter,
              type: TDButtonType.text,
              size: TDButtonSize.small,
              disabled: _nextChapterId == null,
              onTap: () => _openChapter(_nextChapterId),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleMode() {
    _updateSettings(
      (current) => current.copyWith(
        mode: current.mode == ComicReadMode.paged
            ? ComicReadMode.continuous
            : ComicReadMode.paged,
      ),
    ).ignore();
  }

  Future<void> _showChapterSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ComicChapterSheet(
        chapters: _chapters,
        currentId: _chapterPages?.chapterId,
      ),
    );
    if (selected != null && selected != _chapterPages?.chapterId) {
      _openChapter(selected);
    }
  }

  Future<void> _showSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ComicSettingsSheet(
        settings: _settings,
        onChanged: (next) => _updateSettings((_) => next).ignore(),
      ),
    );
  }
}

/// 漫画章节目录弹层。
class _ComicChapterSheet extends StatelessWidget {
  const _ComicChapterSheet({required this.chapters, required this.currentId});

  final List<ContentChapter> chapters;
  final String? currentId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (chapters.isEmpty) {
      return SizedBox(
        height: 220,
        child: AppEmpty(message: l10n.readerChapterEmpty),
      );
    }
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              '${l10n.readerChapterList} · ${l10n.chapterCount(chapters.length)}',
              style: AppTypography.title.copyWith(
                color: context.appColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: ListView.builder(
              itemCount: chapters.length,
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                final selected = chapter.id == currentId;
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: context.appColors.brandSubtle,
                  title: Text(
                    chapter.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: selected
                          ? context.appColors.brand
                          : context.appColors.textPrimary,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(chapter.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 漫画阅读设置弹层（阅读模式 / 背景）。
class _ComicSettingsSheet extends StatefulWidget {
  const _ComicSettingsSheet({
    required this.settings,
    required this.onChanged,
  });

  final ComicReaderSettings settings;
  final ValueChanged<ComicReaderSettings> onChanged;

  @override
  State<_ComicSettingsSheet> createState() => _ComicSettingsSheetState();
}

class _ComicSettingsSheetState extends State<_ComicSettingsSheet> {
  late ComicReaderSettings _settings = widget.settings;

  void _apply(ComicReaderSettings next) {
    setState(() => _settings = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.readerSettings,
            style: AppTypography.title.copyWith(
              color: context.appColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.comicReadMode,
            style: AppTypography.caption.copyWith(
              color: context.appColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: TDButton(
                  text: l10n.comicReadModePaged,
                  type: _settings.mode == ComicReadMode.paged
                      ? TDButtonType.fill
                      : TDButtonType.outline,
                  size: TDButtonSize.small,
                  isBlock: true,
                  onTap: () =>
                      _apply(_settings.copyWith(mode: ComicReadMode.paged)),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TDButton(
                  text: l10n.comicReadModeContinuous,
                  type: _settings.mode == ComicReadMode.continuous
                      ? TDButtonType.fill
                      : TDButtonType.outline,
                  size: TDButtonSize.small,
                  isBlock: true,
                  onTap: () =>
                      _apply(_settings.copyWith(mode: ComicReadMode.continuous)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.readerBackground,
            style: AppTypography.caption.copyWith(
              color: context.appColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              _backgroundChip(
                context,
                label: l10n.readerBackgroundLight,
                background: ReaderBackground.light,
              ),
              _backgroundChip(
                context,
                label: l10n.readerBackgroundSepia,
                background: ReaderBackground.sepia,
              ),
              _backgroundChip(
                context,
                label: l10n.readerBackgroundGreen,
                background: ReaderBackground.green,
              ),
              _backgroundChip(
                context,
                label: l10n.readerBackgroundDark,
                background: ReaderBackground.dark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _backgroundChip(
    BuildContext context, {
    required String label,
    required ReaderBackground background,
  }) {
    final palette = ReaderPalette.of(background);
    final selected = _settings.background == background;
    return GestureDetector(
      onTap: () => _apply(_settings.copyWith(background: background)),
      child: Container(
        constraints: const BoxConstraints(minWidth: 72),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? context.appColors.brand : context.appColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: palette.text),
        ),
      ),
    );
  }
}
