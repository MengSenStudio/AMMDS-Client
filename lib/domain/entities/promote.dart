/// 官方推送通告（promote）领域模型。
///
/// 与服务端前端的 `app/src/utils/promote.ts` 保持同一套语义：
/// * 数据源是远端 JSON（`https://file.lifebus.top/ammds/notice/promote.json`），
///   而不是 AMMDS 服务端的系统通知（那是后台消息中心的数据，用途不同）；
/// * **展示条件** = 当前时间落在 `[pushTime, endTime]` 内 **且** 当日未读；
/// * 「已读」是**当日已读**：只抑制当天的展示，次日若仍在窗口内会再次出现。
library;

/// 一条官方推送通告。
final class AppPromote {
  /// 创建通告。
  const AppPromote({
    required this.id,
    required this.title,
    this.description,
    this.tip,
    this.pushTime,
    this.endTime,
    this.banner,
    this.website,
    this.dialogTitle,
    this.buttonText,
  });

  /// 通告唯一标识。
  final String id;

  /// 标题。
  final String title;

  /// 正文描述。
  final String? description;

  /// 附加提示文案。
  final String? tip;

  /// 推送开始时间；缺失表示立即开始。
  final DateTime? pushTime;

  /// 推送结束时间。
  final DateTime? endTime;

  /// banner 图片地址。
  final Uri? banner;

  /// 跳转地址（官网 / 详情页）。
  final Uri? website;

  /// 弹窗标题。
  final String? dialogTitle;

  /// 主按钮文案。
  final String? buttonText;

  /// 当前时间是否处于推送窗口内。
  bool inWindow(DateTime now) {
    final start = pushTime;
    if (start != null && now.isBefore(start)) {
      return false;
    }
    final end = endTime;
    if (end == null) {
      // 结束时间无法解析时按「不在窗口内」处理，与网页端一致
      return false;
    }
    return !now.isAfter(end);
  }

  /// 解析远端/缓存条目；`id` 非空是唯一的硬性要求。
  static AppPromote? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    return AppPromote(
      id: id,
      title: _string(json['title']) ?? '',
      description: _string(json['description']),
      tip: _string(json['tip']),
      pushTime: _date(json['pushTime']),
      endTime: _date(json['endTime']),
      banner: _uri(json['banner']),
      website: _uri(json['website']),
      dialogTitle: _string(json['dialogTitle']),
      buttonText: _string(json['buttonText']),
    );
  }

  static String? _string(Object? value) {
    if (value is String) {
      return value.isEmpty ? null : value;
    }
    return null;
  }

  /// 解析时间；服务端使用 `yyyy-MM-dd HH:mm:ss`（无时区），按本地时间处理，
  /// 与网页端 `new Date('2026-09-21 00:00:00')` 的口径一致。
  static DateTime? _date(Object? value) {
    final text = _string(value);
    if (text == null) {
      return null;
    }
    return DateTime.tryParse(text.replaceFirst(' ', 'T'));
  }

  static Uri? _uri(Object? value) {
    final text = _string(value);
    if (text == null) {
      return null;
    }
    return Uri.tryParse(text);
  }
}
