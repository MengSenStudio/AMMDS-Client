import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'AMMDS'**
  String get appTitle;

  /// No description provided for @appName.
  ///
  /// In zh, this message translates to:
  /// **'AMMDS 客户端'**
  String get appName;

  /// No description provided for @slogan.
  ///
  /// In zh, this message translates to:
  /// **'连接你的 AMMDS 媒体库'**
  String get slogan;

  /// No description provided for @bootstrapInitializing.
  ///
  /// In zh, this message translates to:
  /// **'正在初始化…'**
  String get bootstrapInitializing;

  /// No description provided for @bootstrapLoadingConfig.
  ///
  /// In zh, this message translates to:
  /// **'正在加载本地配置…'**
  String get bootstrapLoadingConfig;

  /// No description provided for @bootstrapInitializingStorage.
  ///
  /// In zh, this message translates to:
  /// **'正在初始化存储…'**
  String get bootstrapInitializingStorage;

  /// No description provided for @bootstrapInitializingNetwork.
  ///
  /// In zh, this message translates to:
  /// **'正在初始化网络…'**
  String get bootstrapInitializingNetwork;

  /// No description provided for @bootstrapRestoringSession.
  ///
  /// In zh, this message translates to:
  /// **'正在恢复登录状态…'**
  String get bootstrapRestoringSession;

  /// No description provided for @bootstrapConnectingServer.
  ///
  /// In zh, this message translates to:
  /// **'正在连接服务端…'**
  String get bootstrapConnectingServer;

  /// No description provided for @loginTitle.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'登录 AMMDS 服务端以开始浏览内容'**
  String get loginSubtitle;

  /// No description provided for @usernameLabel.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get usernameLabel;

  /// No description provided for @usernameHint.
  ///
  /// In zh, this message translates to:
  /// **'请输入用户名'**
  String get usernameHint;

  /// No description provided for @passwordLabel.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get passwordLabel;

  /// No description provided for @passwordHint.
  ///
  /// In zh, this message translates to:
  /// **'请输入密码'**
  String get passwordHint;

  /// No description provided for @loginButton.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get loginButton;

  /// No description provided for @loggingIn.
  ///
  /// In zh, this message translates to:
  /// **'正在登录…'**
  String get loggingIn;

  /// No description provided for @logout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get logout;

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmMessage.
  ///
  /// In zh, this message translates to:
  /// **'确认退出当前账号吗？'**
  String get logoutConfirmMessage;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get confirm;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @refresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get refresh;

  /// No description provided for @back.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get back;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @search.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get search;

  /// No description provided for @searchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索关键词'**
  String get searchHint;

  /// No description provided for @clear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get clear;

  /// No description provided for @all.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get all;

  /// No description provided for @unknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get unknown;

  /// No description provided for @optional.
  ///
  /// In zh, this message translates to:
  /// **'可选'**
  String get optional;

  /// No description provided for @loading.
  ///
  /// In zh, this message translates to:
  /// **'加载中…'**
  String get loading;

  /// No description provided for @loadingMore.
  ///
  /// In zh, this message translates to:
  /// **'正在加载更多…'**
  String get loadingMore;

  /// No description provided for @noMore.
  ///
  /// In zh, this message translates to:
  /// **'没有更多了'**
  String get noMore;

  /// No description provided for @pullToRefresh.
  ///
  /// In zh, this message translates to:
  /// **'下拉刷新'**
  String get pullToRefresh;

  /// No description provided for @releaseToRefresh.
  ///
  /// In zh, this message translates to:
  /// **'松开刷新'**
  String get releaseToRefresh;

  /// No description provided for @yes.
  ///
  /// In zh, this message translates to:
  /// **'是'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In zh, this message translates to:
  /// **'否'**
  String get no;

  /// No description provided for @serverSectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'服务器'**
  String get serverSectionTitle;

  /// No description provided for @discoverServers.
  ///
  /// In zh, this message translates to:
  /// **'发现服务器'**
  String get discoverServers;

  /// No description provided for @discovering.
  ///
  /// In zh, this message translates to:
  /// **'正在搜索附近的 AMMDS 服务…'**
  String get discovering;

  /// No description provided for @discoveryFoundCount.
  ///
  /// In zh, this message translates to:
  /// **'发现 {count} 个服务端'**
  String discoveryFoundCount(int count);

  /// No description provided for @discoveryNotFound.
  ///
  /// In zh, this message translates to:
  /// **'没有发现服务端。请确认手机与服务端在同一网段、服务端已放通 UDP 47823，或直接手动填写地址'**
  String get discoveryNotFound;

  /// No description provided for @discoveryFailed.
  ///
  /// In zh, this message translates to:
  /// **'服务发现失败，请检查网络或手动添加服务器'**
  String get discoveryFailed;

  /// No description provided for @discoveryUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前平台不支持内网自动发现'**
  String get discoveryUnsupported;

  /// No description provided for @discoveryUnsupportedHint.
  ///
  /// In zh, this message translates to:
  /// **'浏览器沙箱无法收发 UDP，请手动填写服务端地址后登录'**
  String get discoveryUnsupportedHint;

  /// No description provided for @rescan.
  ///
  /// In zh, this message translates to:
  /// **'重新搜索'**
  String get rescan;

  /// No description provided for @discoveryResultsTitle.
  ///
  /// In zh, this message translates to:
  /// **'搜索结果'**
  String get discoveryResultsTitle;

  /// No description provided for @discoveryHistoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'历史服务端'**
  String get discoveryHistoryTitle;

  /// No description provided for @discoveryHistoryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'连接过的服务端会显示在这里'**
  String get discoveryHistoryEmpty;

  /// No description provided for @discoverySkippedHint.
  ///
  /// In zh, this message translates to:
  /// **'已跳过路由器 / 热点网关等非服务端地址'**
  String get discoverySkippedHint;

  /// No description provided for @serverList.
  ///
  /// In zh, this message translates to:
  /// **'服务端列表'**
  String get serverList;

  /// No description provided for @selectServer.
  ///
  /// In zh, this message translates to:
  /// **'选择服务端'**
  String get selectServer;

  /// No description provided for @currentServer.
  ///
  /// In zh, this message translates to:
  /// **'当前服务器'**
  String get currentServer;

  /// No description provided for @switchServer.
  ///
  /// In zh, this message translates to:
  /// **'切换服务器'**
  String get switchServer;

  /// No description provided for @manualServer.
  ///
  /// In zh, this message translates to:
  /// **'手动添加'**
  String get manualServer;

  /// No description provided for @manualServerTitle.
  ///
  /// In zh, this message translates to:
  /// **'手动配置服务器'**
  String get manualServerTitle;

  /// No description provided for @serverAddress.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址'**
  String get serverAddress;

  /// No description provided for @serverAddressHint.
  ///
  /// In zh, this message translates to:
  /// **'http://192.168.1.100:8080'**
  String get serverAddressHint;

  /// No description provided for @serverName.
  ///
  /// In zh, this message translates to:
  /// **'服务器名称'**
  String get serverName;

  /// No description provided for @serverPort.
  ///
  /// In zh, this message translates to:
  /// **'端口'**
  String get serverPort;

  /// No description provided for @serverProtocol.
  ///
  /// In zh, this message translates to:
  /// **'协议'**
  String get serverProtocol;

  /// No description provided for @testConnection.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get testConnection;

  /// No description provided for @testing.
  ///
  /// In zh, this message translates to:
  /// **'正在测试…'**
  String get testing;

  /// No description provided for @connectSuccess.
  ///
  /// In zh, this message translates to:
  /// **'连接成功'**
  String get connectSuccess;

  /// No description provided for @missingServerAddress.
  ///
  /// In zh, this message translates to:
  /// **'请先选择或输入服务器地址'**
  String get missingServerAddress;

  /// No description provided for @serverDuplicate.
  ///
  /// In zh, this message translates to:
  /// **'该服务器已在列表中'**
  String get serverDuplicate;

  /// No description provided for @removeServer.
  ///
  /// In zh, this message translates to:
  /// **'移除服务器'**
  String get removeServer;

  /// No description provided for @noServerConfigured.
  ///
  /// In zh, this message translates to:
  /// **'尚未配置服务器'**
  String get noServerConfigured;

  /// No description provided for @discoveryCapabilities.
  ///
  /// In zh, this message translates to:
  /// **'能力'**
  String get discoveryCapabilities;

  /// No description provided for @connectionFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败'**
  String get connectionFailed;

  /// No description provided for @connectionFailedServerNotFound.
  ///
  /// In zh, this message translates to:
  /// **'服务端不存在，请确认地址是否正确'**
  String get connectionFailedServerNotFound;

  /// No description provided for @connectionFailedNetworkUnreachable.
  ///
  /// In zh, this message translates to:
  /// **'网络不可达，请检查网络连接'**
  String get connectionFailedNetworkUnreachable;

  /// No description provided for @connectionFailedPortUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'端口不可用，服务端可能未启动'**
  String get connectionFailedPortUnavailable;

  /// No description provided for @connectionFailedServerRefused.
  ///
  /// In zh, this message translates to:
  /// **'服务端拒绝连接'**
  String get connectionFailedServerRefused;

  /// No description provided for @connectionFailedUnauthorized.
  ///
  /// In zh, this message translates to:
  /// **'认证失败，请重新登录'**
  String get connectionFailedUnauthorized;

  /// No description provided for @incompatibleServerVersion.
  ///
  /// In zh, this message translates to:
  /// **'当前服务端版本不支持此客户端，请升级服务端。'**
  String get incompatibleServerVersion;

  /// No description provided for @authErrorInvalidCredentials.
  ///
  /// In zh, this message translates to:
  /// **'用户名或密码错误'**
  String get authErrorInvalidCredentials;

  /// No description provided for @authErrorUsernameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入用户名'**
  String get authErrorUsernameRequired;

  /// No description provided for @authErrorPasswordRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入密码'**
  String get authErrorPasswordRequired;

  /// No description provided for @authErrorSessionExpired.
  ///
  /// In zh, this message translates to:
  /// **'登录状态已过期，请重新登录'**
  String get authErrorSessionExpired;

  /// No description provided for @authErrorServerMismatch.
  ///
  /// In zh, this message translates to:
  /// **'登录信息与服务端不匹配'**
  String get authErrorServerMismatch;

  /// No description provided for @networkError.
  ///
  /// In zh, this message translates to:
  /// **'网络异常，请稍后重试'**
  String get networkError;

  /// No description provided for @networkTimeout.
  ///
  /// In zh, this message translates to:
  /// **'请求超时，请稍后重试'**
  String get networkTimeout;

  /// No description provided for @parseError.
  ///
  /// In zh, this message translates to:
  /// **'数据解析失败'**
  String get parseError;

  /// No description provided for @serverError.
  ///
  /// In zh, this message translates to:
  /// **'服务端异常'**
  String get serverError;

  /// No description provided for @validationError.
  ///
  /// In zh, this message translates to:
  /// **'输入内容不合法'**
  String get validationError;

  /// No description provided for @unknownError.
  ///
  /// In zh, this message translates to:
  /// **'发生未知错误'**
  String get unknownError;

  /// No description provided for @navMedia.
  ///
  /// In zh, this message translates to:
  /// **'影视'**
  String get navMedia;

  /// No description provided for @navPeople.
  ///
  /// In zh, this message translates to:
  /// **'人物'**
  String get navPeople;

  /// No description provided for @navNovel.
  ///
  /// In zh, this message translates to:
  /// **'小说'**
  String get navNovel;

  /// No description provided for @navComic.
  ///
  /// In zh, this message translates to:
  /// **'漫画'**
  String get navComic;

  /// No description provided for @navSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get navSettings;

  /// No description provided for @navMain.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get navMain;

  /// No description provided for @mediaTitle.
  ///
  /// In zh, this message translates to:
  /// **'影视'**
  String get mediaTitle;

  /// No description provided for @mediaDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'影视详情'**
  String get mediaDetailTitle;

  /// No description provided for @peopleTitle.
  ///
  /// In zh, this message translates to:
  /// **'人物'**
  String get peopleTitle;

  /// No description provided for @mediaSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索影视'**
  String get mediaSearchHint;

  /// No description provided for @peopleSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索人物'**
  String get peopleSearchHint;

  /// No description provided for @novelSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索小说'**
  String get novelSearchHint;

  /// No description provided for @comicSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索漫画'**
  String get comicSearchHint;

  /// No description provided for @peopleDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'人物详情'**
  String get peopleDetailTitle;

  /// No description provided for @novelTitle.
  ///
  /// In zh, this message translates to:
  /// **'小说'**
  String get novelTitle;

  /// No description provided for @novelDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'小说详情'**
  String get novelDetailTitle;

  /// No description provided for @comicTitle.
  ///
  /// In zh, this message translates to:
  /// **'漫画'**
  String get comicTitle;

  /// No description provided for @comicDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'漫画详情'**
  String get comicDetailTitle;

  /// No description provided for @chapterList.
  ///
  /// In zh, this message translates to:
  /// **'章节列表'**
  String get chapterList;

  /// No description provided for @chapterCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 章'**
  String chapterCount(int count);

  /// No description provided for @loadMoreChapters.
  ///
  /// In zh, this message translates to:
  /// **'加载更多章节'**
  String get loadMoreChapters;

  /// No description provided for @startReading.
  ///
  /// In zh, this message translates to:
  /// **'开始阅读'**
  String get startReading;

  /// No description provided for @emptyContent.
  ///
  /// In zh, this message translates to:
  /// **'暂无内容'**
  String get emptyContent;

  /// No description provided for @emptySearchResult.
  ///
  /// In zh, this message translates to:
  /// **'没有找到相关内容'**
  String get emptySearchResult;

  /// No description provided for @emptyServerList.
  ///
  /// In zh, this message translates to:
  /// **'还没有可用的服务器'**
  String get emptyServerList;

  /// No description provided for @errorRetryHint.
  ///
  /// In zh, this message translates to:
  /// **'加载失败，请重试'**
  String get errorRetryHint;

  /// No description provided for @peopleRelatedContent.
  ///
  /// In zh, this message translates to:
  /// **'关联内容'**
  String get peopleRelatedContent;

  /// No description provided for @comicDetailPending.
  ///
  /// In zh, this message translates to:
  /// **'漫画阅读器将在后续版本提供'**
  String get comicDetailPending;

  /// No description provided for @novelReaderPending.
  ///
  /// In zh, this message translates to:
  /// **'小说阅读器将在后续版本提供'**
  String get novelReaderPending;

  /// No description provided for @mediaPlayerPending.
  ///
  /// In zh, this message translates to:
  /// **'播放功能将在后续版本提供'**
  String get mediaPlayerPending;

  /// No description provided for @releaseYear.
  ///
  /// In zh, this message translates to:
  /// **'年份'**
  String get releaseYear;

  /// No description provided for @rating.
  ///
  /// In zh, this message translates to:
  /// **'评分'**
  String get rating;

  /// No description provided for @overview.
  ///
  /// In zh, this message translates to:
  /// **'简介'**
  String get overview;

  /// No description provided for @noOverview.
  ///
  /// In zh, this message translates to:
  /// **'暂无简介'**
  String get noOverview;

  /// No description provided for @categories.
  ///
  /// In zh, this message translates to:
  /// **'分类'**
  String get categories;

  /// No description provided for @genres.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get genres;

  /// No description provided for @episodeCount.
  ///
  /// In zh, this message translates to:
  /// **'集数'**
  String get episodeCount;

  /// No description provided for @readCount.
  ///
  /// In zh, this message translates to:
  /// **'阅读'**
  String get readCount;

  /// No description provided for @author.
  ///
  /// In zh, this message translates to:
  /// **'作者'**
  String get author;

  /// No description provided for @status.
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get status;

  /// No description provided for @popularity.
  ///
  /// In zh, this message translates to:
  /// **'热度'**
  String get popularity;

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @settingsServer.
  ///
  /// In zh, this message translates to:
  /// **'服务器'**
  String get settingsServer;

  /// No description provided for @settingsAccount.
  ///
  /// In zh, this message translates to:
  /// **'账户'**
  String get settingsAccount;

  /// No description provided for @settingsAppearance.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get settingsAppearance;

  /// No description provided for @settingsLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get settingsLanguage;

  /// No description provided for @settingsAbout.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get settingsAbout;

  /// No description provided for @settingsUserInfo.
  ///
  /// In zh, this message translates to:
  /// **'用户信息'**
  String get settingsUserInfo;

  /// No description provided for @settingsLoginState.
  ///
  /// In zh, this message translates to:
  /// **'登录状态'**
  String get settingsLoginState;

  /// No description provided for @settingsSignedIn.
  ///
  /// In zh, this message translates to:
  /// **'已登录'**
  String get settingsSignedIn;

  /// No description provided for @settingsSignedOut.
  ///
  /// In zh, this message translates to:
  /// **'未登录'**
  String get settingsSignedOut;

  /// No description provided for @settingsChangeServer.
  ///
  /// In zh, this message translates to:
  /// **'切换服务器'**
  String get settingsChangeServer;

  /// No description provided for @themeFollowSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get themeFollowSystem;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get themeDark;

  /// No description provided for @languageChinese.
  ///
  /// In zh, this message translates to:
  /// **'中文'**
  String get languageChinese;

  /// No description provided for @languageEnglish.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @aboutVersion.
  ///
  /// In zh, this message translates to:
  /// **'版本'**
  String get aboutVersion;

  /// No description provided for @aboutLicense.
  ///
  /// In zh, this message translates to:
  /// **'开源协议'**
  String get aboutLicense;

  /// No description provided for @aboutProject.
  ///
  /// In zh, this message translates to:
  /// **'项目信息'**
  String get aboutProject;

  /// No description provided for @aboutLicenseValue.
  ///
  /// In zh, this message translates to:
  /// **'MIT License'**
  String get aboutLicenseValue;

  /// No description provided for @aboutProjectValue.
  ///
  /// In zh, this message translates to:
  /// **'AMMDS Client · Flutter 跨平台客户端'**
  String get aboutProjectValue;

  /// No description provided for @logLevel.
  ///
  /// In zh, this message translates to:
  /// **'日志级别'**
  String get logLevel;

  /// No description provided for @saved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get saved;

  /// No description provided for @apiVersion.
  ///
  /// In zh, this message translates to:
  /// **'API 版本'**
  String get apiVersion;

  /// No description provided for @serverVersion.
  ///
  /// In zh, this message translates to:
  /// **'服务端版本'**
  String get serverVersion;

  /// No description provided for @httpsEnabled.
  ///
  /// In zh, this message translates to:
  /// **'HTTPS'**
  String get httpsEnabled;

  /// No description provided for @capabilityMedia.
  ///
  /// In zh, this message translates to:
  /// **'影视'**
  String get capabilityMedia;

  /// No description provided for @capabilityPeople.
  ///
  /// In zh, this message translates to:
  /// **'人物'**
  String get capabilityPeople;

  /// No description provided for @capabilityNovel.
  ///
  /// In zh, this message translates to:
  /// **'小说'**
  String get capabilityNovel;

  /// No description provided for @capabilityComic.
  ///
  /// In zh, this message translates to:
  /// **'漫画'**
  String get capabilityComic;

  /// No description provided for @networkOnline.
  ///
  /// In zh, this message translates to:
  /// **'在线'**
  String get networkOnline;

  /// No description provided for @networkOffline.
  ///
  /// In zh, this message translates to:
  /// **'离线'**
  String get networkOffline;

  /// No description provided for @networkConnecting.
  ///
  /// In zh, this message translates to:
  /// **'正在连接'**
  String get networkConnecting;

  /// No description provided for @networkReconnecting.
  ///
  /// In zh, this message translates to:
  /// **'正在重连'**
  String get networkReconnecting;

  /// No description provided for @serverConnectionDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'未连接'**
  String get serverConnectionDisconnected;

  /// No description provided for @serverConnectionConnected.
  ///
  /// In zh, this message translates to:
  /// **'已连接'**
  String get serverConnectionConnected;

  /// No description provided for @serverConnectionUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'服务端不可用'**
  String get serverConnectionUnavailable;

  /// No description provided for @serverConnectionUnauthorized.
  ///
  /// In zh, this message translates to:
  /// **'未授权'**
  String get serverConnectionUnauthorized;

  /// No description provided for @authStateUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get authStateUnknown;

  /// No description provided for @authStateChecking.
  ///
  /// In zh, this message translates to:
  /// **'校验中'**
  String get authStateChecking;

  /// No description provided for @authStateAuthenticated.
  ///
  /// In zh, this message translates to:
  /// **'已认证'**
  String get authStateAuthenticated;

  /// No description provided for @authStateExpired.
  ///
  /// In zh, this message translates to:
  /// **'已过期'**
  String get authStateExpired;

  /// No description provided for @authStateUnauthenticated.
  ///
  /// In zh, this message translates to:
  /// **'未认证'**
  String get authStateUnauthenticated;

  /// No description provided for @welcomeBack.
  ///
  /// In zh, this message translates to:
  /// **'欢迎回来，{name}'**
  String welcomeBack(String name);

  /// No description provided for @mainShellPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'{feature}功能正在建设中'**
  String mainShellPlaceholder(String feature);

  /// No description provided for @managementTitle.
  ///
  /// In zh, this message translates to:
  /// **'管理'**
  String get managementTitle;

  /// No description provided for @managementProfile.
  ///
  /// In zh, this message translates to:
  /// **'个人信息'**
  String get managementProfile;

  /// No description provided for @managementProfileDesc.
  ///
  /// In zh, this message translates to:
  /// **'账号资料与登录状态'**
  String get managementProfileDesc;

  /// No description provided for @managementServer.
  ///
  /// In zh, this message translates to:
  /// **'服务器'**
  String get managementServer;

  /// No description provided for @managementServerDesc.
  ///
  /// In zh, this message translates to:
  /// **'当前服务端、切换与连接测试'**
  String get managementServerDesc;

  /// No description provided for @managementApp.
  ///
  /// In zh, this message translates to:
  /// **'应用配置'**
  String get managementApp;

  /// No description provided for @managementAppDesc.
  ///
  /// In zh, this message translates to:
  /// **'主题、语言与日志'**
  String get managementAppDesc;

  /// No description provided for @managementAbout.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get managementAbout;

  /// No description provided for @profileUsername.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get profileUsername;

  /// No description provided for @profileNickname.
  ///
  /// In zh, this message translates to:
  /// **'昵称'**
  String get profileNickname;

  /// No description provided for @profileRole.
  ///
  /// In zh, this message translates to:
  /// **'角色'**
  String get profileRole;

  /// No description provided for @profileEmail.
  ///
  /// In zh, this message translates to:
  /// **'邮箱'**
  String get profileEmail;

  /// No description provided for @profilePhone.
  ///
  /// In zh, this message translates to:
  /// **'手机号'**
  String get profilePhone;

  /// No description provided for @profileRegisteredAt.
  ///
  /// In zh, this message translates to:
  /// **'注册时间'**
  String get profileRegisteredAt;

  /// No description provided for @profileLastLoginAt.
  ///
  /// In zh, this message translates to:
  /// **'最近登录'**
  String get profileLastLoginAt;

  /// No description provided for @profileNotAvailable.
  ///
  /// In zh, this message translates to:
  /// **'未填写'**
  String get profileNotAvailable;

  /// No description provided for @profileRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新资料'**
  String get profileRefresh;

  /// No description provided for @profileRefreshSuccess.
  ///
  /// In zh, this message translates to:
  /// **'资料已更新'**
  String get profileRefreshSuccess;

  /// No description provided for @profileGuest.
  ///
  /// In zh, this message translates to:
  /// **'未登录用户'**
  String get profileGuest;

  /// No description provided for @roleAdmin.
  ///
  /// In zh, this message translates to:
  /// **'管理员'**
  String get roleAdmin;

  /// No description provided for @roleUser.
  ///
  /// In zh, this message translates to:
  /// **'普通用户'**
  String get roleUser;

  /// No description provided for @accountEnabled.
  ///
  /// In zh, this message translates to:
  /// **'账号状态'**
  String get accountEnabled;

  /// No description provided for @accountEnabledYes.
  ///
  /// In zh, this message translates to:
  /// **'正常'**
  String get accountEnabledYes;

  /// No description provided for @accountEnabledNo.
  ///
  /// In zh, this message translates to:
  /// **'已禁用'**
  String get accountEnabledNo;

  /// No description provided for @serverConnectionTest.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get serverConnectionTest;

  /// No description provided for @serverConnectionTesting.
  ///
  /// In zh, this message translates to:
  /// **'正在测试…'**
  String get serverConnectionTesting;

  /// No description provided for @serverConnectionSuccess.
  ///
  /// In zh, this message translates to:
  /// **'连接正常'**
  String get serverConnectionSuccess;

  /// No description provided for @serverDialect.
  ///
  /// In zh, this message translates to:
  /// **'接口方言'**
  String get serverDialect;

  /// No description provided for @serverDialectClientV1.
  ///
  /// In zh, this message translates to:
  /// **'Client API'**
  String get serverDialectClientV1;

  /// No description provided for @serverDialectPublic.
  ///
  /// In zh, this message translates to:
  /// **'公开接口'**
  String get serverDialectPublic;

  /// No description provided for @serverDiscoverNow.
  ///
  /// In zh, this message translates to:
  /// **'重新发现服务器'**
  String get serverDiscoverNow;

  /// No description provided for @serverSwitchNow.
  ///
  /// In zh, this message translates to:
  /// **'切换服务器'**
  String get serverSwitchNow;

  /// No description provided for @appTheme.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get appTheme;

  /// No description provided for @appLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get appLanguage;

  /// No description provided for @appLogLevel.
  ///
  /// In zh, this message translates to:
  /// **'日志级别'**
  String get appLogLevel;

  /// No description provided for @logLevelDebug.
  ///
  /// In zh, this message translates to:
  /// **'调试'**
  String get logLevelDebug;

  /// No description provided for @logLevelInfo.
  ///
  /// In zh, this message translates to:
  /// **'信息'**
  String get logLevelInfo;

  /// No description provided for @logLevelWarning.
  ///
  /// In zh, this message translates to:
  /// **'警告'**
  String get logLevelWarning;

  /// No description provided for @logLevelError.
  ///
  /// In zh, this message translates to:
  /// **'错误'**
  String get logLevelError;

  /// No description provided for @autoStart.
  ///
  /// In zh, this message translates to:
  /// **'开机自启'**
  String get autoStart;

  /// No description provided for @autoStartEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启开机自启'**
  String get autoStartEnabled;

  /// No description provided for @autoStartDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭开机自启'**
  String get autoStartDisabled;

  /// No description provided for @autoStartFailed.
  ///
  /// In zh, this message translates to:
  /// **'开机自启设置失败，请重试或检查系统权限'**
  String get autoStartFailed;

  /// No description provided for @trayShowWindow.
  ///
  /// In zh, this message translates to:
  /// **'显示主窗口'**
  String get trayShowWindow;

  /// No description provided for @trayAutoStartEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用开机自启'**
  String get trayAutoStartEnable;

  /// No description provided for @trayAutoStartDisable.
  ///
  /// In zh, this message translates to:
  /// **'禁用开机自启'**
  String get trayAutoStartDisable;

  /// No description provided for @trayWebsite.
  ///
  /// In zh, this message translates to:
  /// **'官网'**
  String get trayWebsite;

  /// No description provided for @trayHelp.
  ///
  /// In zh, this message translates to:
  /// **'帮助'**
  String get trayHelp;

  /// No description provided for @trayVersion.
  ///
  /// In zh, this message translates to:
  /// **'版本：{version}'**
  String trayVersion(String version);

  /// No description provided for @trayExit.
  ///
  /// In zh, this message translates to:
  /// **'退出应用'**
  String get trayExit;

  /// No description provided for @aboutClientVersion.
  ///
  /// In zh, this message translates to:
  /// **'客户端版本'**
  String get aboutClientVersion;

  /// No description provided for @aboutClientId.
  ///
  /// In zh, this message translates to:
  /// **'客户端标识'**
  String get aboutClientId;

  /// No description provided for @aboutProtocol.
  ///
  /// In zh, this message translates to:
  /// **'发现协议'**
  String get aboutProtocol;

  /// No description provided for @aboutProtocolValue.
  ///
  /// In zh, this message translates to:
  /// **'ammds-discovery v1'**
  String get aboutProtocolValue;

  /// No description provided for @logoutSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已退出登录'**
  String get logoutSuccess;

  /// No description provided for @appCopyright.
  ///
  /// In zh, this message translates to:
  /// **'© 新疆萌森软件开发工作室'**
  String get appCopyright;

  /// No description provided for @splashSkip.
  ///
  /// In zh, this message translates to:
  /// **'跳过'**
  String get splashSkip;

  /// No description provided for @splashSkipCountdown.
  ///
  /// In zh, this message translates to:
  /// **'跳过 {seconds}s'**
  String splashSkipCountdown(int seconds);

  /// No description provided for @loginSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get loginSettingsTitle;

  /// No description provided for @settingsGroupApp.
  ///
  /// In zh, this message translates to:
  /// **'外观与应用'**
  String get settingsGroupApp;

  /// No description provided for @settingsGroupData.
  ///
  /// In zh, this message translates to:
  /// **'数据与隐私'**
  String get settingsGroupData;

  /// No description provided for @clearCache.
  ///
  /// In zh, this message translates to:
  /// **'清除缓存'**
  String get clearCache;

  /// No description provided for @clearCacheConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'清除缓存'**
  String get clearCacheConfirmTitle;

  /// No description provided for @clearCacheConfirmMessage.
  ///
  /// In zh, this message translates to:
  /// **'将清理本地图片与界面缓存。不会影响登录状态与服务器配置。'**
  String get clearCacheConfirmMessage;

  /// No description provided for @clearCacheSuccess.
  ///
  /// In zh, this message translates to:
  /// **'缓存已清除'**
  String get clearCacheSuccess;

  /// No description provided for @copyrightPrivacy.
  ///
  /// In zh, this message translates to:
  /// **'版权与隐私'**
  String get copyrightPrivacy;

  /// No description provided for @copyrightPrivacyTitle.
  ///
  /// In zh, this message translates to:
  /// **'版权与隐私'**
  String get copyrightPrivacyTitle;

  /// No description provided for @copyrightPrivacyMessage.
  ///
  /// In zh, this message translates to:
  /// **'AMMDS Client 是 AMMDS 服务的终端客户端，用于连接并浏览你自有的 AMMDS 服务端。\n\n客户端不采集、不上传任何个人数据；登录凭据仅保存在本机安全存储（Keystore / Keychain）中。'**
  String get copyrightPrivacyMessage;

  /// No description provided for @rememberPassword.
  ///
  /// In zh, this message translates to:
  /// **'记住密码'**
  String get rememberPassword;

  /// No description provided for @forgotPassword.
  ///
  /// In zh, this message translates to:
  /// **'忘记密码？'**
  String get forgotPassword;

  /// No description provided for @forgotPasswordTitle.
  ///
  /// In zh, this message translates to:
  /// **'找回密码'**
  String get forgotPasswordTitle;

  /// No description provided for @forgotPasswordMessage.
  ///
  /// In zh, this message translates to:
  /// **'客户端无法重置服务端账号密码。\n\n请前往 AMMDS 服务端，使用「恢复密钥」自助重置，或联系管理员重置后再登录。'**
  String get forgotPasswordMessage;

  /// No description provided for @discoverLanServers.
  ///
  /// In zh, this message translates to:
  /// **'发现内网服务器'**
  String get discoverLanServers;

  /// No description provided for @detailSectionInfo.
  ///
  /// In zh, this message translates to:
  /// **'详细信息'**
  String get detailSectionInfo;

  /// No description provided for @detailSectionGallery.
  ///
  /// In zh, this message translates to:
  /// **'图集'**
  String get detailSectionGallery;

  /// No description provided for @continueReading.
  ///
  /// In zh, this message translates to:
  /// **'继续阅读'**
  String get continueReading;

  /// No description provided for @detailNoChapters.
  ///
  /// In zh, this message translates to:
  /// **'暂无章节'**
  String get detailNoChapters;

  /// No description provided for @detailLastRead.
  ///
  /// In zh, this message translates to:
  /// **'上次读到：{chapter}'**
  String detailLastRead(String chapter);

  /// No description provided for @promoteDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'官方推送'**
  String get promoteDialogTitle;

  /// No description provided for @promoteRead.
  ///
  /// In zh, this message translates to:
  /// **'已读'**
  String get promoteRead;

  /// No description provided for @promoteGo.
  ///
  /// In zh, this message translates to:
  /// **'前往'**
  String get promoteGo;

  /// No description provided for @promoteBannerFailed.
  ///
  /// In zh, this message translates to:
  /// **'配图无法加载'**
  String get promoteBannerFailed;

  /// No description provided for @mediaFilesTitle.
  ///
  /// In zh, this message translates to:
  /// **'播放资源'**
  String get mediaFilesTitle;

  /// No description provided for @mediaFilePlay.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get mediaFilePlay;

  /// No description provided for @mediaFileUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'不可用'**
  String get mediaFileUnavailable;

  /// No description provided for @mediaPlayback.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get mediaPlayback;

  /// No description provided for @playerPreparing.
  ///
  /// In zh, this message translates to:
  /// **'正在准备播放…'**
  String get playerPreparing;

  /// No description provided for @playerUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'无法播放'**
  String get playerUnavailable;

  /// No description provided for @playerSwitchSource.
  ///
  /// In zh, this message translates to:
  /// **'切换播放源'**
  String get playerSwitchSource;

  /// No description provided for @playerNoSource.
  ///
  /// In zh, this message translates to:
  /// **'暂无可播放资源'**
  String get playerNoSource;

  /// No description provided for @playerPlay.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get playerPlay;

  /// No description provided for @playerPause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get playerPause;

  /// No description provided for @playerBackward.
  ///
  /// In zh, this message translates to:
  /// **'后退 10 秒'**
  String get playerBackward;

  /// No description provided for @playerForward.
  ///
  /// In zh, this message translates to:
  /// **'前进 10 秒'**
  String get playerForward;

  /// No description provided for @playerVolume.
  ///
  /// In zh, this message translates to:
  /// **'音量'**
  String get playerVolume;

  /// No description provided for @playerMute.
  ///
  /// In zh, this message translates to:
  /// **'静音'**
  String get playerMute;

  /// No description provided for @playerUnmute.
  ///
  /// In zh, this message translates to:
  /// **'取消静音'**
  String get playerUnmute;

  /// No description provided for @playerSpeed.
  ///
  /// In zh, this message translates to:
  /// **'播放速度'**
  String get playerSpeed;

  /// No description provided for @playerSourceCurrent.
  ///
  /// In zh, this message translates to:
  /// **'正在播放'**
  String get playerSourceCurrent;

  /// No description provided for @playerBrightness.
  ///
  /// In zh, this message translates to:
  /// **'亮度'**
  String get playerBrightness;

  /// No description provided for @playerGestureHint.
  ///
  /// In zh, this message translates to:
  /// **'播放画面：单击播放或暂停，双击两侧快进快退，左右滑动调整进度，上下滑动调整音量与亮度'**
  String get playerGestureHint;

  /// No description provided for @readerChapterList.
  ///
  /// In zh, this message translates to:
  /// **'目录'**
  String get readerChapterList;

  /// No description provided for @readerSettings.
  ///
  /// In zh, this message translates to:
  /// **'阅读设置'**
  String get readerSettings;

  /// No description provided for @readerMode.
  ///
  /// In zh, this message translates to:
  /// **'阅读模式'**
  String get readerMode;

  /// No description provided for @readerModePaged.
  ///
  /// In zh, this message translates to:
  /// **'翻页'**
  String get readerModePaged;

  /// No description provided for @readerModeScroll.
  ///
  /// In zh, this message translates to:
  /// **'滚动'**
  String get readerModeScroll;

  /// No description provided for @readerFontSize.
  ///
  /// In zh, this message translates to:
  /// **'字号'**
  String get readerFontSize;

  /// No description provided for @readerLineHeight.
  ///
  /// In zh, this message translates to:
  /// **'行距'**
  String get readerLineHeight;

  /// No description provided for @readerContentWidth.
  ///
  /// In zh, this message translates to:
  /// **'版心'**
  String get readerContentWidth;

  /// No description provided for @readerPadding.
  ///
  /// In zh, this message translates to:
  /// **'页边距'**
  String get readerPadding;

  /// No description provided for @readerIndent.
  ///
  /// In zh, this message translates to:
  /// **'首行缩进'**
  String get readerIndent;

  /// No description provided for @readerPageAnimation.
  ///
  /// In zh, this message translates to:
  /// **'翻页动画'**
  String get readerPageAnimation;

  /// No description provided for @readerAutoNextChapter.
  ///
  /// In zh, this message translates to:
  /// **'章末自动下一章'**
  String get readerAutoNextChapter;

  /// No description provided for @readerOptionNarrow.
  ///
  /// In zh, this message translates to:
  /// **'窄'**
  String get readerOptionNarrow;

  /// No description provided for @readerOptionMedium.
  ///
  /// In zh, this message translates to:
  /// **'适中'**
  String get readerOptionMedium;

  /// No description provided for @readerOptionWide.
  ///
  /// In zh, this message translates to:
  /// **'宽'**
  String get readerOptionWide;

  /// No description provided for @readerNovelPageProgress.
  ///
  /// In zh, this message translates to:
  /// **'第 {page} / {total} 页'**
  String readerNovelPageProgress(int page, int total);

  /// No description provided for @readerBackground.
  ///
  /// In zh, this message translates to:
  /// **'背景'**
  String get readerBackground;

  /// No description provided for @readerBackgroundLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get readerBackgroundLight;

  /// No description provided for @readerBackgroundSepia.
  ///
  /// In zh, this message translates to:
  /// **'米黄'**
  String get readerBackgroundSepia;

  /// No description provided for @readerBackgroundGreen.
  ///
  /// In zh, this message translates to:
  /// **'护眼绿'**
  String get readerBackgroundGreen;

  /// No description provided for @readerBackgroundDark.
  ///
  /// In zh, this message translates to:
  /// **'夜间'**
  String get readerBackgroundDark;

  /// No description provided for @readerPrevChapter.
  ///
  /// In zh, this message translates to:
  /// **'上一章'**
  String get readerPrevChapter;

  /// No description provided for @readerNextChapter.
  ///
  /// In zh, this message translates to:
  /// **'下一章'**
  String get readerNextChapter;

  /// No description provided for @readerChapterEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无章节'**
  String get readerChapterEmpty;

  /// No description provided for @readerNoContent.
  ///
  /// In zh, this message translates to:
  /// **'本章暂无正文'**
  String get readerNoContent;

  /// No description provided for @readerChapterProgress.
  ///
  /// In zh, this message translates to:
  /// **'第 {current} / {total} 章'**
  String readerChapterProgress(int current, int total);

  /// No description provided for @readerSourceChapter.
  ///
  /// In zh, this message translates to:
  /// **'书源章节'**
  String get readerSourceChapter;

  /// No description provided for @comicReadMode.
  ///
  /// In zh, this message translates to:
  /// **'阅读模式'**
  String get comicReadMode;

  /// No description provided for @comicReadModePaged.
  ///
  /// In zh, this message translates to:
  /// **'翻页'**
  String get comicReadModePaged;

  /// No description provided for @comicReadModeContinuous.
  ///
  /// In zh, this message translates to:
  /// **'连续'**
  String get comicReadModeContinuous;

  /// No description provided for @comicReaderEmpty.
  ///
  /// In zh, this message translates to:
  /// **'本章暂无图片'**
  String get comicReaderEmpty;

  /// No description provided for @comicPageProgress.
  ///
  /// In zh, this message translates to:
  /// **'{current} / {total} 页'**
  String comicPageProgress(int current, int total);

  /// No description provided for @comicPageCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 页'**
  String comicPageCount(int count);

  /// No description provided for @attrOriginalTitle.
  ///
  /// In zh, this message translates to:
  /// **'原名'**
  String get attrOriginalTitle;

  /// No description provided for @attrTagline.
  ///
  /// In zh, this message translates to:
  /// **'标语'**
  String get attrTagline;

  /// No description provided for @attrRuntime.
  ///
  /// In zh, this message translates to:
  /// **'时长(分钟)'**
  String get attrRuntime;

  /// No description provided for @attrPremiered.
  ///
  /// In zh, this message translates to:
  /// **'首播日期'**
  String get attrPremiered;

  /// No description provided for @attrCountry.
  ///
  /// In zh, this message translates to:
  /// **'国家/地区'**
  String get attrCountry;

  /// No description provided for @attrLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get attrLanguage;

  /// No description provided for @attrMpaa.
  ///
  /// In zh, this message translates to:
  /// **'分级'**
  String get attrMpaa;

  /// No description provided for @attrStudio.
  ///
  /// In zh, this message translates to:
  /// **'出品'**
  String get attrStudio;

  /// No description provided for @attrResolution.
  ///
  /// In zh, this message translates to:
  /// **'分辨率'**
  String get attrResolution;

  /// No description provided for @attrVideoCodec.
  ///
  /// In zh, this message translates to:
  /// **'视频编码'**
  String get attrVideoCodec;

  /// No description provided for @attrAudioCodec.
  ///
  /// In zh, this message translates to:
  /// **'音频编码'**
  String get attrAudioCodec;

  /// No description provided for @attrFileSize.
  ///
  /// In zh, this message translates to:
  /// **'文件大小'**
  String get attrFileSize;

  /// No description provided for @attrCast.
  ///
  /// In zh, this message translates to:
  /// **'演员'**
  String get attrCast;

  /// No description provided for @attrGender.
  ///
  /// In zh, this message translates to:
  /// **'性别'**
  String get attrGender;

  /// No description provided for @attrBirthDate.
  ///
  /// In zh, this message translates to:
  /// **'出生日期'**
  String get attrBirthDate;

  /// No description provided for @attrAge.
  ///
  /// In zh, this message translates to:
  /// **'年龄'**
  String get attrAge;

  /// No description provided for @attrHeight.
  ///
  /// In zh, this message translates to:
  /// **'身高(cm)'**
  String get attrHeight;

  /// No description provided for @attrWeight.
  ///
  /// In zh, this message translates to:
  /// **'体重(kg)'**
  String get attrWeight;

  /// No description provided for @attrNationality.
  ///
  /// In zh, this message translates to:
  /// **'国籍'**
  String get attrNationality;

  /// No description provided for @attrBloodType.
  ///
  /// In zh, this message translates to:
  /// **'血型'**
  String get attrBloodType;

  /// No description provided for @attrCupSize.
  ///
  /// In zh, this message translates to:
  /// **'罩杯'**
  String get attrCupSize;

  /// No description provided for @attrDebutDate.
  ///
  /// In zh, this message translates to:
  /// **'出道日期'**
  String get attrDebutDate;

  /// No description provided for @attrRetired.
  ///
  /// In zh, this message translates to:
  /// **'退役'**
  String get attrRetired;

  /// No description provided for @attrDeceased.
  ///
  /// In zh, this message translates to:
  /// **'已故'**
  String get attrDeceased;

  /// No description provided for @attrAliases.
  ///
  /// In zh, this message translates to:
  /// **'别名'**
  String get attrAliases;

  /// No description provided for @attrStyle.
  ///
  /// In zh, this message translates to:
  /// **'风格'**
  String get attrStyle;

  /// No description provided for @attrSpecialFeatures.
  ///
  /// In zh, this message translates to:
  /// **'特征'**
  String get attrSpecialFeatures;

  /// No description provided for @attrStatus.
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get attrStatus;

  /// No description provided for @attrGenre.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get attrGenre;

  /// No description provided for @attrPublisher.
  ///
  /// In zh, this message translates to:
  /// **'出版社'**
  String get attrPublisher;

  /// No description provided for @attrPublishYear.
  ///
  /// In zh, this message translates to:
  /// **'出版年份'**
  String get attrPublishYear;

  /// No description provided for @attrPageCount.
  ///
  /// In zh, this message translates to:
  /// **'页数'**
  String get attrPageCount;

  /// No description provided for @attrChapterCount.
  ///
  /// In zh, this message translates to:
  /// **'章节数'**
  String get attrChapterCount;

  /// No description provided for @attrIsbn.
  ///
  /// In zh, this message translates to:
  /// **'ISBN'**
  String get attrIsbn;

  /// No description provided for @attrSeries.
  ///
  /// In zh, this message translates to:
  /// **'系列'**
  String get attrSeries;

  /// No description provided for @attrSource.
  ///
  /// In zh, this message translates to:
  /// **'来源'**
  String get attrSource;

  /// No description provided for @attrType.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get attrType;

  /// No description provided for @attrSeason.
  ///
  /// In zh, this message translates to:
  /// **'季'**
  String get attrSeason;

  /// No description provided for @attrPhotoCount.
  ///
  /// In zh, this message translates to:
  /// **'图片数'**
  String get attrPhotoCount;

  /// No description provided for @attrPublishDate.
  ///
  /// In zh, this message translates to:
  /// **'出版日期'**
  String get attrPublishDate;

  /// No description provided for @attrFormat.
  ///
  /// In zh, this message translates to:
  /// **'格式'**
  String get attrFormat;

  /// No description provided for @attrAgeRating.
  ///
  /// In zh, this message translates to:
  /// **'年龄分级'**
  String get attrAgeRating;

  /// No description provided for @attrCommunityRating.
  ///
  /// In zh, this message translates to:
  /// **'社区评分'**
  String get attrCommunityRating;

  /// No description provided for @attrManga.
  ///
  /// In zh, this message translates to:
  /// **'阅读方向'**
  String get attrManga;

  /// No description provided for @attrFullChapter.
  ///
  /// In zh, this message translates to:
  /// **'全集'**
  String get attrFullChapter;

  /// No description provided for @attrBlackWhite.
  ///
  /// In zh, this message translates to:
  /// **'黑白'**
  String get attrBlackWhite;

  /// No description provided for @attrWriter.
  ///
  /// In zh, this message translates to:
  /// **'编剧'**
  String get attrWriter;

  /// No description provided for @attrPenciller.
  ///
  /// In zh, this message translates to:
  /// **'线稿'**
  String get attrPenciller;

  /// No description provided for @attrInker.
  ///
  /// In zh, this message translates to:
  /// **'勾线'**
  String get attrInker;

  /// No description provided for @attrColorist.
  ///
  /// In zh, this message translates to:
  /// **'上色'**
  String get attrColorist;

  /// No description provided for @attrLetterer.
  ///
  /// In zh, this message translates to:
  /// **'字体排版'**
  String get attrLetterer;

  /// No description provided for @attrCoverArtist.
  ///
  /// In zh, this message translates to:
  /// **'封面绘制'**
  String get attrCoverArtist;

  /// No description provided for @attrEditor.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get attrEditor;

  /// No description provided for @attrTranslator.
  ///
  /// In zh, this message translates to:
  /// **'翻译'**
  String get attrTranslator;

  /// No description provided for @attrCharacters.
  ///
  /// In zh, this message translates to:
  /// **'角色'**
  String get attrCharacters;

  /// No description provided for @attrTeams.
  ///
  /// In zh, this message translates to:
  /// **'团队'**
  String get attrTeams;

  /// No description provided for @attrLocations.
  ///
  /// In zh, this message translates to:
  /// **'地点'**
  String get attrLocations;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
