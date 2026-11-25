# Client API 约定

本文说明客户端与 AMMDS 服务端之间的接口约定，依据文档
[`../../../AMMDS-Client.md`](../../../AMMDS-Client.md) 第 19 ~ 33、81、82 节。

> 客户端只依赖 **Client API**，与管理端 API 逻辑隔离（文档 #21）。

---

## 0. 两套接口方言

AMMDS 生态中存在两套可用的服务端接口，客户端通过 `ServerApi` 抽象同时支持：

| 方言 | 前缀 | 说明 |
| --- | --- | --- |
| `clientV1` | `/api/client/v1/**` | 本文档约定的客户端专用接口 |
| `ammdsPublic` | `/api/oauth/**`、`/api/pub/**`、`/api/admin/user/info` | 服务端**当前已实现**的公开接口 |

**方言在连接测试阶段自动探测一次**，结果写入 `ServerProfile.dialect` 并持久化，
后续请求全部走同一路径：

```text
probe()
  ├── GET /api/client/v1/health      成功 → clientV1
  └── GET /api/oauth/secret          成功 → ammdsPublic
```

选择逻辑：优先使用档案中已记录的方言，失败时再尝试另一种方言并把结果写回档案。

两套方言的关键差异：

| 项 | `clientV1` | `ammdsPublic` |
| --- | --- | --- |
| 登录路径 | `POST /api/client/v1/auth/login` | `POST /api/oauth/login` |
| 公钥接口 | `GET /api/oauth/secret` → `publicKey` | `GET /api/oauth/secret` → `secret`（裸 Base64 DER） |
| 密码约定 | `RSA(明文)` | `RSA(MD5^5(明文))` |
| 用户信息 | `GET /api/client/v1/user/profile` | `GET /api/admin/user/info` |
| 鉴权失败 | HTTP 401 | **HTTP 200 + 业务码 401** |
| 令牌刷新 | `POST /api/client/v1/auth/refresh` | 不支持（过期后重新登录） |
| 内容列表 | `GET /api/client/v1/{media,people,novels,comics}` | `POST /api/pub/media/search`、`POST /api/pub/actor/search`、`GET /api/pub/novel/search`、`GET /api/pub/comic/search` |
| 内容详情 | `GET .../{id}` | `GET /api/pub/{media,actor,novel,comic}/details/{id}` |
| 分页字段 | `items` + `has_more` + `next_cursor` | `data` + `current`（当前页）+ `page`（总页数）+ `total` |

> `ammdsPublic` 的密码约定与既有服务端 `UserEntity` 一致：
> `setPassword()` 先做一轮 MD5 写入 `password` 列，
> `getLoginPassword()` 再以该摘要为输入连续做 4 轮 MD5，共 5 轮，
> 服务端把请求密文 RSA 解密后与该值比对。
> 客户端实现见 `lib/core/utils/password_digest.dart`。

### 0.1 相关实现

| 文件 | 职责 |
| --- | --- |
| `lib/data/api/server_api.dart` | 方言无关的接口抽象 |
| `lib/data/api/client_api.dart` | `clientV1` 实现 |
| `lib/data/api/ammds_public_api.dart` | `ammdsPublic` 实现 |
| `lib/data/api/server_dialect.dart` | 方言枚举与档案字段解析 |
| `lib/core/utils/password_digest.dart` | 五轮 MD5 摘要 |
| `lib/app/app_container.dart` | `serverApiFactory`（按服务端 + 方言缓存会话） |

> **服务端已实现本方言**（`src/main/java/top/lifebus/ammds/controller/client/**`）：
> 登录接口提交 {@code RSA(明文)}，由服务端解密后自行完成 5 轮 MD5 比对
> （`UserServiceImpl#loginWithPlainPassword`），客户端无需了解服务端摘要算法。
> 因此新部署的服务端会被客户端探测为 `clientV1`，`ammdsPublic` 仅用于兼容旧部署。

---

## 1. 前缀与版本

```text
/api/client/v1/...
```

* 统一前缀：`/api/client/v1`（`ClientApiPaths.prefix`）
* 版本化：不兼容变更时新增 `/api/client/v2/`，而不是修改 v1
* 客户端声明的 API 版本：`v1`（`AppConstants.supportedApiVersion`）

### 1.1 前缀常量

```dart
abstract final class ClientApiPaths {
  static const String prefix = '/api/client/v1';
  static const String serverInfo = '$prefix/server/info';
  static const String health = '$prefix/health';
  static const String login = '$prefix/auth/login';
  static const String refresh = '$prefix/auth/refresh';
  static const String logout = '$prefix/auth/logout';
  static const String session = '$prefix/auth/session';
  static const String profile = '$prefix/user/profile';
  static const String media = '$prefix/media';
  static const String people = '$prefix/people';
  static const String novels = '$prefix/novels';
  static const String comics = '$prefix/comics';
  // 阅读器
  static String novelChapterContent(String bookId, String chapterId) =>
      '$novels/$bookId/chapters/$chapterId';
  static String comicChapterPages(String albumId, String chapterId) =>
      '$comics/$albumId/chapters/$chapterId';
}
```

---

## 2. 通用响应体

客户端兼容 AMMDS 统一响应体：

```json
{ "code": 0, "message": "ok", "data": { } }
```

解包规则（`DioNetworkClient._unwrapEnvelope`）：

| 情况 | 行为 |
| --- | --- |
| 含 `code` 或 `data` | 按统一响应体解包，成功时返回 `data` |
| `code == 0 / 200 / "0" / "200" / "success"` | 视为成功 |
| 其它 `code` | 抛出 `ServerError`，携带 `code` 与 `message` |
| 不含 `code`/`data` | 直接返回原始响应体 |
| HTTP ≥ 400 | 抛出 `ServerError`，携带 HTTP 状态码 |

`message` / `msg` / `error` / `detail` 都会作为错误描述被识别。

---

## 3. 接口清单

### 3.1 服务端信息

```http
GET /api/client/v1/server/info
```

无需鉴权。用于连接测试、版本与能力协商（文档 #81 / #82）。

```json
{
  "code": 0,
  "data": {
    "server_id": "test-server-0001",
    "name": "AMMDS Server",
    "server_version": "1.0.0",
    "api_version": "v1",
    "https": false,
    "capabilities": { "media": true, "people": true, "novel": true, "comic": true }
  }
}
```

客户端在 `api_version` 不属于 `v1 / 1 / 1.0 / 1.0.0` 时抛出
`ServerError(code: 'incompatible_version')`，UI 展示「服务端版本不兼容」提示。

### 3.2 连通性探测

```http
GET /api/client/v1/health
```

无需鉴权。`ServerManager.testConnection()` 会先调用该接口判断服务端是否可达。

### 3.3 登录

```http
POST /api/client/v1/auth/login
```

请求体：

```json
{
  "username": "admin",
  "password": "<RSA 加密后的 Base64 或明文>",
  "client": "ammds-client",
  "client_version": "1.0.0"
}
```

> 若服务端提供 `GET /api/oauth/secret` 返回 `{ "publicKey": "<PEM>" }`，
> 客户端会使用 **RSA PKCS#1 v1.5** 加密密码后再填入 `password`；
> 否则退回明文（兼容尚未启用加密的服务端）。
> 该约定与服务端既有管理端登录实现保持一致。

响应：

```json
{
  "code": 0,
  "data": {
    "access_token": "...",
    "refresh_token": "...",
    "expires_in": 3600,
    "user": { "id": "u1", "username": "admin", "nickname": "管理员", "permissions": ["media:read"] }
  }
}
```

兼容形态：

* `{ "token": { "access_token": ... } }` 嵌套结构
* 扁平结构 `{ "access_token": ... }`
* 绝对过期时间 `expires_at`（ISO8601）

`user` 缺失时，客户端会额外调用一次 `GET /api/client/v1/user/profile`。

### 3.4 刷新令牌

```http
POST /api/client/v1/auth/refresh
```

```json
{ "refresh_token": "..." }
```

响应同登录的令牌部分。客户端保证**同一时间只有一个刷新请求**。

### 3.5 登出

```http
POST /api/client/v1/auth/logout
Authorization: Bearer <access_token>
```

### 3.6 校验会话

```http
GET /api/client/v1/auth/session
Authorization: Bearer <access_token>
```

用于启动时的会话有效性校验（文档 #54：不能仅凭本地 Token 判定有效）。
返回 401 / 403 时客户端判定会话失效；网络异常时保留本地会话。

### 3.7 用户信息

```http
GET /api/client/v1/user/profile
Authorization: Bearer <access_token>
```

```json
{
  "code": 0,
  "data": { "id": "u1", "username": "admin", "nickname": "管理员", "avatar": "/a.jpg", "permissions": ["media:read"] }
}
```

### 3.8 内容列表 / 搜索

```http
GET /api/client/v1/media?cursor=1&page_size=20&keyword=xxx&category=xxx
GET /api/client/v1/people?...
GET /api/client/v1/novels?...
GET /api/client/v1/comics?...
```

响应兼容三种形态：

```jsonc
// 1) 统一分页
{ "code": 0, "data": { "items": [...], "has_more": true, "next_cursor": "2" } }

// 2) 页码分页（由 page / page_size / total 推导 has_more）
{ "code": 0, "data": { "list": [...], "page": 1, "page_size": 20, "total": 45 } }

// 3) 裸数组
{ "code": 0, "data": [ ... ] }
```

条目字段兼容多种命名：

| 领域字段 | 接受的字段名 |
| --- | --- |
| `id` | `id` / `uuid` / `key` |
| `title` | `title` / `name` / `original_title` / `nickname` |
| `subtitle` | `subtitle` / `author` / `original_name` / `region` / `status` |
| `coverUri` | `cover` / `poster` / `avatar` / `image`（相对路径会按服务端地址解析为绝对地址） |
| `year` | `year` / `release_year` |
| `rating` | `rating` / `score` |
| `categories` | `categories` / `genres` / `types` / `tags` |

### 3.9 内容详情

```http
GET /api/client/v1/media/{id}
GET /api/client/v1/people/{id}
GET /api/client/v1/novels/{id}
GET /api/client/v1/comics/{id}
```

```json
{
  "code": 0,
  "data": {
    "id": "novels-1",
    "title": "小说",
    "overview": "简介",
    "episode_count": 3,
    "author": "作者",
    "chapters": [ { "id": "c1", "title": "第一章", "index": 1 } ],
    "attributes": { "status": "连载中", "publisher": "出版社甲" },
    "gallery": [ "/api/pub/resource/image?path=data%2Fimages%2F1.jpg" ],
    "related": [ { "id": "media-1", "title": "参演影片", "cover": "..." } ]
  }
}
```

也支持 `{ "data": { "detail": { ... } } }` 嵌套；既有公开接口的小说详情为
`{ "book": { ... }, "chapters": [ ... ] }`，客户端同样兼容（书籍字段从 `book` 中读取）。

| 字段 | 说明 |
| --- | --- |
| `attributes` | 四类内容各自的扩展元信息（人物身高 / 血型、影视语言 / 分辨率、小说出版社、漫画卷号等）。键为服务端约定的英文键名，客户端按已知键渲染本地化标签，未知键原样展示，因此服务端新增字段无需客户端发版 |
| `gallery` | 图集（海报 / 剧照 / 写真），元素为可直接访问的图片地址 |
| `related` | 关联内容；人物详情返回该人物参演的影视作品（最多 12 条），点击进入影视详情 |

扩展属性键与客户端标签的映射见 `lib/shared/widgets/content_attributes.dart`。

### 3.10 章节列表

```http
GET /api/client/v1/novels/{id}/chapters
GET /api/client/v1/comics/{id}/chapters
```

响应为数组，或 `{ "items": [ ... ] }`。详情未内联 `chapters` 时客户端会额外请求该接口。

### 3.11 小说章节正文（小说阅读器）

```http
GET /api/client/v1/novels/{bookId}/chapters/{chapterId}
Authorization: Bearer <access_token>
```

```json
{
  "code": 0,
  "data": {
    "id": "c2",
    "book_id": "n1",
    "title": "第二章",
    "index": 2,
    "content": "<p>正文</p>",
    "text": "正文",
    "word_count": 2,
    "has_content": true,
    "from_source": false,
    "prev_id": "c1",
    "next_id": "c3"
  }
}
```

| 字段 | 说明 |
| --- | --- |
| `content` | 原始正文（可能包含 HTML，供后续富文本渲染使用） |
| `text` | 已剥离 HTML 的纯文本（段落以换行分隔），阅读器直接渲染 |
| `has_content` | 是否存在可阅读正文；`false` 时客户端展示「本章暂无正文」 |
| `prev_id` / `next_id` | 服务端按书籍目录顺序计算，客户端无需自行维护章节顺序 |

章节不属于该书籍时返回业务失败（`code != 200`），客户端映射为统一错误提示。
既有公开接口的等价路径为 `GET /api/pub/novel/chapter/{chapterId}`（正文为 HTML，
客户端会用 `NovelTextParser` 在本地转换）。

### 3.12 漫画章节图片（漫画阅读器）

```http
GET /api/client/v1/comics/{albumId}/chapters/{chapterId}
Authorization: Bearer <access_token>
```

```json
{
  "code": 0,
  "data": {
    "chapter_id": "cc1",
    "chapter_title": "第一话",
    "album_id": "a1",
    "index": 1,
    "page_count": 2,
    "pages": [
      { "sequence": 1, "image": "/api/pub/resource/image?path=data%2Fimages%2F1.jpg" },
      { "sequence": 2, "image": "https://cdn.example.com/2.jpg" }
    ],
    "prev_id": null,
    "next_id": "cc2"
  }
}
```

`image` 已由服务端归一化为可直接访问的地址；既有公开接口的等价路径为
`GET /api/pub/comic/chapter/pages?chapterId=`（返回 `imagePath` 原始值，
客户端用 `ResourceUri` 在本地归一化）。

### 3.13 图片资源地址规则

服务端数据库中的封面 / 海报 / 章节图片可能是三类值，客户端必须统一归一化后再交给
图片组件加载（`lib/core/utils/resource_uri.dart`）：

| 原始值 | 客户端处理 | 结果 |
| --- | --- | --- |
| `https://host/a.jpg` | 改写为服务端图片代理（外链防盗链 / 被墙） | `http://host/api/pub/resource/proxyImage?url=https%3A%2F%2Fhost%2Fa.jpg` |
| `/static/a.jpg` | 按服务端地址补全 | `http://host/static/a.jpg` |
| `data\images\a.jpg` | 改写为公开图片接口 | `http://host/api/pub/resource/image?path=data%2Fimages%2Fa.jpg` |

> **外链为什么必须代理**：外链海报（真实数据中存在 `http://pics.dmm.co.jp/...`）普遍有防盗链，
> 浏览器带 `Referer` 与浏览器 UA 能取到，客户端（`dart:io`）两者都没有会被源站拒绝，
> 且这类图床在国内常属「被墙」地址。Web 端同样把外链交给
> `/api/pub/resource/proxyImage` 转发（见 `app/src/views/.../MovieCardComponent.vue`
> 的 `getImg`），客户端保持同一规则，避免「同一份数据 Web 端能看、客户端只显示占位图」。
> 服务端自身的地址（含已归一化的公开图片接口）不再重复代理。

`Client API`（`clientV1` 方言）已在服务端完成归一化，直接返回上表中的可用地址；
`ammdsPublic` 方言返回原始值，由客户端归一化。上述接口均免鉴权，
因此 `Image.network` 无需额外请求头。

### 3.14 开屏配置

```http
GET /api/client/v1/splash
```

无需鉴权。用于向客户端下发开屏形态（文档 #14 / #65）：

```json
{
  "code": 200,
  "data": {
    "enabled": true,
    "type": "ad",
    "official_style": "3d",
    "image_url": "http://host/promote/a.jpg",
    "target_url": "http://host/act",
    "title": "新版本活动",
    "duration_ms": 3000,
    "skip_after_ms": 1000,
    "product_name": "AMMDS",
    "copyright": "© 版权方"
  }
}
```

| 字段 | 说明 |
| --- | --- |
| `type` | `official`（AMMDS 官方开屏，**不展示跳过按钮**）或 `ad`（广告，展示跳过按钮） |
| `official_style` | 官方开屏形态：`3d`（3D 动画）或 `static`（静态页） |
| `enabled` | 是否下发了非默认内容；false 表示客户端应使用本地品牌资源 |
| `skip_after_ms` | 允许跳过的延迟；0 表示立即可跳过（仅广告有意义） |
| `product_name` / `copyright` | 开屏底部主标题与版权小灰字 |

服务端规则：

* 系统配置 `system_global_ad` 关闭时**强制**回到官方开屏；
* 只有「`client_splash_type=ad` 且配置了 `client_splash_image`」才下发广告，
  避免客户端拿到无法渲染的广告位；
* 其余 `client_splash_*` 配置项均为可选，未配置时回落默认值。

客户端规则：

* 接口不可达 / 404 / 超时（1.5s 上限）时使用**本地官方开屏**，开屏永远可展示；
* 只有 `type=ad` 才渲染跳过按钮；官方开屏不支持跳过；
* 广告图加载失败时自动回落为官方开屏。

---

## 4. 超时策略（文档 #59）

不同用途使用不同超时（`AppTimeouts`）：

| 用途 | 连接 | 发送 | 接收 |
| --- | --- | --- | --- |
| 普通请求 | 10s | 15s | 20s |
| 搜索请求 | 10s | 15s | 30s |
| 图片请求 | 10s | 15s | 30s |
| 文件下载 | 10s | 15s | 10min |

---

## 5. 重试策略（文档 #60）

| 错误 | 是否重试 |
| --- | --- |
| 网络不可达 / 连接失败 | ✅ |
| 超时 | ✅ |
| 5xx | ✅ |
| 400 / 401 / 403 / 404 | ❌ |
| 业务校验失败 | ❌ |

默认最大重试 2 次（`NetworkOptions.maxRetries`），仅对显式开启重试的请求生效
（当前为内容列表 / 搜索请求）。

---

## 6. 错误模型（文档 #32）

UI 层**禁止**解析 HTTP 状态码，所有错误在数据层归一化为 `AppException`：

```text
NetworkError      网络不可达 / 连接失败 / DNS 失败
AuthError         认证失败
ServerError       5xx、业务失败响应（携带 statusCode / code）
ValidationError   输入校验失败
TimeoutError      请求超时
ParseError        响应解析失败
UnknownError      未归类错误
```

UI 通过 `localizeError(context, error)` 映射为本地化文案。

---

## 7. 鉴权

```http
Authorization: Bearer <access_token>
```

由 `AuthInterceptor` 统一注入，业务代码不接触令牌：

1. 读取当前访问令牌（`SessionManager.currentAccessToken()`）；
2. 令牌进入刷新窗口（默认剩余 60s）时**主动刷新**；
3. 收到 401 时刷新令牌并**重放一次**请求；
4. 刷新失败 → 清理认证信息 → 状态置为 `expired` → 回到登录页。

---

## 8. 待与服务端确认（文档 #109）

| 项 | 客户端当前假设 | 服务端状态 |
| --- | --- | --- |
| Client API 前缀 | `/api/client/v1` | ✅ 已实现 |
| API 版本 | `v1` | ✅ `ammds.discovery.api-version` |
| 登录接口 | `POST /api/client/v1/auth/login` | ✅ 已实现（`RSA(明文)`） |
| 刷新接口 | `POST /api/client/v1/auth/refresh` | ✅ 已实现（无状态重签） |
| 登出接口 | `POST /api/client/v1/auth/logout` | ✅ 已实现（无黑名单） |
| 会话校验 | `GET /api/client/v1/auth/session` | ✅ 已实现 |
| 用户信息 | `GET /api/client/v1/user/profile` | ✅ 已实现 |
| 开屏配置 | `GET /api/client/v1/splash` | ✅ 已实现 |
| 服务端能力 | `GET /api/client/v1/server/info` 的 `capabilities` | ✅ 已实现 |
| Access Token 生命周期 | 由 `expires_in` 决定 | ✅ 返回 7200（与 JWT 的 120 分钟一致） |
| Refresh Token 生命周期 | 由 `refresh_expires_in` 决定（可选） | ⚠️ 无独立刷新令牌，`refresh_token == access_token` |
| 内容列表分页方式 | 同时兼容 cursor 与 page 两种 | ✅ 返回 `items/has_more/next_cursor` |
| 内容详情扩展字段 | `attributes` / `gallery` / `related` | ✅ Client API 已实现（`ClientContentDetailResp`） |
| 小说章节正文 | `GET /api/client/v1/novels/{id}/chapters/{chapterId}` | ✅ 已实现（同时下发原始与纯文本正文） |
| 漫画章节图片 | `GET /api/client/v1/comics/{id}/chapters/{chapterId}` | ✅ 已实现（图片地址已归一化） |
| 图片资源地址 | 相对路径统一走 `/api/pub/resource/image?path=` | ✅ 服务端归一化 + 客户端兜底 |
| 阅读进度同步 | 本地保存（离线可用） | ⚠️ Client API 暂无阅读进度读写接口 |
| HTTPS | 由服务端信息中的 `https` 与发现响应中的 `https` 决定 | ⚠️ 由 `server.ssl.enabled` 决定 |

> 所有路径集中在 `ClientApiPaths`，响应解析集中在 `lib/data/dto/api_dto.dart`。
> 服务端最终字段与上述不一致时，只需调整这两处，UI 与领域模型不受影响。
