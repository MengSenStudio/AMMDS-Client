# third_party

本目录存放**第三方依赖的兼容补丁副本**，通过 `pubspec.yaml` 的
`dependency_overrides` 指向它们。仅在无法等待上游修复时使用。

---

## tdesign_flutter

| 项 | 内容 |
| --- | --- |
| 上游版本 | `tdesign_flutter 0.2.8-fix.1`（pub.dev 最新稳定版） |
| 上游仓库 | https://github.com/Tencent/tdesign-flutter |
| 许可 | MIT（见 `tdesign_flutter/LICENSE`） |
| 补丁范围 | 仅 `lib/src/components/icon/td_icons.dart` 一个文件 |

### 为什么需要补丁

上游 0.2.x 通过继承 `IconData` 来实现图标常量：

```dart
// 上游原始实现
@immutable
class _TDIconsData extends IconData {
  const _TDIconsData(int codePoint, this.name)
      : super(codePoint, fontFamily: 'TDIcons', fontPackage: 'tdesign_flutter');
  final String name;
}
```

Flutter 3.35 / Dart 3.13 起 `IconData` 成为 `final class`，禁止包外继承，
编译时报错：

```text
Error: The class 'IconData' can't be extended outside of its library
because it's a final class.
```

这会导致依赖该库的项目**完全无法编译**（`flutter test` / `flutter run` 均失败）。

### 补丁内容

把 `_TDIconsData(codePoint, 'name')` 替换为直接使用 `IconData` 的命名参数构造：

```dart
// 补丁后
static const accessibility_filled = IconData(
  0xE001,
  fontFamily: 'TDIcons',
  fontPackage: 'tdesign_flutter',
);
```

* `IconData` 已有 `const` 命名参数构造，因此 `static const` 常量语义不变；
* 字体族（`TDIcons`）与资源包（`tdesign_flutter`）保持一致，
  图标字形与上游完全相同；
* 未被任何代码使用的 `name` 字段被移除（它只是上游生成器的产物）；
* 其余 4000+ 个图标常量与全库其它文件**未做任何改动**。

### 如何重新生成补丁副本

若需要升级上游版本：

```powershell
# 1. 从 pub 缓存复制新版本
robocopy "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.flutter-io.cn\tdesign_flutter-<版本>" `
         "client\third_party\tdesign_flutter" /E /XD example test .git .idea

# 2. 重新应用图标补丁（把 _TDIconsData(...) 改为 IconData(...)）
#    参考下方正则：
#    _TDIconsData\((0x[0-9A-Fa-f]+),\s*'[^']*'\)
#      →  IconData($1, fontFamily: 'TDIcons', fontPackage: 'tdesign_flutter')
#    并把 Map 的泛型 _TDIconsData 改为 IconData

# 3. 删除 helper 类定义，保留文件头部说明注释
```

### 何时可以移除本目录

当上游发布支持 Dart 3.13+ 的版本（不再继承 `IconData`）后：

1. 删除 `pubspec.yaml` 中的 `dependency_overrides` 段；
2. 把 `tdesign_flutter` 的版本约束提升到该版本；
3. 删除本目录；
4. 重新运行 `flutter analyze`、`flutter test` 与
   `flutter test integration_test -d windows` 确认无回归。

> 上游 `1.0.0-alpha.1` 已改为使用独立的 `tdesign_flutter_icons` 包，
> 但属于预发布的大版本升级（主题与组件 API 有变更），
> 因此当前选择补丁方案，待其稳定后再迁移。
