import 'package:ammds_client/core/utils/novel_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NovelTextParser', () {
    test('段落标签转为换行并剥离标签', () {
      expect(
        NovelTextParser.htmlToPlainText('<p>第一段</p><p>第二段</p>'),
        '第一段\n第二段',
      );
    });

    test('br 标签转为换行', () {
      expect(NovelTextParser.htmlToPlainText('上<br/>下'), '上\n下');
    });

    test('HTML 实体解码且 nbsp 归一化为空格', () {
      expect(
        NovelTextParser.htmlToPlainText('A&amp;B &quot;C&quot;&nbsp;空格'),
        'A&B "C" 空格',
      );
    });

    test('数字实体解码', () {
      expect(NovelTextParser.htmlToPlainText('&#20013;&#x6587;'), '中文');
    });

    test('行内空白折叠并去除行首尾空白', () {
      expect(
        NovelTextParser.htmlToPlainText('<div>  一   二 </div><div> 三 </div>'),
        '一 二\n三',
      );
    });

    test('连续空行折叠为单个空行', () {
      expect(
        NovelTextParser.htmlToPlainText('<p>一</p><br/><br/><br/><p>二</p>'),
        '一\n\n二',
      );
    });

    test('纯文本原样返回', () {
      expect(NovelTextParser.htmlToPlainText('纯文本正文'), '纯文本正文');
    });

    test('空白正文返回 null', () {
      expect(NovelTextParser.htmlToPlainText(null), isNull);
      expect(NovelTextParser.htmlToPlainText(''), isNull);
      expect(NovelTextParser.htmlToPlainText('<p>   </p>'), isNull);
    });

    test('字数统计忽略空白字符', () {
      expect(NovelTextParser.countWords('一 二\n三 四'), 4);
      expect(NovelTextParser.countWords(null), 0);
      expect(NovelTextParser.countWords('   '), 0);
    });
  });
}
