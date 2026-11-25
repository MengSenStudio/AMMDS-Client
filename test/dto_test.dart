import 'package:ammds_client/data/dto/api_dto.dart';
import 'package:ammds_client/domain/entities/content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JsonReader', () {
    test('字符串 / 数字 / 布尔容错', () {
      expect(JsonReader.string('abc'), 'abc');
      expect(JsonReader.string(''), isNull);
      expect(JsonReader.string(12), '12');
      expect(JsonReader.integer('42'), 42);
      expect(JsonReader.integer(3.9), 3);
      expect(JsonReader.decimal('4.5'), 4.5);
      expect(JsonReader.boolean('true'), isTrue);
      expect(JsonReader.boolean('no'), isFalse);
      expect(JsonReader.boolean(0), isFalse);
      expect(JsonReader.boolean(null), isNull);
    });

    test('相对 URL 依据 base 解析为绝对地址', () {
      final uri = JsonReader.uri(
        '/static/covers/a.jpg',
        base: Uri.parse('http://192.168.1.10:8080/'),
      );
      expect(uri.toString(), 'http://192.168.1.10:8080/static/covers/a.jpg');
    });

    test('绝对 URL 原样保留', () {
      final uri = JsonReader.uri(
        'https://cdn.example.com/a.jpg',
        base: Uri.parse('http://192.168.1.10/'),
      );
      expect(uri.toString(), 'https://cdn.example.com/a.jpg');
    });
  });

  group('TokenDto', () {
    test('由 expires_in 推导过期时间', () {
      final now = DateTime(2026, 1, 1, 12);
      final dto = TokenDto.fromJson(<String, Object?>{
        'access_token': 'a',
        'refresh_token': 'r',
        'expires_in': 600,
      });
      final tokens = dto.toEntity(now: now);
      expect(tokens.accessToken, 'a');
      expect(tokens.refreshToken, 'r');
      expect(tokens.expiresAt, now.add(const Duration(seconds: 600)));
    });

    test('支持 expires_at 绝对时间', () {
      final dto = TokenDto.fromJson(<String, Object?>{
        'access_token': 'a',
        'expires_at': '2030-01-01T00:00:00.000Z',
      });
      expect(dto.toEntity().expiresAt, DateTime.utc(2030));
    });

    test('缺少访问令牌时抛出 DtoFormatException', () {
      expect(
        () => TokenDto.fromJson(<String, Object?>{'refresh_token': 'r'}),
        throwsA(isA<DtoFormatException>()),
      );
    });

    test('兼容驼峰字段名', () {
      final dto = TokenDto.fromJson(<String, Object?>{
        'accessToken': 'a',
        'refreshToken': 'r',
        'expiresIn': 30,
      });
      expect(dto.accessToken, 'a');
      expect(dto.refreshToken, 'r');
      expect(dto.expiresInSeconds, 30);
    });
  });

  group('LoginResponseDto', () {
    test('解析嵌套 token 与 user', () {
      final dto = LoginResponseDto.fromJson(<String, Object?>{
        'token': <String, Object?>{
          'access_token': 'a',
          'refresh_token': 'r',
          'expires_in': 60,
        },
        'user': <String, Object?>{
          'id': 'u1',
          'username': 'admin',
          'nickname': '管理员',
          'permissions': <String>['media:read'],
        },
      });
      final result = dto.toEntity(base: Uri.parse('http://host/'));
      expect(result.tokens.accessToken, 'a');
      expect(result.user.id, 'u1');
      expect(result.user.displayName, '管理员');
      expect(result.user.permissions, <String>['media:read']);
    });

    test('扁平结构也能解析', () {
      final dto = LoginResponseDto.fromJson(<String, Object?>{
        'access_token': 'flat',
        'refresh_token': 'r',
      });
      expect(dto.token.accessToken, 'flat');
      expect(dto.user, isNull);
      expect(dto.toEntity().user.username, '');
    });
  });

  group('UserDto', () {
    test('id 缺失时用用户名兜底', () {
      final user = UserDto.fromJson(<String, Object?>{'username': 'bob'});
      expect(user.id, 'bob');
    });

    test('身份完全缺失时抛出 DtoFormatException', () {
      expect(
        () => UserDto.fromJson(<String, Object?>{'nickname': 'x'}),
        throwsA(isA<DtoFormatException>()),
      );
    });
  });

  group('PageDto', () {
    test('解析 items + has_more + next_cursor', () {
      final dto = PageDto.fromJson<ContentItemDto>(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{'id': '1', 'title': 'A'},
          <String, Object?>{'id': '2', 'title': 'B'},
        ],
        'has_more': true,
        'next_cursor': 'cursor-2',
      }, ContentItemDto.fromJson);
      expect(dto.items, hasLength(2));
      expect(dto.hasMore, isTrue);
      expect(dto.nextCursor, 'cursor-2');
    });

    test('由 page/total/page_size 推导 hasMore', () {
      final firstPage = PageDto.fromJson<ContentItemDto>(<String, Object?>{
        'list': <Object?>[
          <String, Object?>{'id': '1', 'title': 'A'},
        ],
        'page': 1,
        'page_size': 1,
        'total': 2,
      }, ContentItemDto.fromJson);
      expect(firstPage.hasMore, isTrue);

      final lastPage = PageDto.fromJson<ContentItemDto>(<String, Object?>{
        'list': <Object?>[
          <String, Object?>{'id': '2', 'title': 'B'},
        ],
        'page': 2,
        'page_size': 1,
        'total': 2,
      }, ContentItemDto.fromJson);
      expect(lastPage.hasMore, isFalse);
    });

    test('裸数组响应也能解析', () {
      final dto = PageDto.fromJson<ContentItemDto>(<Object?>[
        <String, Object?>{'id': '1', 'title': 'A'},
      ], ContentItemDto.fromJson);
      expect(dto.items, hasLength(1));
      expect(dto.hasMore, isFalse);
    });

    test('转换为领域分页模型并映射元素', () {
      final dto = PageDto.fromJson<ContentItemDto>(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{'id': '1', 'title': 'A'},
        ],
        'has_more': true,
      }, ContentItemDto.fromJson);
      final page = dto.toEntity(
        (item) => ContentItem(id: item.id, title: item.title),
      );
      expect(page.items.single.title, 'A');
      expect(page.hasMore, isTrue);
    });

    test('空响应得到空分页', () {
      final dto = PageDto.fromJson<ContentItemDto>(
        null,
        ContentItemDto.fromJson,
      );
      expect(dto.items, isEmpty);
      expect(dto.hasMore, isFalse);
    });
  });

  group('ContentItemDto', () {
    test('兼容多种字段命名', () {
      final dto = ContentItemDto.fromJson(<String, Object?>{
        'uuid': 'x1',
        'name': '标题',
        'poster': '/p.jpg',
        'release_year': '2020',
        'score': '8.6',
        'genres': <String>['动作', '科幻'],
      });
      expect(dto.id, 'x1');
      expect(dto.title, '标题');
      expect(dto.year, 2020);
      expect(dto.rating, 8.6);
      expect(dto.categories, <String>['动作', '科幻']);
    });

    test('缺少标题时用 id 兜底', () {
      final dto = ContentItemDto.fromJson(<String, Object?>{'id': 'only-id'});
      expect(dto.title, 'only-id');
    });
  });

  group('ContentDetailDto', () {
    test('解析详情与章节', () {
      final dto = ContentDetailDto.fromJson(<String, Object?>{
        'detail': <String, Object?>{
          'id': 'n1',
          'title': '小说',
          'overview': '简介',
          'chapter_count': 3,
          'author': '作者',
          'chapters': <Object?>[
            <String, Object?>{'id': 'c1', 'title': '第一章', 'index': 1},
            <String, Object?>{'id': 'c2', 'title': '第二章', 'index': 2},
          ],
        },
      });
      final entity = dto.toEntity();
      expect(entity.item.title, '小说');
      expect(entity.overview, '简介');
      expect(entity.episodeCount, 3);
      expect(entity.author, '作者');
      expect(entity.chapters, hasLength(2));
      expect(entity.chapters.first.title, '第一章');
    });

    test('支持 summary / description 作为简介', () {
      expect(
        ContentDetailDto.fromJson(<String, Object?>{
          'id': 'x',
          'title': 't',
          'summary': 'S',
        }).overview,
        'S',
      );
      expect(
        ContentDetailDto.fromJson(<String, Object?>{
          'id': 'x',
          'title': 't',
          'description': 'D',
        }).overview,
        'D',
      );
    });
  });

  group('ChapterDto', () {
    test('解析章节字段', () {
      final dto = ChapterDto.fromJson(<String, Object?>{
        'chapter_id': 'c9',
        'chapter_name': '第九章',
        'order': 9,
      });
      expect(dto.id, 'c9');
      expect(dto.title, '第九章');
      expect(dto.index, 9);
    });
  });
}
