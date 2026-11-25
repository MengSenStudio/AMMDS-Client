import 'package:flutter/widgets.dart';

import '../l10n/generated/app_localizations.dart';

export '../l10n/generated/app_localizations.dart';

/// 国际化便捷访问（文档 #7.1）。
///
/// ```dart
/// Text(context.l10n.loginButton)
/// ```
extension AppLocalizationsContext on BuildContext {
  /// 当前语言的文案集合。
  AppLocalizations get l10n => AppLocalizations.of(this);
}
