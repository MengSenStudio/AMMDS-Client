# 服务发现协议（Discovery Protocol）

本文定义 AMMDS Client 与 AMMDS Server 之间的局域网发现协议。
这是客户端**唯一**需要服务端配合实现的协议（文档 #16 / #17 / #109）。

> 状态：已实现并被端到端测试覆盖（真实 UDP socket + 真实服务端测试桩）。

---

## 1. 目标与流程

> 用户无需手动输入 IP 地址，即可快速发现局域网中的 AMMDS 服务端。

```text
Client                                   Server
  │                                        │
  │  UDP Broadcast / Unicast (47823)       │
  │ ─────────────────────────────────────► │
  │                                        │
  │  Discovery Response (JSON)             │
  │ ◄───────────────────────────────────── │
  │                                        │
  校验 → 回退 host → 去重 → 展示列表
```

---

## 2. 承载方式

| 项 | 取值 |
| --- | --- |
| 传输协议 | UDP |
| 服务端探测监听端口 | `47823`（`DiscoveryConstants.port`） |
| 服务端广播目标端口 / 客户端绑定端口 | `47824`（`DiscoveryConstants.announcePort`） |
| 客户端探测目标端口 | `47823` |
| 编码 | UTF-8 JSON |
| 单报文上限 | 4096 字节（超出视为非法） |

> 两个端口**刻意分离**：客户端需要长期绑定一个端口才能被动接收广播，
> 若与探测端口相同，客户端与服务端部署在同一台机器时会抢占同一个 UDP 端口。
> 分开后，客户端绑定 `47824` 同时接收「广播」与「探测应答」，
> 探测仍发往 `47823`。

客户端探测目标（按顺序全部发送）：

1. IPv4 受限广播 `255.255.255.255`
2. 本机回环地址 `127.0.0.1`
3. 各网卡所在 `/24` 子网的定向广播地址（如 `192.168.1.255`）

> 依据文档 #17.1，初始版本优先实现 IPv4 UDP 广播；
> 兼容单播探测是因为部分路由器不转发受限广播，
> 同时保证单机开发 / 测试环境也能走完整链路。
>
> 绑定 `47824` 失败时（端口被占用，例如同机已有另一个客户端实例）会**自动回退**为
> 系统分配的临时端口，此时无法接收广播，但仍可通过「探测—应答」完成发现。

---

## 3. 请求报文

客户端发出的探测请求：

```json
{
  "protocol": "ammds-discovery",
  "version": 1,
  "service": "ammds",
  "type": "discover",
  "client_id": "ammds-client",
  "client_version": "1.0.0"
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `protocol` | string | 是 | 固定 `ammds-discovery` |
| `version` | int | 是 | 协议版本，当前 `1` |
| `service` | string | 是 | 期望的服务类型，固定 `ammds` |
| `type` | string | 是 | 固定 `discover` |
| `client_id` | string | 否 | 客户端标识 |
| `client_version` | string | 否 | 客户端版本 |

服务端只需校验 `protocol` / `service` 并返回响应；`type` 为 `discover` 即视为探测。

---

## 4. 响应报文

服务端响应（建议结构，文档 #17）：

```json
{
  "protocol": "ammds-discovery",
  "version": 1,
  "service": "ammds",
  "server_id": "xxxxxxxx",
  "name": "AMMDS Server",
  "host": "192.168.1.100",
  "port": 8080,
  "api_version": "v1",
  "https": false,
  "version_name": "1.0.0",
  "capabilities": {
    "media": true,
    "people": true,
    "novel": true,
    "comic": true
  }
}
```

| 字段 | 类型 | 必填 | 客户端行为 |
| --- | --- | --- | --- |
| `type` | string | 否 | `discover_response`（应答）或 `announce`（服务端周期广播）；缺失时按应答处理 |
| `protocol` | string | 是 | 不匹配则忽略该响应（`protocol_mismatch`） |
| `version` | int | 是 | 高于客户端支持版本则忽略（`version_incompatible`） |
| `service` | string | 是 | 不匹配则忽略（`service_mismatch`） |
| `server_id` | string | 否 | 缺失时由 `host:port` 派生；用于**去重** |
| `name` | string | 否 | 缺失时使用默认名 `AMMDS Server` |
| `host` | string | 否 | 缺失时回退为**报文来源地址** |
| `port` | int | 是 | 缺失或非法（≤0 / >65535）则忽略（`malformed`） |
| `api_version` | string | 否 | 默认 `v1`；用于能力协商 |
| `https` | bool | 否 | 决定客户端使用 `http` 还是 `https` |
| `version_name` | string | 否 | 服务端版本，用于兼容性提示（文档 #81） |
| `capabilities` | object\<string,bool\> | 否 | 非布尔值会被忽略 |

### 4.1 客户端解析规则

```text
收到报文
  ├── 超过 4096 字节        → 忽略（tooLarge）
  ├── 非 UTF-8 / 非 JSON    → 忽略（malformed）
  ├── JSON 根不是对象        → 忽略（malformed）
  ├── protocol 不匹配        → 忽略（protocolMismatch）
  ├── service 不匹配         → 忽略（serviceMismatch）
  ├── version 高于支持版本   → 忽略（versionIncompatible）
  ├── port 缺失或非法        → 忽略（malformed）
  ├── host 缺失             → 回退为报文来源地址
  └── server_id 缺失         → 由 host:port 派生
        │
        ▼
   按 server_id 去重 → 转换为 ServerProfile → 展示
```

非法响应只计数、不抛异常，**不影响**同一轮中的其他合法服务端。

---

## 5. 两种发现模式（文档 #17.2）

客户端与服务端**同时**支持两种模式，二者共用同一套协议字段与去重键：

```text
                Discovery
                    │
        ┌───────────┴───────────┐
        │                       │
  服务端周期广播            客户端主动探测
  （announce，默认 15s）    （每 5s 一轮，页面存活期间持续）
        │                       │
        └───────────┬───────────┘
                    ▼
              按 server_id 去重
```

| 模式 | 解决的问题 | 客户端实现 |
| --- | --- | --- |
| 探测—应答 | 服务端刚启动，还没到下一次广播时间点 | [DiscoveryWatcher] 周期性发送探测 |
| 服务端广播 | App 打开时服务端已在线 | 绑定 `47824` 被动接收 `announce` 报文 |

登录页与服务端选择页使用 `DiscoveryWatcher`（`ServerManager.startWatching`），
**在页面存活期间持续发现**，而不是「打开页面时扫描一次」：

```text
startWatching(onServerFound)
      ├── 绑定端口（47824，失败回退临时端口）
      ├── 立即探测一次
      ├── 每 5s 主动探测一次
      └── 随时接收服务端 announce
```

因此服务端在任何时刻上线或进入网络，都会在下一个探测周期内出现在列表中。
一次性的 `DiscoveryService.discover()` 仍然保留，供单元测试与一次性场景使用。

### 5.1 探测节奏与超时（一次性模式）

禁止无限等待（文档 #17.2、#57）：

```text
Start Discovery
      ├── 立即发送探测
      ├── 延迟重试（默认 4 轮，间隔 350ms）
      ├── 末轮后再等待一个探测窗口（700ms）收集迟到响应
      └── 结束并展示结果
```

| 参数 | 默认值 | 常量 |
| --- | --- | --- |
| 探测轮次 | 4 | `DiscoveryConstants.probeRounds` |
| 轮次间隔 | 350 ms | `DiscoveryConstants.probeInterval` |
| 末轮等待 | 700 ms | `DiscoveryConstants.probeTimeout` |
| 持续发现的重探间隔 | 5 s | `DiscoveryConstants.watchProbeInterval` |

单次完整发现耗时上限约 `4 × 350ms + 700ms ≈ 2.1s`。

节奏可通过 `DiscoveryTuning` 注入覆盖（测试中使用极短节奏）：
`lib/core/discovery/discovery_service.dart`。

---

## 6. 去重与多服务端

* 去重键为 `server_id`；同一服务端在多网卡场景下可能被多次收到；
* 多个服务端会全部保留并在列表中展示；
* 同一服务端先后收到多次响应时，只保留第一次。

---

## 7. 客户端实现位置

| 文件 | 职责 |
| --- | --- |
| `lib/core/constants/discovery_constants.dart` | 端口、协议标识、超时、错误码 |
| `lib/core/discovery/discovery_models.dart` | 请求 / 响应 / 结果模型 |
| `lib/core/discovery/discovery_codec.dart` | 编解码与校验 |
| `lib/core/discovery/discovery_transport.dart` | `DiscoveryTransport` 抽象、UDP 实现、内存假实现 |
| `lib/core/discovery/discovery_service.dart` | 探测编排、去重、超时、回调上报 |
| `lib/domain/services/server_manager.dart` | 转换为 `ServerProfile` 并持久化 |

`DiscoveryTransport` 抽象的用途：让协议逻辑可以在不依赖真实网络的情况下被完整测试。

---

## 8. 服务端实现（`src/`）

服务发现是**唯一需要服务端配合实现**的能力，已在本仓库后端真实落地。

| 文件 | 职责 |
| --- | --- |
| `src/main/java/top/lifebus/ammds/configuration/DiscoveryProperties.java` | `ammds.discovery.*` 配置绑定 |
| `src/main/java/top/lifebus/ammds/template/discovery/DiscoveryRequest.java` | 探测请求 DTO + 合法性判定 |
| `src/main/java/top/lifebus/ammds/template/discovery/DiscoveryResponse.java` | 响应 DTO（下划线字段名） |
| `src/main/java/top/lifebus/ammds/utils/discovery/DiscoveryProtocol.java` | 纯函数编解码与响应构造（可单测） |
| `src/main/java/top/lifebus/ammds/utils/discovery/DiscoverySnapshot.java` | 运行时快照（端口 / 名称 / 版本 / 能力） |
| `src/main/java/top/lifebus/ammds/service/system/DiscoveryServer.java` | UDP socket 生命周期与收发主循环 |
| `src/main/java/top/lifebus/ammds/service/system/DiscoverySnapshotResolver.java` | 从 Spring 环境解析快照（含真实端口） |
| `src/main/java/top/lifebus/ammds/configuration/DiscoveryConfiguration.java` | Bean 装配与就绪后启动 |

### 8.1 配置

```yaml
ammds:
  discovery:
    enabled: ${AMMDS_DISCOVERY_ENABLED:true}
    port: ${AMMDS_DISCOVERY_PORT:47823}
    protocol: ammds-discovery
    version: 1
    service: ammds
    api-version: v1
    buffer-size: 4096
    use-probe-source-host: true
    # 周期广播（被动发现）
    announce-enabled: ${AMMDS_DISCOVERY_ANNOUNCE_ENABLED:true}
    announce-interval-seconds: ${AMMDS_DISCOVERY_ANNOUNCE_INTERVAL_SECONDS:15}
    announce-targets: ${AMMDS_DISCOVERY_ANNOUNCE_TARGETS:}
    announce-port: ${AMMDS_DISCOVERY_ANNOUNCE_PORT:47824}
```

`use-probe-source-host` 默认开启：响应中的 `host` 回填为探测报文来源地址，
保证客户端能回连；若已配置对外地址（系统配置 `system_global_address` 且非回环），
则优先使用该地址。

`announce-targets` 留空表示自动推导（受限广播 + 回环 + 各网卡广播地址），
也可显式配置为逗号分隔的地址列表（测试与特殊网络环境使用）。

### 8.2 实现要点

* 单条守护线程串行收发，关闭 socket 唤醒阻塞中的 `receive`，`stop()` 可重复调用；
* 周期广播由**独立的单线程调度器**（守护线程 `ammds-discovery-announce`）完成，
  启动即广播一次、之后按 `announce-interval-seconds` 周期广播；
  单个目标发送失败只记 debug 日志，不影响其它目标与接收循环；
* 协议逻辑集中在 `DiscoveryProtocol`，可在不启动 Spring 的情况下单测；
* 端口在 `ApplicationReadyEvent` 阶段通过 `local.server.port` 解析，
  随机端口部署同样正确；
* `server_id` 由「主机名 + 安装目录」派生 UUID，同一次部署重启后保持稳定，
  使客户端去重不受重启影响；
* 非 AMMDS 报文（同网段其它应用广播）解析失败即忽略，不产生响应。

### 8.3 本地验证

```bash
# 1. 编译
mvn -o -B -DskipTests compile

# 2. 运行发现相关测试（协议单测 + 真实 UDP 集成测试）
mvn -o -B test -DskipTests=false -Dtest=DiscoveryProtocolTest,DiscoveryServerTest

# 3. 启动服务端（示例：独立库 + 指定端口）
ADMIN_PASS=ammds-e2e-pass mvn -o -B spring-boot:run \
  "-Dspring-boot.run.arguments=--server.port=18099 \
   --ammds.scheduler.enable=false --ammds.monitor.enable=false \
   --spring.datasource.url=jdbc:h2:file:./db/ammds-client-e2e;DB_CLOSE_DELAY=-1"

# 4. 客户端联调（真实 UDP 发现 + 真实登录）
cd client
flutter test integration_test/live_backend_test.dart
```

联调测试会读取 `AMMDS_E2E_HOST` / `AMMDS_E2E_PORT` / `AMMDS_E2E_USER` /
`AMMDS_E2E_PASS`（默认 `127.0.0.1:18099` 与 `ammds/ammds-e2e-pass`），
服务端不可达时自动跳过。

> 注意：服务端与客户端测试桩同时运行时会同时被客户端发现（多服务端场景），
> 因此联调用例会显式选择目标服务端。

---

## 9. 测试覆盖（文档 #80）

| 场景 | 测试位置 |
| --- | --- |
| 正常响应 | `test/discovery_codec_test.dart`、`test/discovery_service_test.dart` |
| 多个服务端 | `test/discovery_service_test.dart` |
| 无服务端 | `test/discovery_service_test.dart` |
| 超时 | `test/discovery_service_test.dart` |
| 重复响应（去重） | `test/discovery_service_test.dart` |
| 非法响应 | `test/discovery_codec_test.dart`（非 JSON / 非对象 / 端口非法 / 超长） |
| 协议版本不兼容 | `test/discovery_codec_test.dart` |
| 协议 / 服务类型不匹配 | `test/discovery_codec_test.dart` |
| 缺少 host 回退来源地址 | `test/discovery_codec_test.dart` |
| 真实 UDP 收发 | `test/discovery_service_test.dart`（真实 socket + 测试桩） |
| 端到端发现 → 登录 | `integration_test/e2e_test.dart` |
| 服务端协议编解码 | `src/test/java/.../utils/discovery/DiscoveryProtocolTest.java`（9 项） |
| 服务端 UDP 收发链路 | `src/test/java/.../service/system/DiscoveryServerTest.java`（8 项） |
| 真实服务端联调 | `integration_test/live_backend_test.dart` |

---

## 10. 待与服务端确认（文档 #109）

| 项 | 当前取值（客户端与服务端一致） | 需确认 |
| --- | --- | --- |
| UDP 探测端口 | `47823` | 是否沿用 |
| UDP 广播端口 | `47824`（与探测端口分离，详见第 2 节） | 是否沿用 |
| UDP 多播地址 | IPv4 `239.255.42.99`（预留，暂未使用） | 是否需要多播 |
| 请求格式 | 见第 3 节 | 是否完全一致 |
| 响应格式 | 见第 4 节（含 `type`） | 字段名 / 是否新增字段 |
| 协议版本 | `1` | 是否一致 |
| 超时与重试 | 第 5 节 | 是否需要调整 |
| 广播间隔 | `15s` | 是否需要调整 |

> 服务端实现已按本文档落地，两侧字段与取值逐项对齐
> （`DiscoveryServerTest#matchesClientProtocolContract` 会校验客户端必需字段齐全）。
> 若后续调整协议，需同时修改 `discovery_constants.dart`、`discovery_codec.dart`
> 与 `DiscoveryProperties` / `DiscoveryProtocol`。
