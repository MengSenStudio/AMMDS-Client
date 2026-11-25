import 'dart:io';

import 'package:ammds_client/core/network/network_client.dart';
import 'package:ammds_client/data/api/ammds_public_api.dart';
import 'package:ammds_client/data/repositories/repositories.dart';
import 'package:ammds_client/domain/entities/content.dart';
import 'package:ammds_client/domain/entities/server.dart';
import 'package:ammds_client/domain/repositories/repositories.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真实服务端「公开接口方言」联调测试。
///
/// 与 `live_backend_test.dart`（Client API + 登录）不同，本用例**不需要账号**，
/// 直接走 `/api/pub/**` 公开接口读取内容，因此可以：
///
/// * 在无法获得测试账号的部署（例如已有生产数据的环境）上验证客户端数据链路；
/// * 验证「真实刮削数据」的兼容性：封面 / 章节图片可能是仓库相对路径，
///   正文可能是 HTML —— 这两种形态都必须能被客户端正确解析。
///
/// 默认 `127.0.0.1:18099`，可用 `AMMDS_E2E_HOST` / `AMMDS_E2E_PORT` 覆盖；
/// 服务端不可达时整组用例跳过。
void main() {
  final host = Platform.environment['AMMDS_E2E_HOST'] ?? '127.0.0.1';
  final port =
      int.tryParse(Platform.environment['AMMDS_E2E_PORT'] ?? '') ?? 18099;

  late bool backendReachable;
  late NetworkClient network;
  late ContentRepository content;

  setUpAll(() async {
    backendReachable = await _isReachable(host, port);
    if (!backendReachable) {
      // ignore: avoid_print
      print('[live-pub] 后端 http://$host:$port 不可达，公开接口联调用例将跳过');
      return;
    }
    final server = ServerProfile(
      id: 'live-public',
      name: 'Live AMMDS',
      host: host,
      port: port,
      dialect: 'ammds-public',
    );
    network = DioNetworkClient(baseUrl: server.baseUri.toString());
    final api = AmmdsPublicApi(network: network, server: server);
    content = ContentRepositoryImpl(apiFactory: () => api);
  });

  tearDownAll(() => network.close());

  test('公开接口：小说列表 → 详情 → 章节正文（含真实 HTML 正文转换）', () async {
    if (!backendReachable) {
      return;
    }

    final novels = await content.list(ContentKind.novel, pageSize: 5);
    expect(novels.items, isNotNull);
    if (novels.items.isEmpty) {
      // ignore: avoid_print
      print('[live-pub] 小说库为空，跳过');
      return;
    }

    final bookId = novels.items.first.id;
    final detail = await content.detail(ContentKind.novel, bookId);
    expect(detail.chapters, isNotEmpty, reason: '小说详情应包含章节目录');

    // 取一个靠后的章节：第一章通常是书名页，正文为空
    final chapterIndex = detail.chapters.length > 3 ? 3 : 0;
    final chapter = await content.novelChapterContent(
      bookId,
      detail.chapters[chapterIndex].id,
    );
    // ignore: avoid_print
    print(
      '[live-pub] 小说: ${detail.item.title} 章节=${detail.chapters.length} '
      '样本章节=${chapter.title} hasContent=${chapter.hasContent} '
      'words=${chapter.wordCount} textLen=${chapter.text?.length ?? 0}',
    );
    if (chapter.hasContent) {
      expect(chapter.text!.trim(), isNotEmpty);
      expect(
        chapter.text,
        isNot(contains('<')),
        reason: '客户端应把 HTML 正文转换为纯文本',
      );
    }
  });

  test('公开接口：漫画列表 → 详情 → 章节图片（相对路径图片可访问）', () async {
    if (!backendReachable) {
      return;
    }

    final comics = await content.list(ContentKind.comic, pageSize: 5);
    expect(comics.items, isNotNull);
    if (comics.items.isEmpty) {
      // ignore: avoid_print
      print('[live-pub] 漫画库为空，跳过');
      return;
    }

    final albumId = comics.items.first.id;
    final detail = await content.detail(ContentKind.comic, albumId);
    expect(detail.chapters, isNotEmpty, reason: '漫画详情应包含章节目录');

    // 选第一个有图片的章节
    ComicChapterPages? pages;
    for (final chapter in detail.chapters) {
      final candidate = await content.comicChapterPages(albumId, chapter.id);
      if (candidate.pages.isNotEmpty) {
        pages = candidate;
        break;
      }
    }
    if (pages == null) {
      // ignore: avoid_print
      print('[live-pub] 漫画章节均无图片，跳过');
      return;
    }

    final image = pages.pages.first.imageUri;
    expect(image.hasScheme, isTrue, reason: '图片地址应被解析为绝对地址');
    final fetched = await _fetchBytes(image);
    expect(fetched, isNotNull, reason: '章节图片应可下载: $image');
    expect(fetched!.mimeType, startsWith('image/'));
    // ignore: avoid_print
    print(
      '[live-pub] 漫画: ${detail.item.title} 章节=${detail.chapters.length} '
      '样本章节=${pages.title} pages=${pages.pageCount} '
      'image=$image bytes=${fetched.length} type=${fetched.mimeType}',
    );
  });

  test('公开接口：影视 / 人物详情与封面资源', () async {
    if (!backendReachable) {
      return;
    }

    for (final kind in <ContentKind>[ContentKind.media, ContentKind.people]) {
      final list = await content.list(kind, pageSize: 5);
      if (list.items.isEmpty) {
        // ignore: avoid_print
        print('[live-pub] ${kind.pathSegment} 列表为空，跳过');
        continue;
      }
      final item = list.items.first;
      final detail = await content.detail(kind, item.id);
      expect(detail.item.title, isNotEmpty);
      final cover = detail.item.coverUri;
      String coverInfo = 'cover=null';
      if (cover != null) {
        expect(cover.hasScheme, isTrue);
        final fetched = await _fetchBytes(cover);
        coverInfo =
            'cover=$cover bytes=${fetched?.length ?? 0} type=${fetched?.mimeType ?? '-'}';
      }
      // ignore: avoid_print
      print(
        '[live-pub] ${kind.pathSegment}: ${detail.item.title} '
        'attributes=${detail.attributes.length} gallery=${detail.gallery.length} '
        'related=${detail.related.length} $coverInfo',
      );
    }
  });
}

/// 图片下载结果。
final class _Fetched {
  const _Fetched(this.length, this.mimeType);

  final int length;
  final String mimeType;
}

Future<_Fetched?> _fetchBytes(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    var length = 0;
    await for (final chunk in response) {
      length += chunk.length;
    }
    if (response.statusCode != 200) {
      return null;
    }
    return _Fetched(length, response.headers.contentType?.mimeType ?? '');
  } on Object {
    return null;
  } finally {
    client.close();
  }
}

Future<bool> _isReachable(String host, int port) async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final request = await client.getUrl(
      Uri.parse('http://$host:$port/api/client/v1/health'),
    );
    final response = await request.close();
    await response.drain<void>();
    client.close();
    return response.statusCode == 200;
  } on Object {
    return false;
  }
}
