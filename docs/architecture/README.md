# 架构说明

本文说明 AMMDS Client 的分层架构、依赖规则与关键运行时流程。
依据文档 [`../../../AMMDS-Client.md`](../../../AMMDS-Client.md) 第 8、10、11、31、91、92、110、111 节。

---

## 1. 分层

```text
┌──────────────────────────────────────────────────────┐
│ Presentation    lib/features/**  lib/shared/**       │
│   页面、组件、UI 状态；只依赖 Domain 接口与 Provider    │
├──────────────────────────────────────────────────────┤
│ Application     lib/features/**/controllers/**       │
│                 lib/domain/services/**               │
│   业务流程编排：SessionManager / ServerManager /       │
│   BootstrapManager / 各页面 Controller                │
├──────────────────────────────────────────────────────┤
│ Domain          lib/domain/entities/**                │
│                 lib/domain/repositories/**            │
│   纯模型 + 仓库接口；不依赖 Flutter、Dio、dart:io       │
├──────────────────────────────────────────────────────┤
│ Data            lib/data/api/**  dto/**  repositories/**│
│   仓库实现、DTO 解析、Client API 拼装                  │
├──────────────────────────────────────────────────────┤
│ Infrastructure  lib/core/**                           │
│   HTTP、UDP 发现、存储、日志、主题、i18n、错误模型       │
└──────────────────────────────────────────────────────┘
```

### 依赖规则

| 规则 | 说明 |
| --- | --- |
| 只能向下依赖 | `Presentation → Application → Domain ← Data → Infrastructure` |
| Domain 无框架依赖 | Domain 层不得 `import 'package:flutter/...'` 或 `dio` |
| UI 不碰网络 | 页面与 Controller 不直接使用 `Dio` / `HttpClient` / `ApiClient` |
| UI 不解析状态码 | 只消费 `AppException`，通过 `localizeError` 展示 |
| 模块间不横向调用 | feature 之间通过 Domain 接口或路由交互，不 import 对方内部实现 |
| 依赖统一入口 | 单例与依赖装配只在 `lib/app/app_container.dart` |

---

## 2. 依赖注入（Riverpod）

`app_container.dart` 是唯一的依赖入口：

```text
preferencesStorageProvider   ─┐
secureStorageProvider        ─┤ 由 main.dart 覆盖为真实实现
httpAdapterProvider          ─┤ 测试覆盖为 MockHttpAdapter
discoveryTransportProvider   ─┘ 测试覆盖为 FakeDiscoveryTransport
                               │
settingsRepositoryProvider ────┤
sessionStoreProvider ──────────┤
authRepositoryProvider ────────┤
sessionManagerProvider ────────┤  ← 延迟解析 authRepository
discoveryServiceProvider ──────┤
serverRepositoryProvider ──────┤
serverManagerProvider ─────────┤
contentRepositoryProvider ─────┤
bootstrapManagerProvider ──────┘
                               │
routerProvider / themeModeProvider / localeProvider / bootstrapStateProvider
```

### 2.1 环形依赖的处理

网络层的鉴权拦截器需要 `SessionManager` 提供令牌与刷新能力，
而 `SessionManager` 需要 `AuthRepository`（进而需要网络层）。
若在构造期相互持有，会形成：

```text
SessionManager → AuthRepository → DioNetworkClient → AuthInterceptor → SessionManager
```

Riverpod 会抛出 `CircularDependencyError`。处理方式：

1. `SessionManager.resolveAuthRepository` 是**函数**而不是字段，
   只在真正调用时解析；
2. `AuthInterceptor` 的 `readAccessToken` / `refreshToken` 回调内部
   才 `ref.read(sessionManagerProvider)`。

这样构造期无环，运行期按需解析。

### 2.2 每服务端一个 API 会话

`clientApiFactory(ref)` 按 `protocol://host:port` 缓存 `ServerApiSession`
（含独立的 `HttpClient` 与拦截器），并在 Provider 释放时关闭底层连接。
切换服务端即切换 API 会话。

---

## 3. 状态管理

| 状态 | 载体 | 位置 |
| --- | --- | --- |
| 认证状态 | `SessionManager`（`Stream<AuthState>`） | `domain/services/session_manager.dart` |
| 服务端与连接状态 | `ServerManager`（`Stream<ServerConnectionState>`） | `domain/services/server_manager.dart` |
| 启动状态 | `BootstrapManager`（`Stream<BootstrapState>`） | `domain/services/bootstrap_manager.dart` |
| 页面状态 | `PageController` + `AsyncState<T>` | `shared/states/async_state.dart` |
| 主题 / 语言 | Riverpod `Notifier` | `app/app_container.dart` |
| 列表分页 | `ContentListController` | `features/media/presentation/pages/content_list_page.dart` |
| 阅读设置 / 阅读进度 | `ReadingRepository`（本地普通配置） | `data/repositories/reading_repository_impl.dart` |

原则（文档 #110 原则五）：认证、服务端连接、应用生命周期、主题、语言等
**全局状态集中管理**，页面不自行维护令牌或服务端信息。

### 3.1 UI 状态模型

```dart
sealed class AsyncState<T> {}
final class Initial<T> extends AsyncState<T> {}
final class Loading<T> extends AsyncState<T> {}
final class Success<T> extends AsyncState<T> { final T data; }
final class Failure<T> extends AsyncState<T> { final Object error; }
```

页面通过 `AppStateView` 统一渲染 `Loading / Error / Empty / Content`。

---

## 4. 启动流程（文档 #13 / #91 / #104）

```text
main()
  ├── WidgetsFlutterBinding.ensureInitialized()
  ├── 安装错误处理（FlutterError / PlatformDispatcher）
  ├── 创建存储实现并注入 ProviderScope
  └── runApp(AmmdsClientApp)

AmmdsClientApp
  ├── 读取本地主题 / 语言偏好
  ├── 注册 AppLifecycle 观察者（回前台检查会话）
  └── MaterialApp.router(TDTheme(...))

Router → /splash → SplashPage
  └── BootstrapManager.start()
        ├── load()                 读取服务器档案与当前服务器
        ├── initializeStorage()
        ├── initializeNetwork()
        ├── restoreSession()       ← 无档案则进入 Login
        ├── connectServer()        ← 连接失败进入 Login
        └── completed(destination)

守卫：completed 前停留在 Splash；完成后按 destination 进入 Login 或 Main；
      未认证访问受保护路由 → 重定向到 Login；已认证访问 Login → 重定向到 Main。
```

`Splash` 只负责动画与过渡；业务判断全部在 `BootstrapManager`。

---

## 5. 请求链路（文档 #31）

```text
Page
 ↓  用户操作
Controller / Service
 ↓  调用仓库接口
Repository（Domain 接口）
 ↓  实现在 Data 层
ClientApi
 ↓  拼装路径与参数
NetworkClient
 ↓  Dio + 拦截器（日志 / 鉴权）
HttpClient
 ↓
AMMDS Server
```

返回链路对称：`Server → HttpClient → NetworkClient → ClientApi → Repository → Domain Model → Controller → UI`。

DTO 不穿透到 UI（文档 #70）：

```text
JSON → DTO（lib/data/dto）→ Domain Entity（lib/domain/entities）→ UI
```

---

## 6. 路由（文档 #12 / #98）

```text
/splash
/login
/device-discovery
/main/media          ← 主界面宿主（MainShellHost）
   └── /detail?id=...
/main/people         └── /detail?id=...
/main/novel          └── /detail?id=...
/main/comic          └── /detail?id=...
/main/management     ← 管理页（由内容页右上角头像 push 进入）
```

* `MainShellHost` 通过 `IndexedStack` 在切换导航时保留各页面状态；
* 移动端使用 `TDBottomTabBar`（影视 / 人物 / 小说 / 漫画）；
* PC 端使用 `NavigationRail`（影视 / 人物 / 小说 / 漫画）；
* 管理模块不在导航项里：移动端由各内容页右上角头像进入，PC 端侧边栏底部同样提供该入口；
* 断点见 `AppBreakpoints`（600 / 1024 / 1440）。

---

## 7. 错误处理（文档 #32 / #58）

```text
Dio / Socket 异常
      ↓  mapDioException()
AppException（NetworkError / TimeoutError / AuthError / ServerError / ParseError）
      ↓  Repository 保持类型
Controller → AsyncState.Failure
      ↓  localizeError() / localizeConnectionFailure()
本地化文案 → AppErrorView / Toast
```

连接失败会区分：服务端不存在 / 网络不可达 / 端口不可用 / 服务端拒绝 /
认证失败 / 版本不兼容（`ConnectionFailureReason`）。

---

## 8. 日志与安全（文档 #48 / #49 / #51）

* 分级：`debug / info / warning / error / fatal`；
* Release 默认最低级别为 `info`，不输出 debug；
* 所有输出经 `AppLogger.sanitize()` 脱敏，
  覆盖 `password` / `token` / `authorization` / `cookie` / `secret` 等字段；
* 网络日志记录 URL / Method / Status / Duration / Request ID，
  敏感 Header 与 Body 脱敏；
* 明文密码不落盘、不写日志；令牌只写入 `SecureStorage`；
* 不提供全局 `badCertificateCallback => true`。

---

## 9. 存储（文档 #24 / #43 / #44）

| 抽象 | 实现 | 用途 |
| --- | --- | --- |
| `PreferencesStorage` | `FilePreferencesStorage` / `InMemoryPreferencesStorage` | 服务器档案、主题、语言 |
| `SecureStorage` | `FileSecureStorage` / `InMemorySecureStorage` | 访问令牌、刷新令牌、当前用户 |

* 桌面数据目录：Windows `%APPDATA%\AMMDS Client`，macOS
  `~/Library/Application Support/AMMDS Client`，Linux `~/.local/share/ammds-client`；
* Android / iOS 通过引擎内置的 `path_provider` 通道获取沙盒目录；
* 所有写入采用「临时文件 + 重命名」，避免进程中断导致配置损坏；
* 读取失败降级为空配置而不是抛异常。

`SecureStorage` 是抽象接口：需要接入 Android Keystore / iOS Keychain 时，
在装配层替换实现即可，业务代码不变。

---

## 10. 响应式与可访问性

* `ResponsiveBuilder` + `AppWindowSize`（compact / medium / expanded）；
* 页面不假设屏幕宽度；列表使用 `SliverGridDelegateWithMaxCrossAxisExtent`；
* 触摸区域不小于 44×44（TDesign 组件默认满足）；
* 文本支持系统字体缩放（未固定 `textScaleFactor`）；
* 语义信息通过标准 Widget（`IconButton` 的 `tooltip`、`Text`）提供。

---

## 11. 测试策略（文档 #79 / #80）

| 层级 | 位置 | 覆盖内容 |
| --- | --- | --- |
| Unit | `test/` | 发现协议编解码与编排、RSA 加解密、DTO 解析与分页、存储、错误映射与重试、SessionManager、ServerManager |
| Widget | `test/app_widget_test.dart` | 开屏、登录、发现列表、手动添加、登录成功 / 失败、主界面导航、主题切换、内容列表 |
| Integration | `integration_test/e2e_test.dart` | 真实 UDP 发现 + 真实 HTTP + 真实存储的完整链路 |

关键测试设施：

* `test_support/mock_ammds_server.dart`：可运行的 AMMDS 服务端测试桩；
* `test_support/mock_http_adapter.dart`：可脚本化的 Dio 适配器；
* `test_support/test_app.dart`：应用装配 + 测试时序工具
  （`pumpUntil` / `waitReal` / `settle` / `drainTimers`）。

> `waitReal` 在虚拟时钟与真实事件循环之间交替推进：
> 启动流程与发现节奏由虚拟时钟驱动，网络与存储 IO 由真实事件循环驱动，
> 单独使用任意一种都会让另一类永久挂起。
