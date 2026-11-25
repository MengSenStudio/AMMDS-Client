import 'dart:ui' as ui;

import 'package:ammds_client/core/l10n/l10n.dart';
import 'package:ammds_client/core/theme/app_theme.dart';
import 'package:ammds_client/domain/entities/promote.dart';
import 'package:ammds_client/shared/widgets/promote_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

/// 官方推送弹窗配图的渲染测试。
///
/// 守住「配图被压成正方形 / 变形」这一反馈。弹窗里的配图是任意比例的图
/// （官方活动图是 876×876 的二维码，也有电影海报等横图），因此判定标准是
/// **实际绘制出来的像素区域必须保持原图宽高比**，而不是看起来占满整行。
///
/// 做法：喂入一张纯色图，渲染后扫描画面上该颜色的像素范围，得到真实绘制矩形。
/// 这样「改回 `height: 固定值 + BoxFit.cover`」会让测试立刻失败：
/// 那种写法会把任意比例的图裁成同一条横带（正方形图会变成 460×180 的横条）。
void main() {
  /// 正方形（例如 876×876 的二维码）。
  const squareUrl = 'https://example.test/square.jpg';

  /// 横图 3:1。
  const wideUrl = 'https://example.test/wide.jpg';

  /// 竖图 1:2.5。
  const tallUrl = 'https://example.test/tall.jpg';

  /// 用来标记配图的颜色；选用主题里不会出现的洋红，避免误判到按钮等元素。
  const marker = Color(0xFFFF00FF);

  final boundaryKey = GlobalKey();

  /// 生成一张纯色图。
  Future<ui.Image> makeImage(WidgetTester tester, int width, int height) async {
    final image = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint()..color = marker,
      );
      return recorder.endRecording().toImage(width, height);
    });
    return image!;
  }

  /// 预置图片缓存：让 `Image.network(url)` 命中指定尺寸的图，不走网络。
  void prime(String url, ui.Image image) {
    PaintingBinding.instance.imageCache.putIfAbsent(
      NetworkImage(url),
      () => OneFrameImageStreamCompleter(
        Future<ImageInfo>.value(ImageInfo(image: image)),
      ),
    );
  }

  Future<void> pumpDialog(WidgetTester tester, String url) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1400);
    addTearDown(tester.view.reset);
    TDTheme.needMultiTheme();

    final promote = AppPromote.fromJson(<String, Object?>{
      'id': 'banner',
      'title': '中秋预热',
      'description': '正文',
      'banner': url,
      'website': 'https://example.test/go',
      'endTime': '2099-01-01 00:00:00',
    })!;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: TDTheme(
          data: TDTheme.defaultData(),
          systemData: AppTheme.light(),
          child: RepaintBoundary(
            key: boundaryKey,
            child: PromoteDialog(promote: promote),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// 扫描当前画面，返回标记色的像素包围盒（未命中时返回 null）。
  Future<Rect?> paintedBannerRect(WidgetTester tester) async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final capture = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      return (data: data, size: size);
    });
    final pixels = capture?.data;
    if (pixels == null) {
      return null;
    }
    final bytes = pixels.buffer.asUint8List();
    final width = capture!.size.width.round();
    final height = capture.size.height.round();
    var left = width;
    var top = height;
    var right = -1;
    var bottom = -1;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final offset = (y * width + x) * 4;
        final isMarker =
            bytes[offset] > 200 && bytes[offset + 1] < 80 && bytes[offset + 2] > 200;
        if (!isMarker) {
          continue;
        }
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    if (right < 0) {
      return null;
    }
    return Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      (right + 1).toDouble(),
      (bottom + 1).toDouble(),
    );
  }

  /// 断言配图绘制区保持 `ratio` 的宽高比，且高度不超过 260。
  Future<void> expectBannerRatio(
    WidgetTester tester,
    double ratio,
  ) async {
    final rect = await paintedBannerRect(tester);
    expect(rect, isNotNull, reason: '配图没有绘制出来');
    expect(rect!.width / rect.height, closeTo(ratio, 0.02));
    expect(rect.height, lessThanOrEqualTo(260));
  }

  testWidgets('正方形配图（二维码）按原始比例绘制，不被裁成横条', (WidgetTester tester) async {
    prime(squareUrl, await makeImage(tester, 876, 876));
    await pumpDialog(tester, squareUrl);

    await expectBannerRatio(tester, 1);
  });

  testWidgets('横图保持 3:1', (WidgetTester tester) async {
    prime(wideUrl, await makeImage(tester, 1200, 400));
    await pumpDialog(tester, wideUrl);

    await expectBannerRatio(tester, 3);
  });

  testWidgets('竖图保持 1:2.5，并按最大高度收口', (WidgetTester tester) async {
    prime(tallUrl, await makeImage(tester, 400, 1000));
    await pumpDialog(tester, tallUrl);

    await expectBannerRatio(tester, 0.4);
  });
}
