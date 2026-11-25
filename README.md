# AMMDS Client

AMMDS 的跨平台内容客户端，让你通过手机、电脑或浏览器访问自己部署的 AMMDS 服务端，集中浏览和使用影视、演员、小说与漫画内容。

> AMMDS Client 不是独立内容服务，也不内置影视、小说或漫画资源。服务端请从 [AMMDS-Docker](https://github.com/MengSenStudio/AMMDS-Docker) 获取，部署与使用说明见 [AMMDS 公开文档](https://github.com/MengSenStudio/AMMDS-DOC)。登录账号由你的 AMMDS 服务端提供。

## 下载安装

前往 [Releases](https://github.com/MengSenStudio/AMMDS-Client/releases) 下载最新版本。

| 平台 | 安装包 | 使用说明 |
| --- | --- | --- |
| Android | `AMMDS-Android-all-<版本>.apk` | 通用包；不确定设备架构时选择此项 |
| Android | `AMMDS-Android-arm64-v8a-<版本>.apk` | 适合多数现代手机，体积较小 |
| Android | `AMMDS-Android-armeabi-v7a-<版本>.apk` | 适合较旧的 32 位 ARM 设备 |
| Android | `AMMDS-Android-x86_64-<版本>.apk` | 适合部分模拟器与 x86_64 设备 |
| Windows | `AMMDS-Windows-all-<版本>.zip` | 解压完整目录后运行主程序；不要只复制其中的 EXE 文件 |

目前发布页提供 Android 与 Windows 安装包。工程同时包含 Web、Linux、macOS 和 iOS 目标，但这些平台暂未提供正式安装包，需自行构建，功能与适配程度可能有所不同。

> **测试版本提示：** 当前 Android release 构建使用调试签名，适合体验与测试，不应视为采用正式生产签名的版本。升级或覆盖安装前，请确认安装包来源一致。

## 快速开始

1. 启动 AMMDS 服务端，并确认客户端设备能够访问该服务端。
2. 打开 AMMDS Client。手机或桌面设备与服务端位于同一局域网时，客户端会尝试自动发现服务端。
3. 选择发现的服务端；如果没有发现结果，可手动输入地址，例如 `http://192.168.1.100:8080`。
4. 使用服务端分配的账号登录，即可浏览内容、阅读小说与漫画或播放影视。

如果自动发现不可用，请检查服务端是否在线、设备是否处于同一网络，以及路由器或系统防火墙是否限制局域网广播。Web 版受浏览器限制，不支持 UDP 自动发现，需要手动填写服务端地址。

## 主要功能

- **影视与演员**：浏览列表和详情，查看封面与相关资料，播放服务端提供的影视资源。
- **小说阅读**：支持翻页与滚动模式，调整字号、版心和配色，使用沉浸式阅读。
- **漫画阅读**：支持翻页、连续滚动和图片缩放，按需加载章节图片。
- **跨设备续读**：阅读进度保存到所连接的 AMMDS 服务端，便于在不同设备间继续阅读；多端同时使用时以后写入的进度为准。
- **局域网发现**：自动发现可用服务端，也可保存多个服务端地址并手动切换。
- **桌面体验**：支持系统托盘、最小化到托盘和开机自启。
- **界面与设备适配**：提供深色模式、中英文界面，并适配手机、平板与桌面窗口尺寸。

## 使用须知

- 客户端仅负责内容预览与使用，不承担服务端内容管理、刮削或系统配置能力。
- 封面与章节图片通常由 AMMDS 服务端代理。旧版服务端可能缺少所需接口，遇到图片无法显示时请先升级服务端。
- 当前尚未提供离线下载和收藏功能。
- 在公共设备上不建议启用“记住密码”。退出登录或不再使用设备时，请清理本机会话。
- 局域网服务端可以使用 HTTP；如果服务端暴露在公网或不可信网络，请务必配置 HTTPS，避免账号、令牌和内容流量被窃听。
- 客户端会获取项目官方通告；该请求使用独立连接，不会把 AMMDS 服务端令牌发送到通告服务器。

## 从源码运行

需要 Flutter stable，Dart 版本满足 `pubspec.yaml` 中的 `^3.13.3` 约束。

```powershell
git clone https://github.com/MengSenStudio/AMMDS-Client.git
cd AMMDS-Client
flutter pub get
flutter devices
flutter run -d <设备ID>
```

Android 与 Windows 的一键打包脚本位于 `scripts/`：

```powershell
pwsh -File scripts\build_installer.ps1
```

服务端部署与使用请参阅 [AMMDS 公开文档](https://github.com/MengSenStudio/AMMDS-DOC)。以下为客户端开发文档：

- [架构说明](docs/architecture/README.md)
- [服务发现与排障](docs/discovery/README.md)
- [接口约定](docs/api/README.md)
- [测试说明](docs/testing/)
- [多语言流程](docs/l10n/README.md)
- [主题说明](docs/theme/README.md)

## 问题反馈

请通过 [GitHub Issues](https://github.com/MengSenStudio/AMMDS-Client/issues) 提交问题。建议附上客户端版本、操作系统、服务端版本、复现步骤和相关截图。

**不要在 Issue 中公开密码、访问令牌、刷新令牌、私人服务端地址或完整凭据文件。** 日志请先脱敏再上传。

## 许可

本项目随 AMMDS 项目公开，保留所有权利。`third_party/` 中的第三方组件遵循其各自许可证，相关说明与许可证文件已随源码保留。
