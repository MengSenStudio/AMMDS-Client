import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../../../../app/app_container.dart';
import '../../../../app/navigation.dart';
import '../../../../app/route_paths.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/reader_palette.dart';
import '../../../../core/utils/novel_paginator.dart';
import '../../../../domain/entities/content.dart';
import '../../../../domain/entities/reading.dart';
import '../../../../shared/states/async_state.dart' show localizeError;
import '../../../../shared/widgets/app_state_views.dart';
import '../../../../shared/widgets/reader_immersive.dart';

/// 小说阅读器（文档 #39）。
///
/// 数据来源完全来自服务端：
/// * 书籍详情 → 章节目录（`GET /api/client/v1/novels/{id}`）；
/// * 章节正文 → `GET /api/client/v1/novels/{id}/chapters/{chapterId}`，
///   旧版服务端自动回退到 `/api/pub/novel/chapter/{chapterId}`。
///
/// 阅读模式（对齐服务端网页阅读器的能力，见 `app/src/views/web/novel/reader`）：
///
/// | 模式 | 翻页方式 | 进度语义 |
/// | --- | --- | --- |
/// | **翻页** | 点击左右分区 / 横向滑动 / 方向键 / 空格 / 滚轮 | 章内百分比 |
/// | **滚动** | 纵向滚动 | 滚动百分比 |
///
/// 两种模式共用同一套排版设置（字号 / 行距 / 版心宽度 / 页边距 / 首行缩进 /
/// 配色）与阅读进度字段（`percent`），因此切换模式后仍能续读到同一位置。
///
/// 分页不用「按字数切」的近似做法，而是用 [NovelPaginator] 实测排版结果切分，
/// 保证不会出现末行被裁掉或页面留白过多。
class NovelReaderPage extends ConsumerStatefulWidget {
  /// 创建页面。
  const NovelReaderPage({super.key, required this.bookId, this.chapterId});

  /// 小说 ID。
  final String bookId;

  /// 起始章节 ID；为空时从上次阅读进度或第一章开始。
  final String? chapterId;

  @override
  ConsumerState<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends ConsumerState<NovelReaderPage>
    with ReaderImmersive<NovelReaderPage> {
  /// 滚轮翻页的最小间隔（避免一次滚动连翻多页）。
  static const Duration _wheelThrottle = Duration(milliseconds: 260);

  /// 进度写入节流。
  static const Duration _progressThrottle = Duration(milliseconds: 600);

  /// 首行缩进前缀（两个字宽）。
  static const String _indent = '\u3000\u3000';

  /// 回翻进入上一章时使用的章内进度：100% 即该章最后一页。
  static const int _lastPagePercent = 100;

  final ScrollController _scrollController = ScrollController();
  final PageController _pageController = PageController();
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'novel-reader');

  NovelReaderSettings _settings = const NovelReaderSettings();
  List<ContentChapter> _chapters = const <ContentChapter>[];
  ChapterContent? _chapter;
  String? _bookTitle;

  bool _loading = true;
  bool _loadingChapter = false;
  bool _uiVisible = true;
  Object? _error;

  Timer? _progressTimer;
  DateTime _lastWheelAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 分页结果与签名；签名变化（版面 / 排版设置 / 章节）时重新分页。
  List<List<NovelPageChunk>> _pages = const <List<NovelPageChunk>>[];
  String _paginationSignature = '';

  /// 当前页码（0 基）。
  int _pageIndex = 0;

  /// 待恢复的章内百分比：分页完成后才能换算成页码，因此延后处理。
  int? _restorePercent;

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
    final current = _chapter;
    if (current == null) {
      return -1;
    }
    return _chapters.indexWhere((item) => item.id == current.id);
  }

  bool get _isPaged => _settings.mode == NovelReadMode.paged;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    initReaderImmersive();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _pageController.dispose();
    _keyboardFocus.dispose();
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
      final settings = await reading.readNovelSettings();
      final detail = await ref
          .read(contentRepositoryProvider)
          .detail(ContentKind.novel, widget.bookId);
      if (!mounted) {
        return;
      }
      final progress = await reading.readProgress(
        ContentKind.novel,
        widget.bookId,
      );
      final target =
          widget.chapterId ??
          progress?.chapterId ??
          (detail.chapters.isEmpty ? null : detail.chapters.first.id);
      setState(() {
        _settings = settings;
        _chapters = detail.chapters;
        _bookTitle = detail.item.title;
        _loading = false;
      });
      if (target == null) {
        return;
      }
      await _loadChapter(target, restorePercent: progress?.page ?? 0);
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

  /// 加载章节正文。
  ///
  /// [restorePercent] 为章内进度（百分数），仅在恢复到同一章节时生效。
  Future<void> _loadChapter(String chapterId, {int restorePercent = 0}) async {
    setState(() {
      _loadingChapter = true;
      _error = null;
    });
    try {
      final chapter = await ref
          .read(contentRepositoryProvider)
          .novelChapterContent(widget.bookId, chapterId);
      if (!mounted) {
        return;
      }
      setState(() {
        _chapter = chapter;
        _loadingChapter = false;
        // 换章后分页结果失效，重新分页；页码从 0 开始并交给恢复逻辑定位
        _paginationSignature = '';
        _pages = const <List<NovelPageChunk>>[];
        _pageIndex = 0;
        _restorePercent = restorePercent;
      });
      await _saveProgress(chapter, percent: restorePercent);
      if (!_isPaged) {
        _jumpTo(restorePercent);
      }
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

  // ---------------------------------------------------------------- 排版

  /// 正文样式：分页测量与渲染必须使用完全相同的样式。
  TextStyle _textStyle(ReaderPalette palette) => AppTypography.body.copyWith(
    color: palette.text,
    fontSize: _settings.fontSize,
    height: _settings.lineHeight,
  );

  /// 段间距（与服务端网页阅读器的 `0.8em` 对齐）。
  double get _paragraphSpacing => _settings.fontSize * 0.8;

  /// 由版面尺寸推导排版几何。
  ({double hPad, double vPad, double textWidth, double textHeight}) _metrics(
    Size size,
  ) {
    final narrow = size.width < 600;
    final base = _settings.padding.value;
    final hPad = (narrow ? base * 0.6 : base)
        .clamp(12.0, math.max(12.0, size.width * 0.12))
        .toDouble();
    final vPad = narrow ? 20.0 : 30.0;
    final textWidth = math.max(
      80.0,
      math.min(size.width - hPad * 2, _settings.contentWidth.maxWidth),
    );
    final textHeight = math.max(120.0, size.height - vPad * 2);
    return (
      hPad: hPad,
      vPad: vPad,
      textWidth: textWidth,
      textHeight: textHeight,
    );
  }

  /// 章节标题在首页占用的高度（标题 + 间距）。
  double _titleBlockHeight(BuildContext context, double textWidth) {
    final title = _chapter?.title ?? '';
    if (title.isEmpty) {
      return 0;
    }
    final style = AppTypography.title.copyWith(
      fontSize: _settings.fontSize + 4,
      fontWeight: FontWeight.w600,
    );
    final painter = TextPainter(
      text: TextSpan(text: title, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: textWidth);
    final height = painter.height;
    painter.dispose();
    return height + AppSpacing.lg;
  }

  /// 按需重新分页；结果缓存在 [_pages]，避免每帧重算。
  void _ensurePagination(
    BuildContext context,
    Size size,
    ReaderPalette palette,
  ) {
    final chapter = _chapter;
    if (chapter == null) {
      return;
    }
    final text = chapter.text ?? '';
    final scaler = MediaQuery.textScalerOf(context);
    final signature = <Object?>[
      chapter.id,
      text.length,
      size.width.toStringAsFixed(1),
      size.height.toStringAsFixed(1),
      _settings.fontSize,
      _settings.lineHeight,
      _settings.contentWidth.code,
      _settings.padding.code,
      _settings.indentFirstLine,
      scaler.scale(14),
    ].join('|');
    if (signature == _paginationSignature) {
      return;
    }
    final metrics = _metrics(size);
    _pages = NovelPaginator.paginate(
      paragraphs: text.split('\n'),
      style: _textStyle(palette),
      textScaler: scaler,
      maxWidth: metrics.textWidth,
      maxHeight: metrics.textHeight,
      paragraphSpacing: _paragraphSpacing,
      indent: _indent,
      indentFirstLine: _settings.indentFirstLine,
      firstPageHeaderHeight: _titleBlockHeight(context, metrics.textWidth),
    );
    _paginationSignature = signature;
    _pageIndex = _pages.isEmpty ? 0 : _pageIndex.clamp(0, _pages.length - 1);

    final restore = _restorePercent;
    if (restore != null) {
      _restorePercent = null;
      final target = _pageForPercent(restore);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) {
          return;
        }
        _pageController.jumpToPage(target);
        setState(() => _pageIndex = target);
      });
    }
  }

  /// 章内百分比 → 页码。
  int _pageForPercent(int percent) {
    if (_pages.isEmpty) {
      return 0;
    }
    final ratio = (percent.clamp(0, 100)) / 100;
    final index = (ratio * _pages.length).round() - 1;
    return index.clamp(0, _pages.length - 1);
  }

  /// 当前页对应的章内百分比。
  int _percentOfPage() {
    if (_pages.isEmpty) {
      return 0;
    }
    return (((_pageIndex + 1) / _pages.length) * 100).clamp(0, 100).round();
  }

  // ---------------------------------------------------------------- 进度

  /// 滚动到指定百分比位置（滚动模式）。
  void _jumpTo(int percent) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final max = _scrollController.position.maxScrollExtent;
      final ratio = (percent.clamp(0, 100)) / 100;
      _scrollController.jumpTo(max * ratio);
    });
  }

  void _onScroll() {
    if (_isPaged || !_scrollController.hasClients) {
      return;
    }
    _scheduleProgressSave();
  }

  void _scheduleProgressSave() {
    _progressTimer?.cancel();
    _progressTimer = Timer(_progressThrottle, () {
      final chapter = _chapter;
      if (chapter == null) {
        return;
      }
      _saveProgress(chapter, percent: _currentPercent()).ignore();
    });
  }

  int _currentPercent() => _isPaged ? _percentOfPage() : _scrollPercent();

  int _scrollPercent() {
    if (!_scrollController.hasClients) {
      return 0;
    }
    final position = _scrollController.position;
    final max = position.maxScrollExtent;
    if (max <= 0) {
      return 0;
    }
    return ((position.pixels / max) * 100).clamp(0, 100).round();
  }

  Future<void> _saveProgress(ChapterContent chapter, {int? percent}) async {
    final index = _chapters.indexWhere((item) => item.id == chapter.id);
    await ref
        .read(readingRepositoryProvider)
        .writeProgress(
          ReadingProgress(
            kind: ContentKind.novel,
            id: widget.bookId,
            title: _bookTitle ?? chapter.title,
            chapterId: chapter.id,
            chapterTitle: chapter.title,
            chapterIndex: index >= 0 ? index + 1 : chapter.index,
            page: percent ?? 0,
          ),
        );
  }

  Future<void> _updateSettings(
    NovelReaderSettings Function(NovelReaderSettings current) update,
  ) async {
    final next = update(_settings);
    setState(() {
      _settings = next;
      // 排版设置变化会改变分页，签名置空触发重排
      _paginationSignature = '';
    });
    await ref.read(readingRepositoryProvider).writeNovelSettings(next);
  }

  // ---------------------------------------------------------------- 翻页

  /// 翻页。[delta] 为 +1（下一页）/ -1（上一页）。
  ///
  /// 越界时按 [NovelReaderSettings.autoNextChapter] 决定是否进入相邻章节。
  /// 回翻进入上一章时落在**上一章的最后一页**（第三章第 1 页再往回翻，
  /// 应当回到第二章的结尾，而不是跳到第二章的开头）。
  void _turnPage(int delta) {
    if (_pages.isNotEmpty) {
      final target = _pageIndex + delta;
      if (target >= 0 && target < _pages.length) {
        _goToPage(target);
        return;
      }
    }
    if (!_settings.autoNextChapter) {
      return;
    }
    if (delta > 0) {
      _openChapter(_nextChapterId);
      return;
    }
    _openChapter(_prevChapterId, restorePercent: _lastPagePercent);
  }

  void _goToPage(int index) {
    if (_settings.pageAnimation) {
      _pageController
          .animateToPage(
            index,
            duration: AppMotion.normal,
            curve: AppMotion.standard,
          )
          .ignore();
      return;
    }
    _pageController.jumpToPage(index);
  }

  /// 点击分区：左侧上一页 / 右侧下一页 / 中间切换操作栏。
  void _handleTapUp(TapUpDetails details, double width) {
    final dx = details.localPosition.dx;
    if (dx < width * 0.3) {
      _turnPage(-1);
      return;
    }
    if (dx > width * 0.7) {
      _turnPage(1);
      return;
    }
    toggleReaderUi();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!_isPaged || event is! PointerScrollEvent) {
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastWheelAt) < _wheelThrottle) {
      return;
    }
    final dy = event.scrollDelta.dy;
    if (dy.abs() < 4) {
      return;
    }
    _lastWheelAt = now;
    _turnPage(dy > 0 ? 1 : -1);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey == LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final forward =
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.space;
    final backward =
        key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.pageUp;
    if (forward || backward) {
      final delta = forward ? 1 : -1;
      if (_isPaged) {
        _turnPage(delta);
      } else {
        _scrollByScreen(delta);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (_isPaged) {
        _turnPage(key == LogicalKeyboardKey.arrowDown ? 1 : -1);
      } else {
        _scrollByScreen(key == LogicalKeyboardKey.arrowDown ? 1 : -1);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      setReaderUiVisible(false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollByScreen(int delta) {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final target = position.pixels + position.viewportDimension * 0.9 * delta;
    _scrollController.jumpTo(target.clamp(0, position.maxScrollExtent));
  }

  String? get _prevChapterId {
    final index = _chapterIndex;
    if (index > 0) {
      return _chapters[index - 1].id;
    }
    return _chapter?.prevId;
  }

  String? get _nextChapterId {
    final index = _chapterIndex;
    if (index >= 0 && index < _chapters.length - 1) {
      return _chapters[index + 1].id;
    }
    return _chapter?.nextId;
  }

  // ---------------------------------------------------------------- 构建

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(_settings.background);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: _uiVisible ? _buildAppBar(context, palette) : null,
      body: SafeArea(
        child: KeyboardListener(
          focusNode: _keyboardFocus,
          autofocus: true,
          onKeyEvent: (event) => _handleKeyEvent(_keyboardFocus, event),
          child: Listener(
            onPointerSignal: _handlePointerSignal,
            child: _buildBody(context, palette),
          ),
        ),
      ),
      bottomNavigationBar: _uiVisible
          ? _buildBottomBar(context, palette)
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, ReaderPalette palette) {
    final l10n = context.l10n;
    return TDNavBar(
      title: _chapter?.title ?? _bookTitle ?? l10n.novelTitle,
      backgroundColor: palette.background,
      titleColor: palette.text,
      // 阅读器可能由深链直接进入，此时栈里没有上一页，由 popOrGo 兜底。
      useDefaultBack: false,
      leftBarItems: appBackBarItems(
        context,
        RoutePaths.novel,
        iconColor: palette.text,
      ),
      rightBarItems: <TDNavBarItem>[
        TDNavBarItem(
          icon: TDIcons.swap_left,
          iconColor: palette.text,
          action: _toggleMode,
        ),
        TDNavBarItem(
          icon: TDIcons.view_list,
          iconColor: palette.text,
          action: _showChapterSheet,
        ),
        TDNavBarItem(
          icon: TDIcons.setting,
          iconColor: palette.text,
          action: _showSettingsSheet,
        ),
      ],
    );
  }

  void _toggleMode() {
    _updateSettings(
      (current) => current.copyWith(
        mode: current.mode == NovelReadMode.paged
            ? NovelReadMode.scroll
            : NovelReadMode.paged,
      ),
    ).ignore();
  }

  Widget _buildBody(BuildContext context, ReaderPalette palette) {
    if (_loading) {
      return const AppLoading();
    }
    final error = _error;
    if (error != null && _chapter == null) {
      return AppErrorView(
        message: localizeError(context, error),
        onRetry: _bootstrap,
      );
    }
    final chapter = _chapter;
    if (chapter == null) {
      return AppEmpty(message: context.l10n.readerChapterEmpty);
    }
    if (_loadingChapter) {
      return const AppLoading();
    }
    final text = chapter.text ?? '';
    if (text.trim().isEmpty) {
      return Center(
        child: Text(
          context.l10n.readerNoContent,
          style: _textStyle(palette),
        ),
      );
    }
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: _isPaged
              ? _buildPagedView(context, palette)
              : _buildScrollView(context, palette, chapter, text),
        ),
        // 常显阅读进度线（不拦截点击）
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: SizedBox(
              height: 3,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  // heightFactor 必须显式给出：只给 widthFactor 时高度约束是松的，
                  // 无子节点的 ColoredBox 会取最小高度 0，进度线就永远看不见。
                  heightFactor: 1,
                  widthFactor: _bookProgress(),
                  child: ColoredBox(color: palette.secondary),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 全书进度（0~1）：已读章节数 + 章内占比。
  double _bookProgress() {
    final total = _chapters.length;
    if (total <= 0) {
      return 0;
    }
    final index = _chapterIndex;
    if (index < 0) {
      return 0;
    }
    final inner = _currentPercent() / 100;
    return ((index + inner) / total).clamp(0.0, 1.0);
  }

  /// 翻页模式：一次一屏，横向翻页。
  Widget _buildPagedView(BuildContext context, ReaderPalette palette) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        _ensurePagination(context, size, palette);
        if (_pages.isEmpty) {
          return Center(
            child: Text(
              context.l10n.readerNoContent,
              style: _textStyle(palette),
            ),
          );
        }
        final metrics = _metrics(size);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (details) => _handleTapUp(details, size.width),
          child: PageView.builder(
            controller: _pageController,
            physics: const ClampingScrollPhysics(),
            itemCount: _pages.length,
            onPageChanged: (index) {
              setState(() => _pageIndex = index);
              // 翻页说明用户仍在操作，重置操作栏自动隐藏计时
              keepReaderUiAlive();
              _scheduleProgressSave();
            },
            itemBuilder: (context, index) => _buildPageContent(
              context,
              palette,
              metrics,
              index,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPageContent(
    BuildContext context,
    ReaderPalette palette,
    ({double hPad, double vPad, double textWidth, double textHeight}) metrics,
    int index,
  ) {
    final chunks = _pages[index];
    final style = _textStyle(palette);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.hPad,
        vertical: metrics.vPad,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (index == 0 && (_chapter?.title ?? '').isNotEmpty) ...<Widget>[
            Text(
              _chapter!.title,
              style: AppTypography.title.copyWith(
                color: palette.text,
                fontSize: _settings.fontSize + 4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          for (final chunk in chunks)
            Padding(
              padding: EdgeInsets.only(bottom: _paragraphSpacing),
              child: Text(
                chunk.text,
                style: style,
                textAlign: TextAlign.justify,
              ),
            ),
        ],
      ),
    );
  }

  /// 滚动模式：整章纵向滚动。
  Widget _buildScrollView(
    BuildContext context,
    ReaderPalette palette,
    ChapterContent chapter,
    String text,
  ) {
    final metrics = _metrics(MediaQuery.sizeOf(context));
    final horizontal = math.max(AppSpacing.xl, metrics.hPad);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // 点击正文区域切换操作栏（与主流阅读器一致）。
      onTap: toggleReaderUi,
      child: ListView(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
          horizontal,
          AppSpacing.lg,
          horizontal,
          AppSpacing.xxl,
        ),
        children: <Widget>[
          Text(
            chapter.title,
            style: AppTypography.title.copyWith(
              color: palette.text,
              fontSize: _settings.fontSize + 4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            // 段落之间保留空行，与渲染段落间距的视觉效果一致
            text.split('\n').join('\n'),
            style: _textStyle(palette),
          ),
          const SizedBox(height: AppSpacing.xxl),
          _chapterFooter(context, palette),
        ],
      ),
    );
  }

  Widget _chapterFooter(BuildContext context, ReaderPalette palette) {
    final l10n = context.l10n;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        TDButton(
          text: l10n.readerPrevChapter,
          type: TDButtonType.outline,
          size: TDButtonSize.small,
          disabled: _prevChapterId == null,
          onTap: () => _openChapter(_prevChapterId),
        ),
        TDButton(
          text: l10n.readerNextChapter,
          type: TDButtonType.outline,
          size: TDButtonSize.small,
          disabled: _nextChapterId == null,
          onTap: () => _openChapter(_nextChapterId),
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context, ReaderPalette palette) {
    final l10n = context.l10n;
    final index = _chapterIndex;
    final position = index >= 0 && _chapters.isNotEmpty
        ? l10n.readerChapterProgress(index + 1, _chapters.length)
        : (_chapter?.title ?? '');
    final pageInfo = _isPaged && _pages.isNotEmpty
        ? l10n.readerNovelPageProgress(_pageIndex + 1, _pages.length)
        : null;
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  position,
                  textAlign: TextAlign.center,
                  style: AppTypography.caption.copyWith(
                    color: palette.secondary,
                  ),
                ),
                if (pageInfo != null)
                  Text(
                    pageInfo,
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(
                      color: palette.secondary,
                    ),
                  ),
              ],
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

  /// 打开章节。[restorePercent] 为进入后的章内进度（百分数）：
  /// 回翻上一章时传 [_lastPagePercent]，使落点是该章最后一页。
  void _openChapter(String? chapterId, {int restorePercent = 0}) {
    if (chapterId == null) {
      return;
    }
    setState(() => _loadingChapter = true);
    _loadChapter(chapterId, restorePercent: restorePercent).ignore();
  }

  /// 章节目录。
  Future<void> _showChapterSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ChapterSheet(
        chapters: _chapters,
        currentId: _chapter?.id,
      ),
    );
    _keyboardFocus.requestFocus();
    if (selected != null && selected != _chapter?.id) {
      _openChapter(selected);
    }
  }

  /// 阅读设置。
  Future<void> _showSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ReaderSettingsSheet(
        settings: _settings,
        onChanged: (next) => _updateSettings((_) => next).ignore(),
      ),
    );
    _keyboardFocus.requestFocus();
  }
}

/// 章节目录弹层。
class _ChapterSheet extends StatelessWidget {
  const _ChapterSheet({required this.chapters, required this.currentId});

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

/// 阅读设置弹层。
///
/// 覆盖服务端网页阅读器的可调项：阅读模式 / 字号 / 行距 / 版心宽度 / 页边距 /
/// 首行缩进 / 翻页动画 / 章末自动下一章 / 配色。
class _ReaderSettingsSheet extends StatefulWidget {
  const _ReaderSettingsSheet({
    required this.settings,
    required this.onChanged,
  });

  final NovelReaderSettings settings;
  final ValueChanged<NovelReaderSettings> onChanged;

  @override
  State<_ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<_ReaderSettingsSheet> {
  late NovelReaderSettings _settings = widget.settings;

  void _apply(NovelReaderSettings next) {
    setState(() => _settings = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
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
            _choiceRow(
              context,
              label: l10n.readerMode,
              options: <_Option>[
                _Option(
                  l10n.readerModePaged,
                  _settings.mode == NovelReadMode.paged,
                  () => _apply(_settings.copyWith(mode: NovelReadMode.paged)),
                ),
                _Option(
                  l10n.readerModeScroll,
                  _settings.mode == NovelReadMode.scroll,
                  () => _apply(_settings.copyWith(mode: NovelReadMode.scroll)),
                ),
              ],
            ),
            _stepper(
              context,
              label: l10n.readerFontSize,
              value: _settings.fontSize.round().toString(),
              onDecrease: () => _apply(
                _settings.copyWith(fontSize: _settings.fontSize - 2),
              ),
              onIncrease: () => _apply(
                _settings.copyWith(fontSize: _settings.fontSize + 2),
              ),
            ),
            _stepper(
              context,
              label: l10n.readerLineHeight,
              value: _settings.lineHeight.toStringAsFixed(1),
              onDecrease: () => _apply(
                _settings.copyWith(lineHeight: _settings.lineHeight - 0.2),
              ),
              onIncrease: () => _apply(
                _settings.copyWith(lineHeight: _settings.lineHeight + 0.2),
              ),
            ),
            _choiceRow(
              context,
              label: l10n.readerContentWidth,
              options: <_Option>[
                _Option(
                  l10n.readerOptionNarrow,
                  _settings.contentWidth == ReaderContentWidth.narrow,
                  () => _apply(
                    _settings.copyWith(
                      contentWidth: ReaderContentWidth.narrow,
                    ),
                  ),
                ),
                _Option(
                  l10n.readerOptionMedium,
                  _settings.contentWidth == ReaderContentWidth.medium,
                  () => _apply(
                    _settings.copyWith(
                      contentWidth: ReaderContentWidth.medium,
                    ),
                  ),
                ),
                _Option(
                  l10n.readerOptionWide,
                  _settings.contentWidth == ReaderContentWidth.wide,
                  () => _apply(
                    _settings.copyWith(contentWidth: ReaderContentWidth.wide),
                  ),
                ),
              ],
            ),
            _choiceRow(
              context,
              label: l10n.readerPadding,
              options: <_Option>[
                _Option(
                  l10n.readerOptionNarrow,
                  _settings.padding == ReaderPadding.narrow,
                  () =>
                      _apply(_settings.copyWith(padding: ReaderPadding.narrow)),
                ),
                _Option(
                  l10n.readerOptionMedium,
                  _settings.padding == ReaderPadding.medium,
                  () =>
                      _apply(_settings.copyWith(padding: ReaderPadding.medium)),
                ),
                _Option(
                  l10n.readerOptionWide,
                  _settings.padding == ReaderPadding.wide,
                  () => _apply(_settings.copyWith(padding: ReaderPadding.wide)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _switchRow(
              context,
              label: l10n.readerIndent,
              value: _settings.indentFirstLine,
              onChanged: (value) =>
                  _apply(_settings.copyWith(indentFirstLine: value)),
            ),
            _switchRow(
              context,
              label: l10n.readerPageAnimation,
              value: _settings.pageAnimation,
              onChanged: (value) =>
                  _apply(_settings.copyWith(pageAnimation: value)),
            ),
            _switchRow(
              context,
              label: l10n.readerAutoNextChapter,
              value: _settings.autoNextChapter,
              onChanged: (value) =>
                  _apply(_settings.copyWith(autoNextChapter: value)),
            ),
            const SizedBox(height: AppSpacing.sm),
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
      ),
    );
  }

  Widget _stepper(
    BuildContext context, {
    required String label,
    required String value,
    required VoidCallback onDecrease,
    required VoidCallback onIncrease,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: AppTypography.body.copyWith(
                color: context.appColors.textPrimary,
              ),
            ),
          ),
          TDButton(
            text: '-',
            type: TDButtonType.outline,
            size: TDButtonSize.small,
            onTap: onDecrease,
          ),
          SizedBox(
            width: 56,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: context.appColors.textPrimary,
              ),
            ),
          ),
          TDButton(
            text: '+',
            type: TDButtonType.outline,
            size: TDButtonSize.small,
            onTap: onIncrease,
          ),
        ],
      ),
    );
  }

  Widget _choiceRow(
    BuildContext context, {
    required String label,
    required List<_Option> options,
  }) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 84,
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

  Widget _switchRow(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: AppTypography.body.copyWith(
                color: context.appColors.textPrimary,
              ),
            ),
          ),
          TDSwitch(
            isOn: value,
            size: TDSwitchSize.small,
            onChanged: (next) {
              onChanged(next);
              return next;
            },
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

/// 互斥选项。
class _Option {
  const _Option(this.label, this.selected, this.onSelect);

  final String label;
  final bool selected;
  final VoidCallback onSelect;
}
