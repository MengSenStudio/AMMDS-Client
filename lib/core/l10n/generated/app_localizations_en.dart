// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'AMMDS';

  @override
  String get appName => 'AMMDS Client';

  @override
  String get slogan => 'Connect to your AMMDS library';

  @override
  String get bootstrapInitializing => 'Initializing…';

  @override
  String get bootstrapLoadingConfig => 'Loading local configuration…';

  @override
  String get bootstrapInitializingStorage => 'Initializing storage…';

  @override
  String get bootstrapInitializingNetwork => 'Initializing network…';

  @override
  String get bootstrapRestoringSession => 'Restoring session…';

  @override
  String get bootstrapConnectingServer => 'Connecting to server…';

  @override
  String get loginTitle => 'Sign in';

  @override
  String get loginSubtitle => 'Sign in to an AMMDS server to start browsing';

  @override
  String get usernameLabel => 'Username';

  @override
  String get usernameHint => 'Enter your username';

  @override
  String get passwordLabel => 'Password';

  @override
  String get passwordHint => 'Enter your password';

  @override
  String get loginButton => 'Sign in';

  @override
  String get loggingIn => 'Signing in…';

  @override
  String get logout => 'Sign out';

  @override
  String get logoutConfirmTitle => 'Sign out';

  @override
  String get logoutConfirmMessage => 'Are you sure you want to sign out?';

  @override
  String get confirm => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Retry';

  @override
  String get refresh => 'Refresh';

  @override
  String get back => 'Back';

  @override
  String get save => 'Save';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get search => 'Search';

  @override
  String get searchHint => 'Search keywords';

  @override
  String get clear => 'Clear';

  @override
  String get all => 'All';

  @override
  String get unknown => 'Unknown';

  @override
  String get optional => 'Optional';

  @override
  String get loading => 'Loading…';

  @override
  String get loadingMore => 'Loading more…';

  @override
  String get noMore => 'No more items';

  @override
  String get pullToRefresh => 'Pull to refresh';

  @override
  String get releaseToRefresh => 'Release to refresh';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get serverSectionTitle => 'Server';

  @override
  String get discoverServers => 'Discover servers';

  @override
  String get discovering => 'Searching for nearby AMMDS services…';

  @override
  String discoveryFoundCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count servers found',
      one: '1 server found',
    );
    return '$_temp0';
  }

  @override
  String get discoveryNotFound =>
      'No server found. Make sure your phone and the server are on the same subnet and UDP 47823 is allowed, or enter the address manually.';

  @override
  String get discoveryFailed =>
      'Discovery failed. Check your network or add a server manually.';

  @override
  String get discoveryUnsupported =>
      'LAN discovery is not available on this platform';

  @override
  String get discoveryUnsupportedHint =>
      'Browsers cannot send or receive UDP. Enter the server address manually.';

  @override
  String get rescan => 'Search again';

  @override
  String get discoveryResultsTitle => 'Search results';

  @override
  String get discoveryHistoryTitle => 'Recent servers';

  @override
  String get discoveryHistoryEmpty =>
      'Servers you have connected to will appear here';

  @override
  String get discoverySkippedHint =>
      'Addresses such as router / hotspot gateways were skipped';

  @override
  String get serverList => 'Servers';

  @override
  String get selectServer => 'Select a server';

  @override
  String get currentServer => 'Current server';

  @override
  String get switchServer => 'Switch server';

  @override
  String get manualServer => 'Add manually';

  @override
  String get manualServerTitle => 'Manual server setup';

  @override
  String get serverAddress => 'Server address';

  @override
  String get serverAddressHint => 'http://192.168.1.100:8080';

  @override
  String get serverName => 'Server name';

  @override
  String get serverPort => 'Port';

  @override
  String get serverProtocol => 'Protocol';

  @override
  String get testConnection => 'Test connection';

  @override
  String get testing => 'Testing…';

  @override
  String get connectSuccess => 'Connected';

  @override
  String get missingServerAddress => 'Please select or enter a server address';

  @override
  String get serverDuplicate => 'This server is already in the list';

  @override
  String get removeServer => 'Remove server';

  @override
  String get noServerConfigured => 'No server configured yet';

  @override
  String get discoveryCapabilities => 'Capabilities';

  @override
  String get connectionFailed => 'Connection failed';

  @override
  String get connectionFailedServerNotFound =>
      'Server not found. Please check the address.';

  @override
  String get connectionFailedNetworkUnreachable =>
      'Network unreachable. Please check your connection.';

  @override
  String get connectionFailedPortUnavailable =>
      'Port unavailable. The server may not be running.';

  @override
  String get connectionFailedServerRefused =>
      'The server refused the connection';

  @override
  String get connectionFailedUnauthorized =>
      'Authentication failed. Please sign in again.';

  @override
  String get incompatibleServerVersion =>
      'This client is not supported by the current server version. Please upgrade the server.';

  @override
  String get authErrorInvalidCredentials => 'Incorrect username or password';

  @override
  String get authErrorUsernameRequired => 'Username is required';

  @override
  String get authErrorPasswordRequired => 'Password is required';

  @override
  String get authErrorSessionExpired =>
      'Your session has expired. Please sign in again.';

  @override
  String get authErrorServerMismatch => 'Credentials do not match this server';

  @override
  String get networkError => 'Network error. Please try again later.';

  @override
  String get networkTimeout => 'Request timed out. Please try again later.';

  @override
  String get parseError => 'Failed to parse server response';

  @override
  String get serverError => 'Server error';

  @override
  String get validationError => 'Invalid input';

  @override
  String get unknownError => 'An unknown error occurred';

  @override
  String get navMedia => 'Media';

  @override
  String get navPeople => 'People';

  @override
  String get navNovel => 'Novels';

  @override
  String get navComic => 'Comics';

  @override
  String get navSettings => 'Settings';

  @override
  String get navMain => 'Home';

  @override
  String get mediaTitle => 'Media';

  @override
  String get mediaDetailTitle => 'Media details';

  @override
  String get peopleTitle => 'People';

  @override
  String get mediaSearchHint => 'Search media';

  @override
  String get peopleSearchHint => 'Search people';

  @override
  String get novelSearchHint => 'Search novels';

  @override
  String get comicSearchHint => 'Search comics';

  @override
  String get peopleDetailTitle => 'Person details';

  @override
  String get novelTitle => 'Novels';

  @override
  String get novelDetailTitle => 'Novel details';

  @override
  String get comicTitle => 'Comics';

  @override
  String get comicDetailTitle => 'Comic details';

  @override
  String get chapterList => 'Chapters';

  @override
  String chapterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chapters',
      one: '1 chapter',
    );
    return '$_temp0';
  }

  @override
  String get loadMoreChapters => 'Load more chapters';

  @override
  String get startReading => 'Start reading';

  @override
  String get emptyContent => 'No content yet';

  @override
  String get emptySearchResult => 'No matching result';

  @override
  String get emptyServerList => 'No server available yet';

  @override
  String get errorRetryHint => 'Failed to load. Please retry.';

  @override
  String get peopleRelatedContent => 'Related content';

  @override
  String get comicDetailPending =>
      'The comic reader will arrive in a later version';

  @override
  String get novelReaderPending =>
      'The novel reader will arrive in a later version';

  @override
  String get mediaPlayerPending => 'Playback will arrive in a later version';

  @override
  String get releaseYear => 'Year';

  @override
  String get rating => 'Rating';

  @override
  String get overview => 'Overview';

  @override
  String get noOverview => 'No overview';

  @override
  String get categories => 'Categories';

  @override
  String get genres => 'Genres';

  @override
  String get episodeCount => 'Episodes';

  @override
  String get readCount => 'Readers';

  @override
  String get author => 'Author';

  @override
  String get status => 'Status';

  @override
  String get popularity => 'Popularity';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsServer => 'Server';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsUserInfo => 'User profile';

  @override
  String get settingsLoginState => 'Sign-in state';

  @override
  String get settingsSignedIn => 'Signed in';

  @override
  String get settingsSignedOut => 'Signed out';

  @override
  String get settingsChangeServer => 'Switch server';

  @override
  String get themeFollowSystem => 'Follow system';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get languageChinese => '中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutLicense => 'License';

  @override
  String get aboutProject => 'Project';

  @override
  String get aboutLicenseValue => 'MIT License';

  @override
  String get aboutProjectValue =>
      'AMMDS Client · Flutter cross-platform client';

  @override
  String get logLevel => 'Log level';

  @override
  String get saved => 'Saved';

  @override
  String get apiVersion => 'API version';

  @override
  String get serverVersion => 'Server version';

  @override
  String get httpsEnabled => 'HTTPS';

  @override
  String get capabilityMedia => 'Media';

  @override
  String get capabilityPeople => 'People';

  @override
  String get capabilityNovel => 'Novel';

  @override
  String get capabilityComic => 'Comic';

  @override
  String get networkOnline => 'Online';

  @override
  String get networkOffline => 'Offline';

  @override
  String get networkConnecting => 'Connecting';

  @override
  String get networkReconnecting => 'Reconnecting';

  @override
  String get serverConnectionDisconnected => 'Disconnected';

  @override
  String get serverConnectionConnected => 'Connected';

  @override
  String get serverConnectionUnavailable => 'Server unavailable';

  @override
  String get serverConnectionUnauthorized => 'Unauthorized';

  @override
  String get authStateUnknown => 'Unknown';

  @override
  String get authStateChecking => 'Checking';

  @override
  String get authStateAuthenticated => 'Authenticated';

  @override
  String get authStateExpired => 'Expired';

  @override
  String get authStateUnauthenticated => 'Unauthenticated';

  @override
  String welcomeBack(String name) {
    return 'Welcome back, $name';
  }

  @override
  String mainShellPlaceholder(String feature) {
    return '$feature is under construction';
  }

  @override
  String get managementTitle => 'Manage';

  @override
  String get managementProfile => 'Profile';

  @override
  String get managementProfileDesc => 'Account details and sign-in state';

  @override
  String get managementServer => 'Server';

  @override
  String get managementServerDesc =>
      'Current server, switching and connection test';

  @override
  String get managementApp => 'App settings';

  @override
  String get managementAppDesc => 'Theme, language and logging';

  @override
  String get managementAbout => 'About';

  @override
  String get profileUsername => 'Username';

  @override
  String get profileNickname => 'Nickname';

  @override
  String get profileRole => 'Role';

  @override
  String get profileEmail => 'Email';

  @override
  String get profilePhone => 'Phone';

  @override
  String get profileRegisteredAt => 'Registered';

  @override
  String get profileLastLoginAt => 'Last sign-in';

  @override
  String get profileNotAvailable => 'Not set';

  @override
  String get profileRefresh => 'Refresh profile';

  @override
  String get profileRefreshSuccess => 'Profile updated';

  @override
  String get profileGuest => 'Not signed in';

  @override
  String get roleAdmin => 'Administrator';

  @override
  String get roleUser => 'User';

  @override
  String get accountEnabled => 'Account status';

  @override
  String get accountEnabledYes => 'Active';

  @override
  String get accountEnabledNo => 'Disabled';

  @override
  String get serverConnectionTest => 'Test connection';

  @override
  String get serverConnectionTesting => 'Testing…';

  @override
  String get serverConnectionSuccess => 'Connection OK';

  @override
  String get serverDialect => 'API dialect';

  @override
  String get serverDialectClientV1 => 'Client API';

  @override
  String get serverDialectPublic => 'Public API';

  @override
  String get serverDiscoverNow => 'Search servers again';

  @override
  String get serverSwitchNow => 'Switch server';

  @override
  String get appTheme => 'Theme';

  @override
  String get appLanguage => 'Language';

  @override
  String get appLogLevel => 'Log level';

  @override
  String get logLevelDebug => 'Debug';

  @override
  String get logLevelInfo => 'Info';

  @override
  String get logLevelWarning => 'Warning';

  @override
  String get logLevelError => 'Error';

  @override
  String get autoStart => 'Launch at startup';

  @override
  String get autoStartEnabled => 'Launch at startup enabled';

  @override
  String get autoStartDisabled => 'Launch at startup disabled';

  @override
  String get autoStartFailed =>
      'Failed to change the startup setting, please retry';

  @override
  String get trayShowWindow => 'Show main window';

  @override
  String get trayAutoStartEnable => 'Enable launch at startup';

  @override
  String get trayAutoStartDisable => 'Disable launch at startup';

  @override
  String get trayWebsite => 'Website';

  @override
  String get trayHelp => 'Help';

  @override
  String trayVersion(String version) {
    return 'Version: $version';
  }

  @override
  String get trayExit => 'Quit';

  @override
  String get aboutClientVersion => 'Client version';

  @override
  String get aboutClientId => 'Client ID';

  @override
  String get aboutProtocol => 'Discovery protocol';

  @override
  String get aboutProtocolValue => 'ammds-discovery v1';

  @override
  String get logoutSuccess => 'Signed out';

  @override
  String get appCopyright => '© Xinjiang Mengsen Software Development Studio';

  @override
  String get splashSkip => 'Skip';

  @override
  String splashSkipCountdown(int seconds) {
    return 'Skip ${seconds}s';
  }

  @override
  String get loginSettingsTitle => 'Settings';

  @override
  String get settingsGroupApp => 'Appearance & app';

  @override
  String get settingsGroupData => 'Data & privacy';

  @override
  String get clearCache => 'Clear cache';

  @override
  String get clearCacheConfirmTitle => 'Clear cache';

  @override
  String get clearCacheConfirmMessage =>
      'Clears local image and UI caches. Your sign-in state and server configuration are not affected.';

  @override
  String get clearCacheSuccess => 'Cache cleared';

  @override
  String get copyrightPrivacy => 'Copyright & privacy';

  @override
  String get copyrightPrivacyTitle => 'Copyright & privacy';

  @override
  String get copyrightPrivacyMessage =>
      'AMMDS Client is the terminal client for AMMDS, used to connect to and browse your own AMMDS server.\n\nIt does not collect or upload any personal data; sign-in credentials are stored only in the local secure storage (Keystore / Keychain).';

  @override
  String get rememberPassword => 'Remember password';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get forgotPasswordTitle => 'Password recovery';

  @override
  String get forgotPasswordMessage =>
      'The client cannot reset a server account password.\n\nPlease use the recovery key on your AMMDS server, or ask the administrator to reset it, then sign in again.';

  @override
  String get discoverLanServers => 'Discover LAN servers';

  @override
  String get detailSectionInfo => 'Details';

  @override
  String get detailSectionGallery => 'Gallery';

  @override
  String get continueReading => 'Continue reading';

  @override
  String get detailNoChapters => 'No chapters';

  @override
  String detailLastRead(String chapter) {
    return 'Last read: $chapter';
  }

  @override
  String get promoteDialogTitle => 'Official notice';

  @override
  String get promoteRead => 'Mark as read';

  @override
  String get promoteGo => 'Open';

  @override
  String get promoteBannerFailed => 'Image unavailable';

  @override
  String get mediaFilesTitle => 'Playable sources';

  @override
  String get mediaFilePlay => 'Play';

  @override
  String get mediaFileUnavailable => 'Unavailable';

  @override
  String get mediaPlayback => 'Play';

  @override
  String get playerPreparing => 'Preparing playback…';

  @override
  String get playerUnavailable => 'Cannot play';

  @override
  String get playerSwitchSource => 'Switch source';

  @override
  String get playerNoSource => 'No playable source';

  @override
  String get playerPlay => 'Play';

  @override
  String get playerPause => 'Pause';

  @override
  String get playerBackward => 'Back 10 seconds';

  @override
  String get playerForward => 'Forward 10 seconds';

  @override
  String get playerVolume => 'Volume';

  @override
  String get playerMute => 'Mute';

  @override
  String get playerUnmute => 'Unmute';

  @override
  String get playerSpeed => 'Playback speed';

  @override
  String get playerSourceCurrent => 'Now playing';

  @override
  String get playerBrightness => 'Brightness';

  @override
  String get playerGestureHint =>
      'Video area: tap to play or pause, double-tap either side to seek, swipe horizontally to scrub, swipe vertically for volume and brightness';

  @override
  String get readerChapterList => 'Contents';

  @override
  String get readerSettings => 'Reading settings';

  @override
  String get readerMode => 'Reading mode';

  @override
  String get readerModePaged => 'Paged';

  @override
  String get readerModeScroll => 'Scroll';

  @override
  String get readerFontSize => 'Font size';

  @override
  String get readerLineHeight => 'Line height';

  @override
  String get readerContentWidth => 'Page width';

  @override
  String get readerPadding => 'Page margin';

  @override
  String get readerIndent => 'First-line indent';

  @override
  String get readerPageAnimation => 'Page animation';

  @override
  String get readerAutoNextChapter => 'Auto next chapter';

  @override
  String get readerOptionNarrow => 'Narrow';

  @override
  String get readerOptionMedium => 'Medium';

  @override
  String get readerOptionWide => 'Wide';

  @override
  String readerNovelPageProgress(int page, int total) {
    return 'Page $page / $total';
  }

  @override
  String get readerBackground => 'Background';

  @override
  String get readerBackgroundLight => 'Light';

  @override
  String get readerBackgroundSepia => 'Sepia';

  @override
  String get readerBackgroundGreen => 'Eye-care green';

  @override
  String get readerBackgroundDark => 'Dark';

  @override
  String get readerPrevChapter => 'Previous';

  @override
  String get readerNextChapter => 'Next';

  @override
  String get readerChapterEmpty => 'No chapters';

  @override
  String get readerNoContent => 'No content in this chapter';

  @override
  String readerChapterProgress(int current, int total) {
    return 'Chapter $current / $total';
  }

  @override
  String get readerSourceChapter => 'Online source chapter';

  @override
  String get comicReadMode => 'Reading mode';

  @override
  String get comicReadModePaged => 'Paged';

  @override
  String get comicReadModeContinuous => 'Continuous';

  @override
  String get comicReaderEmpty => 'No images in this chapter';

  @override
  String comicPageProgress(int current, int total) {
    return '$current / $total pages';
  }

  @override
  String comicPageCount(int count) {
    return '$count pages';
  }

  @override
  String get attrOriginalTitle => 'Original title';

  @override
  String get attrTagline => 'Tagline';

  @override
  String get attrRuntime => 'Runtime (min)';

  @override
  String get attrPremiered => 'Premiered';

  @override
  String get attrCountry => 'Country/Region';

  @override
  String get attrLanguage => 'Language';

  @override
  String get attrMpaa => 'Rated';

  @override
  String get attrStudio => 'Studio';

  @override
  String get attrResolution => 'Resolution';

  @override
  String get attrVideoCodec => 'Video codec';

  @override
  String get attrAudioCodec => 'Audio codec';

  @override
  String get attrFileSize => 'File size';

  @override
  String get attrCast => 'Cast';

  @override
  String get attrGender => 'Gender';

  @override
  String get attrBirthDate => 'Birth date';

  @override
  String get attrAge => 'Age';

  @override
  String get attrHeight => 'Height (cm)';

  @override
  String get attrWeight => 'Weight (kg)';

  @override
  String get attrNationality => 'Nationality';

  @override
  String get attrBloodType => 'Blood type';

  @override
  String get attrCupSize => 'Cup size';

  @override
  String get attrDebutDate => 'Debut date';

  @override
  String get attrRetired => 'Retired';

  @override
  String get attrDeceased => 'Deceased';

  @override
  String get attrAliases => 'Also known as';

  @override
  String get attrStyle => 'Style';

  @override
  String get attrSpecialFeatures => 'Special features';

  @override
  String get attrStatus => 'Status';

  @override
  String get attrGenre => 'Genre';

  @override
  String get attrPublisher => 'Publisher';

  @override
  String get attrPublishYear => 'Publish year';

  @override
  String get attrPageCount => 'Pages';

  @override
  String get attrChapterCount => 'Chapters';

  @override
  String get attrIsbn => 'ISBN';

  @override
  String get attrSeries => 'Series';

  @override
  String get attrSource => 'Source';

  @override
  String get attrType => 'Type';

  @override
  String get attrSeason => 'Season';

  @override
  String get attrPhotoCount => 'Images';

  @override
  String get attrPublishDate => 'Publish date';

  @override
  String get attrFormat => 'Format';

  @override
  String get attrAgeRating => 'Age rating';

  @override
  String get attrCommunityRating => 'Community rating';

  @override
  String get attrManga => 'Reading direction';

  @override
  String get attrFullChapter => 'Complete';

  @override
  String get attrBlackWhite => 'Black & white';

  @override
  String get attrWriter => 'Writer';

  @override
  String get attrPenciller => 'Penciller';

  @override
  String get attrInker => 'Inker';

  @override
  String get attrColorist => 'Colorist';

  @override
  String get attrLetterer => 'Letterer';

  @override
  String get attrCoverArtist => 'Cover artist';

  @override
  String get attrEditor => 'Editor';

  @override
  String get attrTranslator => 'Translator';

  @override
  String get attrCharacters => 'Characters';

  @override
  String get attrTeams => 'Teams';

  @override
  String get attrLocations => 'Locations';
}
