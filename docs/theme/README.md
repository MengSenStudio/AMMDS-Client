# Theme 规范

本文说明 AMMDS Client 的主题系统，以及**如何新增主题变量、颜色与组件主题**。
所有规则以文档 [`../../../AMMDS-Client.md`](../../../AMMDS-Client.md) 第 5、6、102 节为依据。

---

## 1. 主题架构

```text
AppTheme                       lib/core/theme/app_theme.dart
├── light / dark / system      主题模式解析入口
├── AppColors                  项目设计变量（ThemeExtension）
├── AppTypography              字体令牌
├── AppSpacing                 间距令牌
├── AppRadius                  圆角令牌
├── AppMotion                  动效令牌
├── AppBreakpoints             响应式断点
└── TDThemeData                TDesign 主题数据适配
```

| 文件 | 职责 |
| --- | --- |
| `app_colors.dart` | 设计变量集合（含浅色 / 深色两套调色板）+ 间距 / 圆角 / 动效 / 断点 |
| `app_typography.dart` | 字体令牌（字号 / 字重 / 行高，不含颜色） |
| `light_theme.dart` | 浅色 `ThemeData` 组装 |
| `dark_theme.dart` | 深色 `ThemeData` 组装 + `buildAppThemeData()` 共用实现 |
| `app_theme.dart` | 对外入口、`ThemeMode` 解析、TDesign 适配、`context.appColors` |

主题模式默认为 **System**（文档 #5.1），由 `themeModeProvider` 持久化到本地配置。

---

## 2. 铁律：禁止在业务代码中硬编码颜色

```dart
// ❌ 禁止
Container(color: Color(0xFF123456))

// ✅ 允许：使用项目设计变量
Container(color: context.appColors.surface)

// ✅ 允许：使用 Flutter 主题
Container(color: Theme.of(context).colorScheme.primary)

// ✅ 允许：TDesign 主题变量
TDTheme.of(context).brandNormalColor
```

`flutter analyze` 不会自动捕获硬编码颜色，**Code Review 必须检查**。

---

## 3. 如何新增颜色

1. 在 `lib/core/theme/app_colors.dart` 的 `AppColors` 中新增字段；
2. 同时补充构造函数参数、`copyWith` 与 `lerp`；
3. 在 `AppColors.light` 与 `AppColors.dark` 中分别给出取值；
4. 若该颜色同时需要映射到 TDesign 主题，在 `dark_theme.dart` 的组件主题中引用。

```dart
class AppColors extends ThemeExtension<AppColors> {
  // 1) 新增字段
  final Color highlight;

  const AppColors({
    // ...
    required this.highlight,
  });

  static const AppColors light = AppColors(
    // ...
    highlight: Color(0xFFFFF7E6),
  );

  static const AppColors dark = AppColors(
    // ...
    highlight: Color(0xFF3B2F1A),
  );

  @override
  AppColors copyWith({Color? highlight /* ... */}) =>
      AppColors(highlight: highlight ?? this.highlight /* ... */);

  @override
  AppColors lerp(covariant ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      highlight: Color.lerp(highlight, other.highlight, t)!,
      // ...
    );
  }
}
```

> 新增颜色时必须**同时**提供浅色与深色取值，否则深色模式下会退化为浅色值。

---

## 4. 如何新增主题变量（间距 / 圆角 / 动效 / 断点）

这些是**与颜色无关**的常量，直接加到对应令牌类：

```dart
abstract final class AppSpacing {
  static const double sectionGap = 20;   // 新增
}

abstract final class AppRadius {
  static const double sheet = 16;        // 新增
}

abstract final class AppMotion {
  static const Duration page = Duration(milliseconds: 280);   // 新增
  static const Curve pageCurve = Curves.easeInOutCubic;       // 新增
}
```

令牌类的字段必须是 `static const`，不允许出现依赖运行时状态的取值。

---

## 5. 如何新增 Light / Dark 主题

现有 `light_theme.dart` / `dark_theme.dart` 已经覆盖全部组件主题。
新增一套主题（例如高对比度主题）建议：

```dart
// light_theme.dart
ThemeData buildLightTheme() => buildAppThemeData(
      brightness: Brightness.light,
      colors: AppColors.light,
    );

// 新增 high_contrast_theme.dart
ThemeData buildHighContrastTheme() => buildAppThemeData(
      brightness: Brightness.light,
      colors: AppColors.highContrast,   // 新增调色板
    );
```

随后在 `app_theme.dart` 的解析逻辑与 `AmmdsClientApp` 的 `MaterialApp.router`
中接入。**不要**复制粘贴整段 `copyWith`——统一走 `buildAppThemeData()`。

---

## 6. 如何新增组件主题

组件主题统一在 `dark_theme.dart` 的 `buildAppThemeData()` 中集中定义：

```dart
ThemeData buildAppThemeData({
  required Brightness brightness,
  required AppColors colors,
}) {
  final isDark = brightness == Brightness.dark;
  final base = isDark ? ThemeData.dark() : ThemeData.light();
  return base.copyWith(
    // ...
    // 新增组件主题：颜色一律来自 colors
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      textStyle: AppTypography.caption.copyWith(color: colors.textPrimary),
    ),
  );
}
```

规则：

1. 组件主题只允许使用 `colors` 与令牌常量，不允许出现字面量颜色；
2. 浅色与深色共用同一段代码，通过 `brightness` 分支处理差异；
3. 业务页面不覆盖组件主题；确有局部差异时，优先扩展 `AppColors`。

---

## 7. 主题兼容性测试

新增或调整主题后，至少完成以下检查：

### 7.1 静态检查

```bash
flutter analyze          # 必须 No issues found
```

### 7.2 自动化测试

`test/app_widget_test.dart` 中的「切换主题为深色后界面仍然可用」用例覆盖了
主题切换路径：

```bash
flutter test test/app_widget_test.dart
```

### 7.3 人工检查清单

| 检查项 | 说明 |
| --- | --- |
| 浅色 / 深色 / 跟随系统 | 三种模式逐一在设置页切换 |
| 文本对比度 | 正文、次要文本、占位符在两种主题下均可读 |
| 分割线与描边 | 深色下不可过亮或不可见 |
| 状态色 | 成功 / 警告 / 错误提示在两种主题下可辨识 |
| 图片占位与骨架屏 | 深色下不刺眼 |
| 系统切换 | 设备切换深色后，跟随系统模式应自动更新 |
| 弹窗 / 提示 / Toast | 背景与文字对比度正确 |
| 响应式 | 手机宽度与桌面宽度下均无溢出 |

---

## 8. 常见问题

**Q：为什么业务代码里取不到 `AppColors`？**

`AppColors` 通过 `ThemeData.extensions` 注入，需在 `MaterialApp` 之下使用。
在页面中使用 `context.appColors`（见 `app_theme.dart` 的扩展），
它会在扩展缺失时按当前亮度回退。

**Q：TDesign 组件的颜色不受控？**

TDesign 组件读取 `TDTheme.of(context)`。根组件通过 `TDTheme` 包装并传入
`AppTheme.tdesignData(...)`，同时用 `TDTheme.needMultiTheme()` 开启多主题，
保证切换主题时 TDesign 组件跟随变化。

**Q：为什么深色模式默认值也要显式写出来？**

`AppColors.dark` 与 `AppColors.light` 都是 `const` 常量，
显式声明可以避免「只改浅色忘了深色」的问题，也让 `lerp` 的插值始终有效。
