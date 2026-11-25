/// 服务端资源地址解析（文档 #46 / #71）。
///
/// 服务端数据库中的封面 / 海报 / 章节图片可能是：
///
/// * 远端绝对地址：`https://host/a.jpg`
/// * 根路径地址：`/static/a.jpg`
/// * 仓库相对路径：`data\images\a.jpg`（Windows 反斜杠）或 `data/images/a.jpg`
///
/// 三者都不能直接交给图片组件加载，必须统一转换为可访问的 URL：
/// 根路径按服务端地址补全，仓库相对路径走公开图片接口
/// `/api/pub/resource/image?path=<urlencode>`，远端绝对地址走服务端图片代理
/// `/api/pub/resource/proxyImage?url=<urlencode>`（与 Web 端规则一致）。
///
/// 新版服务端（`clientV1` 方言）已在响应中完成归一化，
/// 本工具主要服务于旧版服务端（`ammdsPublic` 方言）与本地兜底。
library;

/// 资源地址解析工具。
abstract final class ResourceUri {
  /// 公开图片读取接口路径。
  static const String imageEndpoint = '/api/pub/resource/image';

  /// 远端图片代理接口路径（**已登录**客户端专用）。
  ///
  /// 与免鉴权的公开代理 `/api/pub/resource/proxyImage` 是两个信任等级：公开代理只允许
  /// 公网地址、只接受 `Content-Type: image/*`、上限 5MB；自托管场景下图片常在同一局域网
  /// （NAS、Jellyfin、或解析到内网 IP 的域名），且不少图床把图片返回成
  /// `application/octet-stream`，用公开代理会整片 400 / 404——这正是「部分图片加载不出来」的成因。
  /// 已登录接口允许内网地址、按字节嗅探图片类型、上限 32MB。
  ///
  /// 外链封面普遍有防盗链：浏览器带 `Referer` 与浏览器 UA 能取到，客户端（`dart:io`）两者都没有，
  /// 会被源站直接拒绝；这类图床在国内也常属于「被墙」地址。交给服务端转发与 Web 端保持一致，
  /// 避免「同一份数据 Web 端能看、客户端只显示占位图」。
  static const String proxyEndpoint = '/api/client/v1/resource/proxyImage';

  /// 当前访问令牌的**同步**读取器。
  ///
  /// 图片由 `Image.network` 直接加载，无法自定义请求头，只能把令牌放进 URL；
  /// 令牌的唯一事实来源是会话层，由组合根（app_container）在启动时注入，
  /// 这样本工具不必反向依赖会话层，也不用把令牌一路穿过 DTO 映射。
  /// 未登录时为 null，此时远端图片仍会走代理，只是不带令牌（服务端会拒绝，客户端显示占位图）。
  static String? Function()? accessTokenReader;

  /// 远端资源的**直连**地址；不会被代理时返回 null。
  ///
  /// 用途：服务端代理并非总能取到图——图床可能在服务端所在网络被屏蔽，
  /// 而手机能访问（反之亦然）。这时客户端直连原地址仍然显示得出来，
  /// 所以 [resolve] 之外再提供一份「未经代理」的地址，供图片组件在代理失败时回退。
  ///
  /// 只在 [value] 是远端 http(s) 地址、且 [resolve] 确实会代理它时才返回；
  /// 仓库内相对路径、data URI、服务端自身地址都返回 null（没有可用的直连地址）。
  static Uri? direct(Object? value, {Uri? base}) {
    final raw = _text(value);
    if (raw == null) {
      return null;
    }
    final lower = raw.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return null;
    }
    final remote = Uri.tryParse(raw);
    if (remote == null) {
      return null;
    }
    // 与 resolve 保持一致：同源地址不会被代理，也就无所谓回退
    if (base == null || _isSameEndpoint(remote, base)) {
      return null;
    }
    return remote;
  }

  /// 把服务端返回的资源值解析为可访问地址。
  ///
  /// [base] 为服务端根地址；为 null 时仅返回解析结果（可能是相对地址）。
  static Uri? resolve(Object? value, {Uri? base}) {
    final raw = _text(value);
    if (raw == null) {
      return null;
    }
    final lower = raw.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      final remote = Uri.tryParse(raw);
      if (remote == null) {
        return null;
      }
      // 服务端自身的地址（含已归一化的公开图片接口）无需再代理，
      // 否则会变成「服务端代理自己」的白跑一趟。
      if (base == null || _isSameEndpoint(remote, base)) {
        return remote;
      }
      return base.resolveUri(_proxyFor(raw));
    }
    if (raw.startsWith('data:')) {
      return Uri.tryParse(raw);
    }
    if (raw.startsWith('/')) {
      final parsed = Uri.tryParse(raw);
      if (parsed == null) {
        return null;
      }
      return base == null ? parsed : base.resolveUri(parsed);
    }
    // 仓库相对路径：反斜杠统一为正斜杠后交给公开图片接口
    final relative = Uri(
      path: imageEndpoint,
      queryParameters: <String, String>{'path': raw.replaceAll('\\', '/')},
    );
    return base == null ? relative : base.resolveUri(relative);
  }

  /// 把 JSON 中的字符串列表解析为可访问地址列表。
  static List<Uri> resolveAll(Object? value, {Uri? base}) {
    if (value is! List) {
      return const <Uri>[];
    }
    final result = <Uri>[];
    for (final item in value) {
      final uri = resolve(item, base: base);
      if (uri != null) {
        result.add(uri);
      }
    }
    return result;
  }

  /// 组装远端图片代理地址（相对服务端根路径）。
  ///
  /// 令牌通过 query 传递：图片由 `Image.network` 加载，无法自定义请求头。
  /// 未登录时仍会发出不带令牌的地址，由服务端按未授权处理。
  static Uri _proxyFor(String raw) {
    final token = accessTokenReader?.call();
    return Uri(
      path: proxyEndpoint,
      queryParameters: <String, String>{
        'url': raw,
        if (token != null && token.isNotEmpty) 'token': token,
      },
    );
  }

  /// 判断两个地址是否指向同一服务端端点（协议 + 主机 + 端口）。
  static bool _isSameEndpoint(Uri uri, Uri base) =>
      uri.scheme == base.scheme &&
      uri.host == base.host &&
      uri.port == base.port;

  static String? _text(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value is String ? value.trim() : '$value'.trim();
    return text.isEmpty ? null : text;
  }
}
