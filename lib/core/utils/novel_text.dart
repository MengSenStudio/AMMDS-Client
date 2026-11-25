/// 小说正文纯文本转换（文档 #39）。
///
/// 小说正文在服务端可能是 HTML（EPUB 导入 / 书源抓取结果）。
/// 新版服务端会同时下发纯文本 `text`；旧版服务端只有 HTML `content`，
/// 此时由客户端在此完成转换，保证阅读器在任何服务端版本下都能渲染正文。
library;

/// 小说正文转换工具。
abstract final class NovelTextParser {
  /// 段落级结束标签：转换为换行以保留段落结构。
  static final RegExp _blockBreak = RegExp(
    r'<\s*(br|/p|/div|/li|/h[1-6]|/tr|/section|/article)\s*/?>',
    caseSensitive: false,
  );

  /// 其余 HTML 标签。
  static final RegExp _tag = RegExp('<[^>]+>');

  /// 行内连续空白（不含换行）。
  static final RegExp _inlineSpace = RegExp(r'[^\S\n]+');

  /// 连续 3 个以上换行。
  static final RegExp _extraNewline = RegExp(r'\n{3,}');

  /// 把 HTML 正文转换为纯文本。
  static String? htmlToPlainText(String? html) {
    if (html == null || html.trim().isEmpty) {
      return null;
    }
    var text = html.replaceAll(_blockBreak, '\n');
    text = text.replaceAll(_tag, '');
    text = _decodeEntities(text);
    text = text
        .replaceAll('\u00a0', ' ')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    text = text.replaceAll(_inlineSpace, ' ');
    text = text
        .split('\n')
        .map((line) => line.trim())
        .join('\n');
    text = text.replaceAll(_extraNewline, '\n\n').trim();
    return text.isEmpty ? null : text;
  }

  /// 统计正文字数（忽略空白字符）。
  static int countWords(String? text) {
    if (text == null) {
      return 0;
    }
    return text.replaceAll(RegExp(r'\s+'), '').length;
  }

  /// 常见 HTML 实体解码。
  static String _decodeEntities(String input) {
    var text = input
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&mdash;', '—')
        .replaceAll('&hellip;', '…')
        .replaceAll('&amp;', '&');
    // 数字实体（&#123; / &#x1F600;）
    text = text.replaceAllMapped(RegExp(r'&#(x?[0-9a-fA-F]+);'), (match) {
      final raw = match.group(1)!;
      final code = raw.startsWith('x') || raw.startsWith('X')
          ? int.tryParse(raw.substring(1), radix: 16)
          : int.tryParse(raw);
      if (code == null || code <= 0 || code > 0x10FFFF) {
        return match.group(0)!;
      }
      return String.fromCharCode(code);
    });
    return text;
  }
}
