// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'AMMDS';

  @override
  String get appName => 'AMMDS 客户端';

  @override
  String get slogan => '连接你的 AMMDS 媒体库';

  @override
  String get bootstrapInitializing => '正在初始化…';

  @override
  String get bootstrapLoadingConfig => '正在加载本地配置…';

  @override
  String get bootstrapInitializingStorage => '正在初始化存储…';

  @override
  String get bootstrapInitializingNetwork => '正在初始化网络…';

  @override
  String get bootstrapRestoringSession => '正在恢复登录状态…';

  @override
  String get bootstrapConnectingServer => '正在连接服务端…';

  @override
  String get loginTitle => '登录';

  @override
  String get loginSubtitle => '登录 AMMDS 服务端以开始浏览内容';

  @override
  String get usernameLabel => '用户名';

  @override
  String get usernameHint => '请输入用户名';

  @override
  String get passwordLabel => '密码';

  @override
  String get passwordHint => '请输入密码';

  @override
  String get loginButton => '登录';

  @override
  String get loggingIn => '正在登录…';

  @override
  String get logout => '退出登录';

  @override
  String get logoutConfirmTitle => '退出登录';

  @override
  String get logoutConfirmMessage => '确认退出当前账号吗？';

  @override
  String get confirm => '确定';

  @override
  String get cancel => '取消';

  @override
  String get close => '关闭';

  @override
  String get retry => '重试';

  @override
  String get refresh => '刷新';

  @override
  String get back => '返回';

  @override
  String get save => '保存';

  @override
  String get edit => '编辑';

  @override
  String get delete => '删除';

  @override
  String get search => '搜索';

  @override
  String get searchHint => '搜索关键词';

  @override
  String get clear => '清空';

  @override
  String get all => '全部';

  @override
  String get unknown => '未知';

  @override
  String get optional => '可选';

  @override
  String get loading => '加载中…';

  @override
  String get loadingMore => '正在加载更多…';

  @override
  String get noMore => '没有更多了';

  @override
  String get pullToRefresh => '下拉刷新';

  @override
  String get releaseToRefresh => '松开刷新';

  @override
  String get yes => '是';

  @override
  String get no => '否';

  @override
  String get serverSectionTitle => '服务器';

  @override
  String get discoverServers => '发现服务器';

  @override
  String get discovering => '正在搜索附近的 AMMDS 服务…';

  @override
  String discoveryFoundCount(int count) {
    return '发现 $count 个服务端';
  }

  @override
  String get discoveryNotFound =>
      '没有发现服务端。请确认手机与服务端在同一网段、服务端已放通 UDP 47823，或直接手动填写地址';

  @override
  String get discoveryFailed => '服务发现失败，请检查网络或手动添加服务器';

  @override
  String get discoveryUnsupported => '当前平台不支持内网自动发现';

  @override
  String get discoveryUnsupportedHint => '浏览器沙箱无法收发 UDP，请手动填写服务端地址后登录';

  @override
  String get rescan => '重新搜索';

  @override
  String get discoveryResultsTitle => '搜索结果';

  @override
  String get discoveryHistoryTitle => '历史服务端';

  @override
  String get discoveryHistoryEmpty => '连接过的服务端会显示在这里';

  @override
  String get discoverySkippedHint => '已跳过路由器 / 热点网关等非服务端地址';

  @override
  String get serverList => '服务端列表';

  @override
  String get selectServer => '选择服务端';

  @override
  String get currentServer => '当前服务器';

  @override
  String get switchServer => '切换服务器';

  @override
  String get manualServer => '手动添加';

  @override
  String get manualServerTitle => '手动配置服务器';

  @override
  String get serverAddress => '服务器地址';

  @override
  String get serverAddressHint => 'http://192.168.1.100:8080';

  @override
  String get serverName => '服务器名称';

  @override
  String get serverPort => '端口';

  @override
  String get serverProtocol => '协议';

  @override
  String get testConnection => '测试连接';

  @override
  String get testing => '正在测试…';

  @override
  String get connectSuccess => '连接成功';

  @override
  String get missingServerAddress => '请先选择或输入服务器地址';

  @override
  String get serverDuplicate => '该服务器已在列表中';

  @override
  String get removeServer => '移除服务器';

  @override
  String get noServerConfigured => '尚未配置服务器';

  @override
  String get discoveryCapabilities => '能力';

  @override
  String get connectionFailed => '连接失败';

  @override
  String get connectionFailedServerNotFound => '服务端不存在，请确认地址是否正确';

  @override
  String get connectionFailedNetworkUnreachable => '网络不可达，请检查网络连接';

  @override
  String get connectionFailedPortUnavailable => '端口不可用，服务端可能未启动';

  @override
  String get connectionFailedServerRefused => '服务端拒绝连接';

  @override
  String get connectionFailedUnauthorized => '认证失败，请重新登录';

  @override
  String get incompatibleServerVersion => '当前服务端版本不支持此客户端，请升级服务端。';

  @override
  String get authErrorInvalidCredentials => '用户名或密码错误';

  @override
  String get authErrorUsernameRequired => '请输入用户名';

  @override
  String get authErrorPasswordRequired => '请输入密码';

  @override
  String get authErrorSessionExpired => '登录状态已过期，请重新登录';

  @override
  String get authErrorServerMismatch => '登录信息与服务端不匹配';

  @override
  String get networkError => '网络异常，请稍后重试';

  @override
  String get networkTimeout => '请求超时，请稍后重试';

  @override
  String get parseError => '数据解析失败';

  @override
  String get serverError => '服务端异常';

  @override
  String get validationError => '输入内容不合法';

  @override
  String get unknownError => '发生未知错误';

  @override
  String get navMedia => '影视';

  @override
  String get navPeople => '人物';

  @override
  String get navNovel => '小说';

  @override
  String get navComic => '漫画';

  @override
  String get navSettings => '设置';

  @override
  String get navMain => '首页';

  @override
  String get mediaTitle => '影视';

  @override
  String get mediaDetailTitle => '影视详情';

  @override
  String get peopleTitle => '人物';

  @override
  String get mediaSearchHint => '搜索影视';

  @override
  String get peopleSearchHint => '搜索人物';

  @override
  String get novelSearchHint => '搜索小说';

  @override
  String get comicSearchHint => '搜索漫画';

  @override
  String get peopleDetailTitle => '人物详情';

  @override
  String get novelTitle => '小说';

  @override
  String get novelDetailTitle => '小说详情';

  @override
  String get comicTitle => '漫画';

  @override
  String get comicDetailTitle => '漫画详情';

  @override
  String get chapterList => '章节列表';

  @override
  String chapterCount(int count) {
    return '共 $count 章';
  }

  @override
  String get loadMoreChapters => '加载更多章节';

  @override
  String get startReading => '开始阅读';

  @override
  String get emptyContent => '暂无内容';

  @override
  String get emptySearchResult => '没有找到相关内容';

  @override
  String get emptyServerList => '还没有可用的服务器';

  @override
  String get errorRetryHint => '加载失败，请重试';

  @override
  String get peopleRelatedContent => '关联内容';

  @override
  String get comicDetailPending => '漫画阅读器将在后续版本提供';

  @override
  String get novelReaderPending => '小说阅读器将在后续版本提供';

  @override
  String get mediaPlayerPending => '播放功能将在后续版本提供';

  @override
  String get releaseYear => '年份';

  @override
  String get rating => '评分';

  @override
  String get overview => '简介';

  @override
  String get noOverview => '暂无简介';

  @override
  String get categories => '分类';

  @override
  String get genres => '类型';

  @override
  String get episodeCount => '集数';

  @override
  String get readCount => '阅读';

  @override
  String get author => '作者';

  @override
  String get status => '状态';

  @override
  String get popularity => '热度';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsServer => '服务器';

  @override
  String get settingsAccount => '账户';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsAbout => '关于';

  @override
  String get settingsUserInfo => '用户信息';

  @override
  String get settingsLoginState => '登录状态';

  @override
  String get settingsSignedIn => '已登录';

  @override
  String get settingsSignedOut => '未登录';

  @override
  String get settingsChangeServer => '切换服务器';

  @override
  String get themeFollowSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get languageChinese => '中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get aboutVersion => '版本';

  @override
  String get aboutLicense => '开源协议';

  @override
  String get aboutProject => '项目信息';

  @override
  String get aboutLicenseValue => 'MIT License';

  @override
  String get aboutProjectValue => 'AMMDS Client · Flutter 跨平台客户端';

  @override
  String get logLevel => '日志级别';

  @override
  String get saved => '已保存';

  @override
  String get apiVersion => 'API 版本';

  @override
  String get serverVersion => '服务端版本';

  @override
  String get httpsEnabled => 'HTTPS';

  @override
  String get capabilityMedia => '影视';

  @override
  String get capabilityPeople => '人物';

  @override
  String get capabilityNovel => '小说';

  @override
  String get capabilityComic => '漫画';

  @override
  String get networkOnline => '在线';

  @override
  String get networkOffline => '离线';

  @override
  String get networkConnecting => '正在连接';

  @override
  String get networkReconnecting => '正在重连';

  @override
  String get serverConnectionDisconnected => '未连接';

  @override
  String get serverConnectionConnected => '已连接';

  @override
  String get serverConnectionUnavailable => '服务端不可用';

  @override
  String get serverConnectionUnauthorized => '未授权';

  @override
  String get authStateUnknown => '未知';

  @override
  String get authStateChecking => '校验中';

  @override
  String get authStateAuthenticated => '已认证';

  @override
  String get authStateExpired => '已过期';

  @override
  String get authStateUnauthenticated => '未认证';

  @override
  String welcomeBack(String name) {
    return '欢迎回来，$name';
  }

  @override
  String mainShellPlaceholder(String feature) {
    return '$feature功能正在建设中';
  }

  @override
  String get managementTitle => '管理';

  @override
  String get managementProfile => '个人信息';

  @override
  String get managementProfileDesc => '账号资料与登录状态';

  @override
  String get managementServer => '服务器';

  @override
  String get managementServerDesc => '当前服务端、切换与连接测试';

  @override
  String get managementApp => '应用配置';

  @override
  String get managementAppDesc => '主题、语言与日志';

  @override
  String get managementAbout => '关于';

  @override
  String get profileUsername => '用户名';

  @override
  String get profileNickname => '昵称';

  @override
  String get profileRole => '角色';

  @override
  String get profileEmail => '邮箱';

  @override
  String get profilePhone => '手机号';

  @override
  String get profileRegisteredAt => '注册时间';

  @override
  String get profileLastLoginAt => '最近登录';

  @override
  String get profileNotAvailable => '未填写';

  @override
  String get profileRefresh => '刷新资料';

  @override
  String get profileRefreshSuccess => '资料已更新';

  @override
  String get profileGuest => '未登录用户';

  @override
  String get roleAdmin => '管理员';

  @override
  String get roleUser => '普通用户';

  @override
  String get accountEnabled => '账号状态';

  @override
  String get accountEnabledYes => '正常';

  @override
  String get accountEnabledNo => '已禁用';

  @override
  String get serverConnectionTest => '测试连接';

  @override
  String get serverConnectionTesting => '正在测试…';

  @override
  String get serverConnectionSuccess => '连接正常';

  @override
  String get serverDialect => '接口方言';

  @override
  String get serverDialectClientV1 => 'Client API';

  @override
  String get serverDialectPublic => '公开接口';

  @override
  String get serverDiscoverNow => '重新发现服务器';

  @override
  String get serverSwitchNow => '切换服务器';

  @override
  String get appTheme => '主题';

  @override
  String get appLanguage => '语言';

  @override
  String get appLogLevel => '日志级别';

  @override
  String get logLevelDebug => '调试';

  @override
  String get logLevelInfo => '信息';

  @override
  String get logLevelWarning => '警告';

  @override
  String get logLevelError => '错误';

  @override
  String get autoStart => '开机自启';

  @override
  String get autoStartEnabled => '已开启开机自启';

  @override
  String get autoStartDisabled => '已关闭开机自启';

  @override
  String get autoStartFailed => '开机自启设置失败，请重试或检查系统权限';

  @override
  String get trayShowWindow => '显示主窗口';

  @override
  String get trayAutoStartEnable => '启用开机自启';

  @override
  String get trayAutoStartDisable => '禁用开机自启';

  @override
  String get trayWebsite => '官网';

  @override
  String get trayHelp => '帮助';

  @override
  String trayVersion(String version) {
    return '版本：$version';
  }

  @override
  String get trayExit => '退出应用';

  @override
  String get aboutClientVersion => '客户端版本';

  @override
  String get aboutClientId => '客户端标识';

  @override
  String get aboutProtocol => '发现协议';

  @override
  String get aboutProtocolValue => 'ammds-discovery v1';

  @override
  String get logoutSuccess => '已退出登录';

  @override
  String get appCopyright => '© 新疆萌森软件开发工作室';

  @override
  String get splashSkip => '跳过';

  @override
  String splashSkipCountdown(int seconds) {
    return '跳过 ${seconds}s';
  }

  @override
  String get loginSettingsTitle => '设置';

  @override
  String get settingsGroupApp => '外观与应用';

  @override
  String get settingsGroupData => '数据与隐私';

  @override
  String get clearCache => '清除缓存';

  @override
  String get clearCacheConfirmTitle => '清除缓存';

  @override
  String get clearCacheConfirmMessage => '将清理本地图片与界面缓存。不会影响登录状态与服务器配置。';

  @override
  String get clearCacheSuccess => '缓存已清除';

  @override
  String get copyrightPrivacy => '版权与隐私';

  @override
  String get copyrightPrivacyTitle => '版权与隐私';

  @override
  String get copyrightPrivacyMessage =>
      'AMMDS Client 是 AMMDS 服务的终端客户端，用于连接并浏览你自有的 AMMDS 服务端。\n\n客户端不采集、不上传任何个人数据；登录凭据仅保存在本机安全存储（Keystore / Keychain）中。';

  @override
  String get rememberPassword => '记住密码';

  @override
  String get forgotPassword => '忘记密码？';

  @override
  String get forgotPasswordTitle => '找回密码';

  @override
  String get forgotPasswordMessage =>
      '客户端无法重置服务端账号密码。\n\n请前往 AMMDS 服务端，使用「恢复密钥」自助重置，或联系管理员重置后再登录。';

  @override
  String get discoverLanServers => '发现内网服务器';

  @override
  String get detailSectionInfo => '详细信息';

  @override
  String get detailSectionGallery => '图集';

  @override
  String get continueReading => '继续阅读';

  @override
  String get detailNoChapters => '暂无章节';

  @override
  String detailLastRead(String chapter) {
    return '上次读到：$chapter';
  }

  @override
  String get promoteDialogTitle => '官方推送';

  @override
  String get promoteRead => '已读';

  @override
  String get promoteGo => '前往';

  @override
  String get promoteBannerFailed => '配图无法加载';

  @override
  String get mediaFilesTitle => '播放资源';

  @override
  String get mediaFilePlay => '播放';

  @override
  String get mediaFileUnavailable => '不可用';

  @override
  String get mediaPlayback => '播放';

  @override
  String get playerPreparing => '正在准备播放…';

  @override
  String get playerUnavailable => '无法播放';

  @override
  String get playerSwitchSource => '切换播放源';

  @override
  String get playerNoSource => '暂无可播放资源';

  @override
  String get playerPlay => '播放';

  @override
  String get playerPause => '暂停';

  @override
  String get playerBackward => '后退 10 秒';

  @override
  String get playerForward => '前进 10 秒';

  @override
  String get playerVolume => '音量';

  @override
  String get playerMute => '静音';

  @override
  String get playerUnmute => '取消静音';

  @override
  String get playerSpeed => '播放速度';

  @override
  String get playerSourceCurrent => '正在播放';

  @override
  String get playerBrightness => '亮度';

  @override
  String get playerGestureHint => '播放画面：单击播放或暂停，双击两侧快进快退，左右滑动调整进度，上下滑动调整音量与亮度';

  @override
  String get readerChapterList => '目录';

  @override
  String get readerSettings => '阅读设置';

  @override
  String get readerMode => '阅读模式';

  @override
  String get readerModePaged => '翻页';

  @override
  String get readerModeScroll => '滚动';

  @override
  String get readerFontSize => '字号';

  @override
  String get readerLineHeight => '行距';

  @override
  String get readerContentWidth => '版心';

  @override
  String get readerPadding => '页边距';

  @override
  String get readerIndent => '首行缩进';

  @override
  String get readerPageAnimation => '翻页动画';

  @override
  String get readerAutoNextChapter => '章末自动下一章';

  @override
  String get readerOptionNarrow => '窄';

  @override
  String get readerOptionMedium => '适中';

  @override
  String get readerOptionWide => '宽';

  @override
  String readerNovelPageProgress(int page, int total) {
    return '第 $page / $total 页';
  }

  @override
  String get readerBackground => '背景';

  @override
  String get readerBackgroundLight => '浅色';

  @override
  String get readerBackgroundSepia => '米黄';

  @override
  String get readerBackgroundGreen => '护眼绿';

  @override
  String get readerBackgroundDark => '夜间';

  @override
  String get readerPrevChapter => '上一章';

  @override
  String get readerNextChapter => '下一章';

  @override
  String get readerChapterEmpty => '暂无章节';

  @override
  String get readerNoContent => '本章暂无正文';

  @override
  String readerChapterProgress(int current, int total) {
    return '第 $current / $total 章';
  }

  @override
  String get readerSourceChapter => '书源章节';

  @override
  String get comicReadMode => '阅读模式';

  @override
  String get comicReadModePaged => '翻页';

  @override
  String get comicReadModeContinuous => '连续';

  @override
  String get comicReaderEmpty => '本章暂无图片';

  @override
  String comicPageProgress(int current, int total) {
    return '$current / $total 页';
  }

  @override
  String comicPageCount(int count) {
    return '共 $count 页';
  }

  @override
  String get attrOriginalTitle => '原名';

  @override
  String get attrTagline => '标语';

  @override
  String get attrRuntime => '时长(分钟)';

  @override
  String get attrPremiered => '首播日期';

  @override
  String get attrCountry => '国家/地区';

  @override
  String get attrLanguage => '语言';

  @override
  String get attrMpaa => '分级';

  @override
  String get attrStudio => '出品';

  @override
  String get attrResolution => '分辨率';

  @override
  String get attrVideoCodec => '视频编码';

  @override
  String get attrAudioCodec => '音频编码';

  @override
  String get attrFileSize => '文件大小';

  @override
  String get attrCast => '演员';

  @override
  String get attrGender => '性别';

  @override
  String get attrBirthDate => '出生日期';

  @override
  String get attrAge => '年龄';

  @override
  String get attrHeight => '身高(cm)';

  @override
  String get attrWeight => '体重(kg)';

  @override
  String get attrNationality => '国籍';

  @override
  String get attrBloodType => '血型';

  @override
  String get attrCupSize => '罩杯';

  @override
  String get attrDebutDate => '出道日期';

  @override
  String get attrRetired => '退役';

  @override
  String get attrDeceased => '已故';

  @override
  String get attrAliases => '别名';

  @override
  String get attrStyle => '风格';

  @override
  String get attrSpecialFeatures => '特征';

  @override
  String get attrStatus => '状态';

  @override
  String get attrGenre => '类型';

  @override
  String get attrPublisher => '出版社';

  @override
  String get attrPublishYear => '出版年份';

  @override
  String get attrPageCount => '页数';

  @override
  String get attrChapterCount => '章节数';

  @override
  String get attrIsbn => 'ISBN';

  @override
  String get attrSeries => '系列';

  @override
  String get attrSource => '来源';

  @override
  String get attrType => '类型';

  @override
  String get attrSeason => '季';

  @override
  String get attrPhotoCount => '图片数';

  @override
  String get attrPublishDate => '出版日期';

  @override
  String get attrFormat => '格式';

  @override
  String get attrAgeRating => '年龄分级';

  @override
  String get attrCommunityRating => '社区评分';

  @override
  String get attrManga => '阅读方向';

  @override
  String get attrFullChapter => '全集';

  @override
  String get attrBlackWhite => '黑白';

  @override
  String get attrWriter => '编剧';

  @override
  String get attrPenciller => '线稿';

  @override
  String get attrInker => '勾线';

  @override
  String get attrColorist => '上色';

  @override
  String get attrLetterer => '字体排版';

  @override
  String get attrCoverArtist => '封面绘制';

  @override
  String get attrEditor => '编辑';

  @override
  String get attrTranslator => '翻译';

  @override
  String get attrCharacters => '角色';

  @override
  String get attrTeams => '团队';

  @override
  String get attrLocations => '地点';
}
