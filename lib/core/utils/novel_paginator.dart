import 'package:flutter/painting.dart';

/// 分页后的一段正文。
///
/// 一「页」是若干段的集合：段落可能跨页，因此同一段会被切成多个片段，
/// [isParagraphStart] 用于判断是否需要加首行缩进。
final class NovelPageChunk {
  /// 创建片段。
  const NovelPageChunk({
    required this.text,
    required this.paragraphIndex,
    required this.isParagraphStart,
  });

  /// 片段文本（已包含可能的首行缩进前缀）。
  final String text;

  /// 所属段落下标。
  final int paragraphIndex;

  /// 是否为该段落的起始片段。
  final bool isParagraphStart;
}

/// 小说分页器。
///
/// 服务端网页阅读器依靠 CSS 多栏（`column-width` + `transform`）让浏览器完成分栏，
/// Flutter 没有等价能力，因此这里用 [TextPainter] 实测排版结果并切分：
///
/// * 以 [maxWidth] / [maxHeight] 描述一页的排版区域；
/// * 逐段测量，段内用**二分查找**定位「当前页还放得下多少字符」，
///   保证切分结果与实际渲染高度一致（不会出现末行被裁掉）；
/// * 每段之间保留 [paragraphSpacing]，与渲染时的段间距保持一致；
/// * 需要首行缩进时，在段落起始片段前拼上 [indent]（渲染侧不再做缩进处理），
///   使「测量」与「渲染」使用完全相同的字符串与样式。
///
/// 该类是纯计算，不持有任何状态，便于单元测试与复用。
abstract final class NovelPaginator {
  /// 执行分页。
  ///
  /// [paragraphs] 为按顺序排列的段落文本（空段落会被跳过）。
  /// [firstPageHeaderHeight] 用于在首页顶部预留标题等区域的高度。
  /// 返回值为「页 → 片段列表」，至少一页。
  static List<List<NovelPageChunk>> paginate({
    required List<String> paragraphs,
    required TextStyle style,
    required TextScaler textScaler,
    required double maxWidth,
    required double maxHeight,
    required double paragraphSpacing,
    required String indent,
    required bool indentFirstLine,
    double firstPageHeaderHeight = 0,
    TextAlign textAlign = TextAlign.justify,
  }) {
    final pages = <List<NovelPageChunk>>[];
    if (maxWidth <= 0 || maxHeight <= 0) {
      return pages;
    }
    final firstPageHeight = maxHeight - firstPageHeaderHeight;
    var page = <NovelPageChunk>[];
    var remaining = firstPageHeight > 0 ? firstPageHeight : maxHeight;

    void flushPage() {
      if (page.isEmpty) {
        return;
      }
      pages.add(page);
      page = <NovelPageChunk>[];
      remaining = maxHeight;
    }

    for (var index = 0; index < paragraphs.length; index++) {
      final paragraph = paragraphs[index];
      if (paragraph.trim().isEmpty) {
        continue;
      }
      var offset = 0;
      var isStart = true;
      while (offset < paragraph.length) {
        final prefix = isStart && indentFirstLine ? indent : '';
        final prefixLength = prefix.length;
        final measured = '$prefix${paragraph.substring(offset)}';

        // 为段间距预留空间：段与段之间不留白会显得挤在一起
        final fitHeight = remaining - paragraphSpacing;
        final height = _measure(measured, style, textScaler, maxWidth, textAlign);
        if (height <= fitHeight) {
          page.add(
            NovelPageChunk(
              text: measured,
              paragraphIndex: index,
              isParagraphStart: isStart,
            ),
          );
          remaining -= height + paragraphSpacing;
          break;
        }

        var end = _fitEnd(
          measured,
          style: style,
          textScaler: textScaler,
          maxWidth: maxWidth,
          fitHeight: fitHeight,
          textAlign: textAlign,
        );
        // 至少要消费一个正文字符，否则会死循环
        if (end <= prefixLength) {
          end = (prefixLength + 1).clamp(0, measured.length);
        }
        if (page.isEmpty && end <= prefixLength) {
          // 单页容不下一个正文字符（极端窄高场景）：放弃分页，整段留给下一页
          flushPage();
          continue;
        }
        final chunk = measured.substring(0, end);
        page.add(
          NovelPageChunk(
            text: chunk,
            paragraphIndex: index,
            isParagraphStart: isStart,
          ),
        );
        remaining -= _measure(chunk, style, textScaler, maxWidth, textAlign) +
            paragraphSpacing;
        offset += end - prefixLength;
        isStart = false;
        // 当前页已写满，后续内容从新的一页开始
        flushPage();
      }
    }
    flushPage();
    return pages;
  }

  /// 二分查找「前缀放得下」的最大字符数。
  static int _fitEnd(
    String text, {
    required TextStyle style,
    required TextScaler textScaler,
    required double maxWidth,
    required double fitHeight,
    required TextAlign textAlign,
  }) {
    if (fitHeight <= 0) {
      return 0;
    }
    var low = 1;
    var high = text.length;
    var best = 0;
    while (low <= high) {
      final mid = low + ((high - low) >> 1);
      final height = _measure(
        text.substring(0, mid),
        style,
        textScaler,
        maxWidth,
        textAlign,
      );
      if (height <= fitHeight) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return best;
  }

  /// 测量一段文本在给定宽度下的渲染高度。
  static double _measure(
    String text,
    TextStyle style,
    TextScaler textScaler,
    double maxWidth,
    TextAlign textAlign,
  ) {
    if (text.isEmpty) {
      return 0;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }
}
