# 国际化（l10n）规范

本文说明 AMMDS Client 的多语言方案、key 命名规范与扩展步骤。
依据文档 [`../../../AMMDS-Client.md`](../../../AMMDS-Client.md) 第 7 节。

---

## 1. 方案

采用 Flutter 官方推荐的 **`gen_l10n`** 方案：

```text
lib/core/l10n/
├── arb/
│   ├── app_zh.arb          # 模板语言（中文）
│   └── app_en.arb
├── generated/              # 生成代码（flutter gen-l10n 产出，不手工修改）
│   ├── app_localizations.dart
│   ├── app_localizations_zh.dart
│   └── app_localizations_en.dart
└── l10n.dart               # context.l10n 便捷扩展
```

配置位于项目根目录 `l10n.yaml`：

```yaml
arb-dir: lib/core/l10n/arb
template-arb-file: app_zh.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
output-dir: lib/core/l10n/generated
nullable-getter: false
preferred-supported-locales:
  - zh
  - en
```

重新生成：

```bash
flutter gen-l10n
```

> 生成代码已加入 `analysis_options.yaml` 的 `analyzer.exclude`，不参与静态分析。

---

## 2. 铁律：所有用户可见文本必须国际化

```dart
// ❌ 禁止
Text('登录')
Text('Server not found')

// ✅ 允许
Text(context.l10n.loginButton)
Text(context.l10n.discoveryNotFound)
```

`context.l10n` 定义于 `lib/core/l10n/l10n.dart`：

```dart
extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
```

需要国际化的内容包括（文档 #7.3）：

* 页面标题、Button、输入框提示
* 错误信息、网络错误、登录错误
* 服务发现提示、空状态、加载状态
* 设置选项、系统提示、Dialog、Toast

**不**需要国际化的内容：日志、接口字段名、协议字段、内部异常 `message`
（这些是开发者可见信息，由 UI 层通过 `localizeError` 映射为本地化文案）。

---

## 3. 如何添加翻译

1. 在 **模板文件** `app_zh.arb` 中新增 key 与中文文案；
2. 在 `app_en.arb` 中补齐对应英文文案；
3. 在需要的地方使用 `context.l10n.<key>`；
4. 运行 `flutter gen-l10n`；
5. 运行 `flutter analyze` 与 `flutter test`。

```jsonc
// app_zh.arb
{
  "settingsTitle": "设置",
  "discoveryFoundCount": "发现 {count} 个服务端",
  "@discoveryFoundCount": {
    "placeholders": { "count": { "type": "int" } }
  }
}
```

```jsonc
// app_en.arb
{
  "settingsTitle": "Settings",
  "discoveryFoundCount": "{count, plural, =1{1 server found} other{{count} servers found}}",
  "@discoveryFoundCount": {
    "placeholders": { "count": { "type": "int" } }
  }
}
```

> 复数 / 性别等语言差异写在**目标语言**的 ARB 中，
> 模板语言（中文）保持简单直白的写法。

---

## 4. key 命名规范

采用 `小驼峰`，按「域 + 语义」组织，避免出现页码或控件类型：

| 前缀 | 用途 | 示例 |
| --- | --- | --- |
| `app*` | 应用级 | `appTitle`、`appName`、`slogan` |
| `bootstrap*` | 启动流程 | `bootstrapLoadingConfig` |
| `login*` / `auth*` | 登录认证 | `loginButton`、`authErrorInvalidCredentials` |
| `discovery*` | 服务发现 | `discoveryNotFound`、`discoveryFoundCount` |
| `server*` / `connection*` | 服务器与连接 | `serverAddress`、`connectionFailedServerRefused` |
| `nav*` | 导航项 | `navMedia`、`navSettings` |
| `settings*` | 设置项 | `settingsAppearance` |
| `theme*` / `language*` | 外观与语言 | `themeDark`、`languageEnglish` |
| `empty*` / `loading*` / `error*` | 状态 | `emptyContent`、`loadingMore` |

命名要求：

* 表达**语义**而不是位置：用 `loginButton`，不要用 `loginPageBottomButton`；
* 同类文案保持前缀一致，便于检索；
* 不使用缩写（`btn`、`msg`、`txt`）；
* key 一旦发布不重命名，避免翻译平台失效。

---

## 5. 参数化文本写法

```dart
// ARB
"chapterCount": "共 {count} 章",
"@chapterCount": {
  "placeholders": { "count": { "type": "int" } }
}

// 使用
Text(context.l10n.chapterCount(chapters.length))
```

规则：

1. 占位符必须声明 `type`（`int` / `double` / `String` / `DateTime`）；
2. 需要格式化时补充 `format`（如 `"format": "compact"`）；
3. 不要在 Dart 侧拼接句子片段——语序在不同语言中不同；
4. 不要在 ARB 中嵌入 HTML 或富文本标记，需要富文本时拆成多段分别国际化。

---

## 6. 如何新增语言

以新增日文（`ja`）为例：

1. 新建 `lib/core/l10n/arb/app_ja.arb`，以 `app_zh.arb` 为模板翻译全部 key；
2. 确认 `@@locale` 为 `"ja"`；
3. 在 `l10n.yaml` 的 `preferred-supported-locales` 中加入 `ja`；
4. 运行 `flutter gen-l10n`；
5. 在设置页的语言列表中新增选项（`settingsPage` 内的语言 `TDCellGroup`）；
6. 在 `LocaleNotifier.parse()` 中加入语言代码映射；
7. 运行 `flutter analyze` 与 `flutter test`，并人工核对长文本换行。

---

## 7. 翻译完成后的缺失校验

`gen_l10n` 在生成阶段就会对**缺失 key** 与**占位符不一致**报错，
因此校验流程为：

```bash
flutter gen-l10n    # 缺失 key / 占位符不一致会直接失败
flutter analyze     # 使用到不存在的 key 会编译失败
flutter test        # Widget 测试会读取文案，间接覆盖主要 key
```

补充检查：

* 用编辑器 / 脚本对比 `app_zh.arb` 与其它 ARB 的 key 集合是否一致；
* 确认不存在仅在某一种语言中出现的 key；
* 确认所有带占位符的 key 在每种语言中的占位符名称一致。

---

## 8. 语言切换

* 语言模式：`跟随系统` / `中文` / `English`；
* 状态由 `localeProvider` 持有，并持久化到 `PreferencesStorage`（key: `appearance.locale`）；
* `null` 表示跟随系统；
* 切换入口：设置页 → 语言（PC 端左侧导航进入设置；移动端可后续纳入个人中心）。

---

## 9. 与错误模型的关系

统一错误模型（`lib/core/errors/app_exception.dart`）中的 `message` 是
**开发者可见**的英文描述，不直接展示给用户。

展示链路：

```text
AppException
   ↓  localizeError(context, error)     // lib/shared/states/async_state.dart
本地化文案（按错误类型分支）
```

连接失败原因同理，通过 `localizeConnectionFailure(context, reason)` 映射，
确保不同失败原因展示不同提示（文档 #58），而不是统一「连接失败」。
