// 只取菜单文案类型：全局 `desktopShell` 由下面的 Web 空实现提供。
import 'package:ammds_client/core/platform/desktop_shell.dart'
    show TrayMenuLabels;
import 'package:ammds_client/core/platform/desktop_shell_web.dart';
import 'package:flutter_test/flutter_test.dart';

/// 桌面外壳的平台约定（文档：托盘 / 关闭即最小化 / 开机自启属于设备专属能力）。
///
/// 这里只验证 Web 空实现的契约——上层（`main.dart` 与设置页）依赖它来判断
/// 「当前平台是否展示开机自启等设置项」；真实桌面实现涉及原生插件，
/// 无法在单元测试中验证，只能通过桌面端手工验证。
void main() {
  group('桌面外壳（Web 空实现）', () {
    test('不支持原生外壳能力', () {
      expect(desktopShell.isSupported, isFalse);
    });

    test('所有能力均为空操作', () async {
      await desktopShell.initialize(
        appName: 'test',
        labels: const TrayMenuLabels(
          showWindow: 'show',
          autoStartEnable: 'enable',
          autoStartDisable: 'disable',
          website: 'website',
          websiteUrl: 'https://example.com/',
          help: 'help',
          helpUrl: 'https://example.com/help',
          version: 'version 1.0.0',
          exit: 'exit',
        ),
      );
      expect(await desktopShell.isAutoStartEnabled(), isFalse);
      // 写入不抛异常，也不反映任何状态（浏览器无法设置登录项）。
      await desktopShell.setAutoStart(true);
      await desktopShell.setAutoStart(false);
      expect(await desktopShell.isAutoStartEnabled(), isFalse);
      await desktopShell.dispose();
    });
  });
}
