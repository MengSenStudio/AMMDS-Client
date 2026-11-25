import 'package:ammds_client/data/dto/api_dto.dart';
import 'package:flutter_test/flutter_test.dart';

/// 阅读器相关 DTO 解析测试（文档 #39 / #40）。
///
/// 同时覆盖 Client API（服务端已归一化）与既有公开接口（返回原始字段）两种形态。
void main() {
  final base = Uri.parse('http://192.168.1.10:8080/');

  group('ChapterContentDto', () {
    test('解析 Client API 形态（含纯文本与相邻章节）', () {
      final dto = ChapterContentDto.fromJson(<String, Object?>{
        'id': 'c2',
        'book_id': 'n1',
        'title': '第二章',
        'index': 2,
        'content': '<p>正文</p>',
        'text': '正文',
        'word_count': 2,
        'has_content': true,
        'from_source': false,
        'prev_id': 'c1',
        'next_id': 'c3',
      });

      final entity = dto.toEntity();
      expect(entity.id, 'c2');
      expect(entity.bookId, 'n1');
      expect(entity.index, 2);
      expect(entity.text, '正文');
      expect(entity.hasContent, isTrue);
      expect(entity.prevId, 'c1');
      expect(entity.nextId, 'c3');
    });

    test('解析既有公开接口形态（HTML 正文由客户端转换）', () {
      final dto = ChapterContentDto.fromJson(<String, Object?>{
        'id': 'c1',
        'bookId': 'n1',
        'title': '第一章',
        'sort': 1,
        'wordCount': 4,
        'content': '<p>甲</p><p>乙</p>',
        'fromSource': true,
        'contentLoaded': true,
      });

      final entity = dto.toEntity();
      expect(entity.text, '甲\n乙');
      expect(entity.hasContent, isTrue);
      expect(entity.fromSource, isTrue);
      expect(entity.index, 1);
    });

    test('缺少正文时标记为无内容', () {
      final entity = ChapterContentDto.fromJson(<String, Object?>{
        'id': 'c9',
        'title': '空章节',
      }).toEntity();
      expect(entity.hasContent, isFalse);
      expect(entity.text, isNull);
      expect(entity.wordCount, 0);
    });

    test('缺少章节 ID 时抛 DtoFormatException', () {
      expect(
        () => ChapterContentDto.fromJson(<String, Object?>{'title': '未知'}),
        throwsA(isA<DtoFormatException>()),
      );
    });
  });

  group('ComicChapterPagesDto', () {
    test('解析 Client API 形态并解析图片地址', () {
      final dto = ComicChapterPagesDto.fromJson(<String, Object?>{
        'chapter_id': 'cc1',
        'chapter_title': '第一话',
        'album_id': 'a1',
        'index': 1,
        'page_count': 2,
        'pages': <Object?>[
          <String, Object?>{'sequence': 1, 'image': 'data/images/1.jpg'},
          <String, Object?>{'sequence': 2, 'image': 'https://cdn/2.jpg'},
        ],
        'prev_id': null,
        'next_id': 'cc2',
      });

      final entity = dto.toEntity(base: base);
      expect(entity.chapterId, 'cc1');
      expect(entity.albumId, 'a1');
      expect(entity.pageCount, 2);
      expect(
        entity.pages.first.imageUri.toString(),
        'http://192.168.1.10:8080/api/pub/resource/image?path=data%2Fimages%2F1.jpg',
      );
      expect(
        entity.pages.last.imageUri.toString(),
        'http://192.168.1.10:8080/api/client/v1/resource/proxyImage'
        '?url=https%3A%2F%2Fcdn%2F2.jpg',
      );
      expect(entity.nextId, 'cc2');
    });

    test('解析既有公开接口形态（imagePath 字段）', () {
      final dto = ComicChapterPagesDto.fromJson(<String, Object?>{
        'chapterId': 'cc2',
        'chapterTitle': '第二话',
        'pages': <Object?>[
          <String, Object?>{'sequence': 1, 'imagePath': r'data\images\2.jpg'},
        ],
      });

      final entity = dto.toEntity(base: base);
      expect(entity.chapterId, 'cc2');
      expect(entity.title, '第二话');
      expect(
        entity.pages.single.imageUri.toString(),
        'http://192.168.1.10:8080/api/pub/resource/image?path=data%2Fimages%2F2.jpg',
      );
    });

    test('空白图片地址被跳过', () {
      final entity = ComicChapterPagesDto.fromJson(<String, Object?>{
        'chapter_id': 'cc1',
        'pages': <Object?>[
          <String, Object?>{'sequence': 1, 'image': ''},
          <String, Object?>{'sequence': 2, 'image': '/static/2.jpg'},
        ],
      }).toEntity(base: base);
      expect(entity.pageCount, 1);
      expect(entity.pages.single.sequence, 2);
    });
  });

  group('ContentDetailDto', () {
    test('解析扩展属性 / 图集 / 关联内容', () {
      final dto = ContentDetailDto.fromJson(<String, Object?>{
        'id': 'actor-1',
        'title': '演员甲',
        'attributes': <String, Object?>{
          'height_cm': 170,
          'retired': false,
          'social_links': <String, Object?>{'x': 'https://x'},
        },
        'gallery': <String>['data/images/a.jpg'],
        'related': <Object?>[
          <String, Object?>{'id': 'movie-1', 'title': '参演影片'},
        ],
      });

      final entity = dto.toEntity(base: base);
      expect(entity.attributes['height_cm'], '170');
      expect(entity.attributes['retired'], 'false');
      // 嵌套结构不作为属性展示
      expect(entity.attributes.containsKey('social_links'), isFalse);
      expect(
        entity.gallery.single.toString(),
        'http://192.168.1.10:8080/api/pub/resource/image?path=data%2Fimages%2Fa.jpg',
      );
      expect(entity.related.single.id, 'movie-1');
    });
  });

  group('真实数据兼容（既有公开接口形态）', () {
    test('小说详情：书籍字段嵌套在 book 内，章节列表在根上', () {
      final dto = ContentDetailDto.fromJson(<String, Object?>{
        'book': <String, Object?>{
          'id': 'n1',
          'title': '斗破苍穹',
          'author': '天蚕土豆',
          'description': '简介内容',
          'cover': 'data/images/novel/cover/a.jpg',
          'chapterCount': 1677,
        },
        'chapters': <Object?>[
          <String, Object?>{'id': 'c1', 'title': '第一章', 'sort': 1},
        ],
      });

      final entity = dto.toEntity(base: base);
      expect(entity.item.id, 'n1');
      expect(entity.item.title, '斗破苍穹');
      expect(entity.item.subtitle, '天蚕土豆');
      expect(entity.overview, '简介内容');
      expect(entity.author, '天蚕土豆');
      expect(entity.episodeCount, 1677);
      expect(entity.chapters.single.title, '第一章');
      expect(
        entity.item.coverUri.toString(),
        'http://192.168.1.10:8080/api/pub/resource/image?path=data%2Fimages%2Fnovel%2Fcover%2Fa.jpg',
      );
    });

    test('影视海报为多值列表时取首个地址', () {
      final dto = ContentItemDto.fromJson(<String, Object?>{
        'id': 'm1',
        'titleCn': '测试影片',
        'originalTitle': 'Test Movie',
        'poster': <String?>[null, 'data/images/actor/a.jpg', 'data/images/actor/b.jpg'],
      });

      final entity = dto.toEntity(base: base);
      expect(entity.title, '测试影片');
      expect(entity.subtitle, 'Test Movie');
      expect(
        entity.coverUri.toString(),
        'http://192.168.1.10:8080/api/pub/resource/image?path=data%2Fimages%2Factor%2Fa.jpg',
      );
    });

    test('影视详情：简介取 plotCn，导演列表取首值', () {
      final dto = ContentDetailDto.fromJson(<String, Object?>{
        'id': 'm1',
        'titleCn': '测试影片',
        'plotCn': '剧情简介',
        'director': <String>['导演甲', '导演乙'],
        'poster': <String>['data/images/a.jpg'],
      });

      final entity = dto.toEntity(base: base);
      expect(entity.overview, '剧情简介');
      expect(entity.author, '导演甲');
      expect(
        entity.item.coverUri.toString(),
        'http://192.168.1.10:8080/api/pub/resource/image?path=data%2Fimages%2Fa.jpg',
      );
    });
  });
}
