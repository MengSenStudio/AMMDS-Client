/// 开屏配置（文档 #14 / #65）。
///
/// 契约来自服务端 `GET /api/client/v1/splash`：服务端只负责告知「放什么」，
/// 具体怎么渲染由客户端决定。服务端不可达或未配置时使用 [SplashConfig.local]
/// 的本地官方兜底，因此开屏永远可展示。
library;

/// 开屏类型。
///
/// 只有 [ad] 需要右上角跳过按钮；AMMDS 官方开屏不允许跳过。
enum SplashKind {
  /// AMMDS 官方开屏（品牌展示）。
  official,

  /// 开屏广告（第三方内容）。
  ad;

  /// 由服务端字符串解析。
  static SplashKind parse(String? raw) =>
      raw?.toLowerCase() == 'ad' ? SplashKind.ad : SplashKind.official;
}

/// 官方开屏的形态。
enum SplashOfficialStyle {
  /// 3D Logo 动画。
  rotate3d,

  /// 静态品牌页。
  static;

  /// 由服务端字符串解析。
  static SplashOfficialStyle parse(String? raw) =>
      raw?.toLowerCase() == 'static'
      ? SplashOfficialStyle.static
      : SplashOfficialStyle.rotate3d;
}

/// 开屏配置。
final class SplashConfig {
  /// 创建配置。
  const SplashConfig({
    required this.kind,
    required this.officialStyle,
    required this.productName,
    required this.copyright,
    this.imageUrl,
    this.targetUrl,
    this.title,
    this.durationMs = 3000,
    this.skipAfterMs = 0,
  });

  /// 官方开屏（本地兜底）。
  ///
  /// [productName] / [copyright] 由调用方传入本地化文案，保证离线也有完整品牌展示。
  factory SplashConfig.local({
    required String productName,
    required String copyright,
    SplashOfficialStyle style = SplashOfficialStyle.rotate3d,
  }) => SplashConfig(
    kind: SplashKind.official,
    officialStyle: style,
    productName: productName,
    copyright: copyright,
  );

  /// 开屏类型。
  final SplashKind kind;

  /// 官方开屏形态（仅 [SplashKind.official] 有意义）。
  final SplashOfficialStyle officialStyle;

  /// 底部主标题（产品名称）。
  final String productName;

  /// 底部小灰字（版权等）。
  final String copyright;

  /// 广告图片地址（仅 [SplashKind.ad] 有意义）。
  final Uri? imageUrl;

  /// 广告点击跳转地址。
  final Uri? targetUrl;

  /// 广告文案。
  final String? title;

  /// 开屏总时长（毫秒）。
  final int durationMs;

  /// 允许跳过的延迟（毫秒），仅广告使用。
  final int skipAfterMs;

  /// 是否为广告开屏。
  bool get isAd => kind == SplashKind.ad && imageUrl != null;

  /// 是否需要展示跳过按钮（仅广告）。
  bool get allowsSkip => isAd;

  @override
  String toString() =>
      'SplashConfig(${kind.name}, style: ${officialStyle.name}, '
      'image: $imageUrl)';
}
