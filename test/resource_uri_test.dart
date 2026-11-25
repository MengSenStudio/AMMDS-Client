import 'package:ammds_client/core/utils/resource_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = Uri.parse('http://192.168.1.10:8080/');

  setUp(() {
    // 令牌读取器是全局注入点，测试里显式清空，保证与运行环境无关
    ResourceUri.accessTokenReader = null;
  });

  tearDown(() {
    ResourceUri.accessTokenReader = null;
  });

  group('ResourceUri', () {
    test('远端地址改写为服务端已登录图片代理（防盗链 / 被墙 / 内网图床）', () {
      // 真实数据里的外链封面形如 http://pics.dmm.co.jp//digital/video/x/xpl.jpg：
      // 客户端没有 Referer 与浏览器 UA，直接请求会被源站拒绝；
      // 而自托管场景下图片也可能在同一局域网，免鉴权的公开代理会按 SSRF 规则拒掉内网地址。
      // 因此统一交给需登录的 /api/client/v1/resource/proxyImage 转发。
      expect(
        ResourceUri.resolve('https://cdn.example.com/a.jpg', base: base)
            .toString(),
        'http://192.168.1.10:8080/api/client/v1/resource/proxyImage'
        '?url=https%3A%2F%2Fcdn.example.com%2Fa.jpg',
      );
      expect(
        ResourceUri.resolve(
          'http://pics.dmm.co.jp//digital/video/a/apl.jpg',
          base: base,
        ).toString(),
        'http://192.168.1.10:8080/api/client/v1/resource/proxyImage'
        '?url=http%3A%2F%2Fpics.dmm.co.jp%2F%2Fdigital%2Fvideo%2Fa%2Fapl.jpg',
      );
      // 内网图床（NAS / Jellyfin）同样走代理，由服务端放行内网地址
      expect(
        ResourceUri.resolve(
          'http://192.168.1.20:8096/Items/1/Images/Primary',
          base: base,
        ).toString(),
        'http://192.168.1.10:8080/api/client/v1/resource/proxyImage'
        '?url=http%3A%2F%2F192.168.1.20%3A8096%2FItems%2F1%2FImages%2FPrimary',
      );
    });

    test('有令牌时把令牌带进代理地址（图片无法自定义请求头）', () {
      ResourceUri.accessTokenReader = () => 'jwt-abc';
      final uri = ResourceUri.resolve(
        'https://cdn.example.com/a.jpg',
        base: base,
      );
      expect(uri!.path, '/api/client/v1/resource/proxyImage');
      expect(uri.queryParameters['url'], 'https://cdn.example.com/a.jpg');
      expect(uri.queryParameters['token'], 'jwt-abc');
    });

    test('无令牌或空令牌时不追加 token 参数', () {
      expect(
        ResourceUri.resolve('https://cdn.example.com/a.jpg', base: base)
            ?.queryParameters
            .containsKey('token'),
        isFalse,
      );
      ResourceUri.accessTokenReader = () => '';
      expect(
        ResourceUri.resolve('https://cdn.example.com/a.jpg', base: base)
            ?.queryParameters
            .containsKey('token'),
        isFalse,
      );
    });

    test('服务端自身地址不再重复代理', () {
      expect(
        ResourceUri.resolve(
          'http://192.168.1.10:8080/api/pub/resource/image?path=a.jpg',
          base: base,
        ).toString(),
        'http://192.168.1.10:8080/api/pub/resource/image?path=a.jpg',
      );
    });

    test('未提供服务端地址时远端地址原样保留', () {
      expect(
        ResourceUri.resolve('https://cdn.example.com/a.jpg').toString(),
        'https://cdn.example.com/a.jpg',
      );
    });

    test('根路径依据服务端地址补全', () {
      expect(
        ResourceUri.resolve('/static/covers/a.jpg', base: base).toString(),
        'http://192.168.1.10:8080/static/covers/a.jpg',
      );
    });

    test('仓库相对路径改写为公开图片接口', () {
      expect(
        ResourceUri.resolve('data/images/a.jpg', base: base).toString(),
        'http://192.168.1.10:8080/api/pub/resource/image?path=data%2Fimages%2Fa.jpg',
      );
    });

    test('Windows 反斜杠路径归一化为正斜杠', () {
      expect(
        ResourceUri.resolve(r'data\images\comic\1.jpg', base: base).toString(),
        'http://192.168.1.10:8080/api/pub/resource/image?path=data%2Fimages%2Fcomic%2F1.jpg',
      );
    });

    test('空值返回 null', () {
      expect(ResourceUri.resolve(null), isNull);
      expect(ResourceUri.resolve(''), isNull);
      expect(ResourceUri.resolve('   '), isNull);
    });

    test('直连地址只在确实会被代理时返回（供图片代理失败时回退）', () {
      // 会被代理的远端地址：给出未代理的原地址
      expect(
        ResourceUri.direct('https://raw.githubusercontent.com/a/b.jpg', base: base)
            .toString(),
        'https://raw.githubusercontent.com/a/b.jpg',
      );
      // 服务端自身地址不会被代理，不需要回退
      expect(
        ResourceUri.direct(
          'http://192.168.1.10:8080/api/pub/resource/image?path=a.jpg',
          base: base,
        ),
        isNull,
      );
      // 仓库相对路径没有可直连的地址
      expect(ResourceUri.direct('data/images/a.jpg', base: base), isNull);
      expect(ResourceUri.direct('data/images/a.jpg'), isNull);
      // 没有服务端地址时远端地址本就原样使用，无需回退
      expect(ResourceUri.direct('https://a.jpg'), isNull);
      // 非图片地址与空值
      expect(ResourceUri.direct('data:image/png;base64,AAAA', base: base), isNull);
      expect(ResourceUri.direct(null, base: base), isNull);
      expect(ResourceUri.direct('  ', base: base), isNull);
    });

    test('列表解析保持顺序并剔除空值', () {
      final uris = ResourceUri.resolveAll(
        <Object?>['https://a.jpg', '', 'data/b.jpg'],
        base: base,
      );
      expect(uris.length, 2);
      expect(
        uris.first.toString(),
        'http://192.168.1.10:8080/api/client/v1/resource/proxyImage'
        '?url=https%3A%2F%2Fa.jpg',
      );
      expect(
        uris.last.toString(),
        'http://192.168.1.10:8080/api/pub/resource/image?path=data%2Fb.jpg',
      );
    });
  });
}
