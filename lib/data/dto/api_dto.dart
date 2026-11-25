import '../../core/utils/novel_text.dart';
import '../../core/utils/resource_uri.dart';
import '../../domain/entities/auth.dart';
import '../../domain/entities/content.dart';
import '../../domain/entities/reading.dart';
import '../../domain/entities/splash.dart';

/// JSON 读取工具。
///
/// 服务端字段可能为 `null`、数字或字符串，
/// 统一在此收敛，避免 DTO 解析处散落类型判断。
abstract final class JsonReader {
  /// 字符串。
  static String? string(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value.isEmpty ? null : value;
    }
    return '$value';
  }

  /// 整数。
  static int? integer(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  /// 浮点数。
  static double? decimal(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  /// 布尔。
  static bool? boolean(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true' || lower == '1' || lower == 'yes') {
        return true;
      }
      if (lower == 'false' || lower == '0' || lower == 'no') {
        return false;
      }
    }
    return null;
  }

  /// 对象。
  static Map<String, Object?>? object(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry('$key', item));
    }
    return null;
  }

  /// 对象列表。
  static List<Map<String, Object?>> objects(Object? value) {
    if (value is! List) {
      return const <Map<String, Object?>>[];
    }
    final result = <Map<String, Object?>>[];
    for (final item in value) {
      final map = object(item);
      if (map != null) {
        result.add(map);
      }
    }
    return result;
  }

  /// 字符串列表。
  static List<String> strings(Object? value) {
    if (value is String) {
      return value.isEmpty ? const <String>[] : <String>[value];
    }
    if (value is! List) {
      return const <String>[];
    }
    return value
        .map((item) => string(item))
        .whereType<String>()
        .toList(growable: false);
  }

  /// 读取「可能是列表」的字符串字段（服务端部分字段为多值列表）。
  ///
  /// 例如影视 / 人物的 `poster` 在原有公开接口中是多值列表，
  /// 直接 `string()` 会得到 `"[a, b]"` 这样的伪地址，因此统一取首个有效值。
  static String? firstString(Object? value) {
    if (value is List) {
      for (final item in value) {
        final text = string(item);
        if (text != null) {
          return text;
        }
      }
      return null;
    }
    return string(value);
  }

  /// 绝对化 URL：服务端可能返回相对路径。
  static Uri? uri(Object? value, {Uri? base}) {
    final raw = string(value);
    if (raw == null) {
      return null;
    }
    final parsed = Uri.tryParse(raw);
    if (parsed == null) {
      return null;
    }
    if (parsed.hasScheme) {
      return parsed;
    }
    if (base == null) {
      return parsed;
    }
    return base.resolveUri(parsed);
  }

  /// 解析图片资源地址。
  ///
  /// 与 [uri] 的差异：服务端以「仓库相对路径」（如 `data\images\a.jpg`）保存图片时，
  /// 需要改写为公开图片接口而不是简单拼接到服务端根地址（文档 #46）。
  static Uri? resource(Object? value, {Uri? base}) =>
      ResourceUri.resolve(value, base: base);
}

/// 服务端信息的响应体。
final class ServerInfoDto {
  /// 创建 DTO。
  const ServerInfoDto({
    this.serverId,
    this.name,
    this.serverVersion,
    this.apiVersion,
    this.https,
    this.capabilities = const <String, bool>{},
  });

  /// 服务端标识。
  final String? serverId;

  /// 名称。
  final String? name;

  /// 服务端版本。
  final String? serverVersion;

  /// API 版本。
  final String? apiVersion;

  /// 是否 HTTPS。
  final bool? https;

  /// 能力。
  final Map<String, bool> capabilities;

  /// 解析。
  static ServerInfoDto fromJson(Object? json) {
    final map = JsonReader.object(json) ?? const <String, Object?>{};
    return ServerInfoDto(
      serverId: JsonReader.string(map['server_id'] ?? map['id']),
      name: JsonReader.string(map['name']),
      serverVersion: JsonReader.string(
        map['server_version'] ?? map['version_name'] ?? map['version'],
      ),
      apiVersion: JsonReader.string(map['api_version'] ?? map['apiVersion']),
      https: JsonReader.boolean(map['https']),
      capabilities: _capabilities(map['capabilities']),
    );
  }

  static Map<String, bool> _capabilities(Object? value) {
    final map = JsonReader.object(value);
    if (map == null) {
      return const <String, bool>{};
    }
    final result = <String, bool>{};
    map.forEach((key, item) {
      final flag = JsonReader.boolean(item);
      if (flag != null) {
        result[key] = flag;
      }
    });
    return result;
  }
}

/// 令牌响应体。
final class TokenDto {
  /// 创建 DTO。
  const TokenDto({
    required this.accessToken,
    this.refreshToken,
    this.expiresInSeconds,
    this.refreshExpiresInSeconds,
    this.expiresAt,
  });

  /// 访问令牌。
  final String accessToken;

  /// 刷新令牌。
  final String? refreshToken;

  /// 访问令牌有效期（秒）。
  final int? expiresInSeconds;

  /// 刷新令牌有效期（秒）。
  final int? refreshExpiresInSeconds;

  /// 绝对过期时间（服务端直接下发时使用）。
  final DateTime? expiresAt;

  /// 解析。
  static TokenDto fromJson(Object? json) {
    final map = JsonReader.object(json) ?? const <String, Object?>{};
    final accessToken =
        JsonReader.string(
          map['access_token'] ?? map['accessToken'] ?? map['token'],
        ) ??
        '';
    if (accessToken.isEmpty) {
      throw const DtoFormatException('Missing access token in response');
    }
    final expiresAtRaw = JsonReader.string(
      map['expires_at'] ?? map['expiresAt'],
    );
    return TokenDto(
      accessToken: accessToken,
      refreshToken: JsonReader.string(
        map['refresh_token'] ?? map['refreshToken'],
      ),
      expiresInSeconds: JsonReader.integer(
        map['expires_in'] ?? map['expiresIn'],
      ),
      refreshExpiresInSeconds: JsonReader.integer(
        map['refresh_expires_in'] ?? map['refreshExpiresIn'],
      ),
      expiresAt: expiresAtRaw == null ? null : DateTime.tryParse(expiresAtRaw),
    );
  }

  /// 转换为领域令牌模型。
  AuthTokens toEntity({DateTime? now}) {
    final reference = now ?? DateTime.now();
    final expiresIn = expiresInSeconds;
    final refreshExpiresIn = refreshExpiresInSeconds;
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt:
          expiresAt ??
          (expiresIn == null
              ? null
              : reference.add(Duration(seconds: expiresIn))),
      refreshExpiresAt: refreshExpiresIn == null
          ? null
          : reference.add(Duration(seconds: refreshExpiresIn)),
    );
  }
}

/// 用户响应体。
///
/// 同时兼容 AMMDS Client API 与既有服务端的用户信息结构：
/// 服务端 `UserInfoResp` 使用 `userId` / `nickname` / `avatar` / `role` 等字段。
final class UserDto {
  /// 创建 DTO。
  const UserDto({
    required this.id,
    required this.username,
    this.nickname,
    this.avatar,
    this.permissions = const <String>[],
    this.role,
    this.email,
    this.phone,
    this.registeredAt,
    this.lastLoginAt,
    this.enabled,
  });

  /// 用户 ID。
  final String id;

  /// 登录名。
  final String username;

  /// 昵称。
  final String? nickname;

  /// 头像。
  final String? avatar;

  /// 权限。
  final List<String> permissions;

  /// 角色。
  final String? role;

  /// 邮箱。
  final String? email;

  /// 手机号。
  final String? phone;

  /// 注册时间。
  final DateTime? registeredAt;

  /// 最近登录时间。
  final DateTime? lastLoginAt;

  /// 是否启用。
  final bool? enabled;

  /// 解析。
  static UserDto fromJson(Object? json) {
    final map = JsonReader.object(json) ?? const <String, Object?>{};
    final id =
        JsonReader.string(map['id'] ?? map['user_id'] ?? map['userId']) ?? '';
    final username =
        JsonReader.string(
          map['username'] ?? map['name'] ?? map['login'] ?? map['userName'],
        ) ??
        '';
    if (id.isEmpty && username.isEmpty) {
      throw const DtoFormatException('Missing user identity in response');
    }
    final role = JsonReader.string(map['role']);
    final permissions = JsonReader.strings(
      map['permissions'] ?? map['authorities'],
    );
    return UserDto(
      id: id.isEmpty ? username : id,
      username: username.isEmpty ? id : username,
      nickname: JsonReader.string(map['nickname']),
      avatar: JsonReader.string(map['avatar'] ?? map['avatar_url']),
      permissions: permissions.isEmpty && role != null
          ? <String>[role]
          : permissions,
      role: role,
      email: JsonReader.string(map['email']),
      phone: JsonReader.string(map['phone']),
      registeredAt: _date(map['register_time'] ?? map['registerTime']),
      lastLoginAt: _date(map['last_login_time'] ?? map['lastLoginTime']),
      enabled: JsonReader.boolean(map['status'] ?? map['enabled']),
    );
  }

  /// 解析服务端 `yyyy-MM-dd HH:mm:ss` 形式的时间。
  static DateTime? _date(Object? value) {
    final raw = JsonReader.string(value);
    if (raw == null) {
      return null;
    }
    return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  }

  /// 转换为领域模型。
  UserProfile toEntity({Uri? base}) => UserProfile(
    id: id,
    username: username,
    nickname: nickname,
    avatarUrl: JsonReader.resource(avatar, base: base),
    permissions: permissions,
    role: role,
    email: email,
    phone: phone,
    registeredAt: registeredAt,
    lastLoginAt: lastLoginAt,
    enabled: enabled ?? true,
  );
}

/// 登录响应体。
final class LoginResponseDto {
  /// 创建 DTO。
  const LoginResponseDto({required this.token, this.user});

  /// 令牌。
  final TokenDto token;

  /// 用户（部分服务端在登录时不返回）。
  final UserDto? user;

  /// 解析：兼容 `{ token: {...} }` 与 `{ access_token: ... }` 两种形态。
  static LoginResponseDto fromJson(Object? json) {
    final map = JsonReader.object(json) ?? const <String, Object?>{};
    final nestedToken = JsonReader.object(map['token']);
    final token = nestedToken != null
        ? TokenDto.fromJson(nestedToken)
        : TokenDto.fromJson(map);
    final user = JsonReader.object(map['user'] ?? map['profile']);
    return LoginResponseDto(
      token: token,
      user: user == null ? null : UserDto.fromJson(user),
    );
  }

  /// 转换为领域模型。
  AuthResult toEntity({Uri? base, DateTime? now}) {
    final parsedUser = user;
    return AuthResult(
      tokens: token.toEntity(now: now),
      user: parsedUser == null
          ? const UserProfile(id: '', username: '')
          : parsedUser.toEntity(base: base),
    );
  }
}

/// 内容条目响应体。
final class ContentItemDto {
  /// 创建 DTO。
  const ContentItemDto({
    required this.id,
    required this.title,
    this.subtitle,
    this.cover,
    this.year,
    this.rating,
    this.categories = const <String>[],
    this.raw = const <String, Object?>{},
  });

  /// 标识。
  final String id;

  /// 标题。
  final String title;

  /// 副标题。
  final String? subtitle;

  /// 封面。
  final String? cover;

  /// 年份。
  final int? year;

  /// 评分。
  final double? rating;

  /// 分类。
  final List<String> categories;

  /// 原始字段。
  final Map<String, Object?> raw;

  /// 解析。
  static ContentItemDto fromJson(Object? json) {
    final map = JsonReader.object(json) ?? const <String, Object?>{};
    final id = JsonReader.string(map['id'] ?? map['uuid'] ?? map['key']) ?? '';
    final title =
        JsonReader.string(
          map['title'] ??
              map['title_cn'] ??
              map['titleCn'] ??
              map['name'] ??
              map['original_title'] ??
              map['originalTitle'] ??
              map['nickname'],
        ) ??
        '';
    return ContentItemDto(
      id: id,
      title: title.isEmpty ? id : title,
      subtitle: JsonReader.string(
        map['subtitle'] ??
            map['author'] ??
            map['original_name'] ??
            map['originalTitle'] ??
            map['region'] ??
            map['status'],
      ),
      cover: JsonReader.firstString(
        map['cover'] ??
            map['poster_hd'] ??
            map['posterHd'] ??
            map['poster'] ??
            map['avatar'] ??
            map['image'],
      ),
      year: JsonReader.integer(
        map['year'] ?? map['release_year'] ?? map['releaseYear'],
      ),
      rating: JsonReader.decimal(map['rating'] ?? map['score']),
      categories: JsonReader.strings(
        map['categories'] ?? map['genres'] ?? map['types'] ?? map['tags'],
      ),
      raw: map,
    );
  }

  /// 转换为领域模型。
  ContentItem toEntity({Uri? base}) => ContentItem(
    id: id,
    title: title,
    subtitle: subtitle,
    coverUri: JsonReader.resource(cover, base: base),
    // 远端封面在服务端取不到图时（图床被服务端所在网络屏蔽）直连原地址兜底
    coverFallbackUri: ResourceUri.direct(cover, base: base),
    year: year,
    rating: rating,
    categories: categories,
    extra: raw,
  );
}

/// 开屏配置响应体。
///
/// 对应服务端 `GET /api/client/v1/splash`。服务端未提供该接口或返回「官方开屏」时，
/// 客户端使用 [SplashConfigDto.official] 并改用本地品牌资源渲染。
final class SplashConfigDto {
  /// 创建 DTO。
  const SplashConfigDto({
    this.enabled = false,
    this.type = 'official',
    this.officialStyle = '3d',
    this.imageUrl,
    this.targetUrl,
    this.title,
    this.durationMs,
    this.skipAfterMs,
    this.productName,
    this.copyright,
  });

  /// 官方开屏（无服务端内容）。
  static const SplashConfigDto official = SplashConfigDto();

  /// 是否下发了非默认开屏内容。
  final bool enabled;

  /// `official` / `ad`。
  final String type;

  /// `3d` / `static`。
  final String officialStyle;

  /// 广告图片地址。
  final String? imageUrl;

  /// 广告跳转地址。
  final String? targetUrl;

  /// 广告文案。
  final String? title;

  /// 开屏总时长（毫秒）。
  final int? durationMs;

  /// 允许跳过的延迟（毫秒）。
  final int? skipAfterMs;

  /// 底部主标题。
  final String? productName;

  /// 底部版权文案。
  final String? copyright;

  /// 解析。
  static SplashConfigDto fromJson(Object? json) {
    final map = JsonReader.object(json);
    if (map == null) {
      return official;
    }
    return SplashConfigDto(
      enabled: JsonReader.boolean(map['enabled']) ?? false,
      type: JsonReader.string(map['type']) ?? 'official',
      officialStyle: JsonReader.string(map['official_style']) ?? '3d',
      imageUrl: JsonReader.string(map['image_url']),
      targetUrl: JsonReader.string(map['target_url']),
      title: JsonReader.string(map['title']),
      durationMs: JsonReader.integer(map['duration_ms']),
      skipAfterMs: JsonReader.integer(map['skip_after_ms']),
      productName: JsonReader.string(map['product_name']),
      copyright: JsonReader.string(map['copyright']),
    );
  }

  /// 转换为领域模型。
  ///
  /// [fallbackProductName] / [fallbackCopyright] 为本地化兜底文案：
  /// 服务端未下发对应字段时使用它们，保证底部区域始终有内容。
  SplashConfig toEntity({
    required String fallbackProductName,
    required String fallbackCopyright,
    Uri? base,
  }) {
    final isAd = enabled && type.toLowerCase() == 'ad' && imageUrl != null;
    return SplashConfig(
      kind: isAd ? SplashKind.ad : SplashKind.official,
      officialStyle: SplashOfficialStyle.parse(officialStyle),
      productName: productName == null || productName!.isEmpty
          ? fallbackProductName
          : productName!,
      copyright: copyright == null || copyright!.isEmpty
          ? fallbackCopyright
          : copyright!,
      imageUrl: JsonReader.resource(imageUrl, base: base),
      targetUrl: JsonReader.uri(targetUrl, base: base),
      title: title,
      durationMs: durationMs ?? 3000,
      skipAfterMs: skipAfterMs ?? 0,
    );
  }
}

/// 分页响应体。
final class PageDto<T> {
  /// 创建 DTO。
  const PageDto({
    required this.items,
    required this.hasMore,
    this.nextCursor,
    this.page,
    this.total,
  });

  /// 数据项。
  final List<T> items;

  /// 是否还有更多。
  final bool hasMore;

  /// 下一页游标。
  final String? nextCursor;

  /// 当前页。
  final int? page;

  /// 总数。
  final int? total;

  /// 解析分页响应。
  ///
  /// 兼容：
  /// * `{ items: [...], has_more: true, next_cursor: "2" }`（Client API）
  /// * `{ current: 1, size: 20, page: 3, total: 45, data: [...] }`
  ///   （服务端 `PageTemplate`：`current` 为当前页，`page` 为**总页数**）
  /// * `{ list: [...], page: 1, page_size: 20, total: 45 }`
  /// * 直接返回数组
  static PageDto<T> fromJson<T>(Object? json, T Function(Object? item) decode) {
    if (json is List) {
      final items = json.map(decode).toList(growable: false);
      return PageDto<T>(items: items, hasMore: false);
    }
    final map = JsonReader.object(json) ?? const <String, Object?>{};
    final rawItems =
        map['items'] ??
        map['list'] ??
        map['records'] ??
        map['data'] ??
        map['rows'] ??
        const <Object?>[];
    final items = rawItems is List
        ? rawItems.map(decode).toList(growable: false)
        : <T>[];

    final current = JsonReader.integer(map['current'] ?? map['pageNum']);
    final totalPages = JsonReader.integer(map['page']);
    final pageSize = JsonReader.integer(
      map['page_size'] ?? map['size'] ?? map['pageSize'],
    );
    final total = JsonReader.integer(map['total'] ?? map['total_count']);
    final explicitHasMore = JsonReader.boolean(
      map['has_more'] ?? map['hasMore'] ?? map['has_next'],
    );

    final bool derivedHasMore;
    if (current != null && totalPages != null) {
      // 服务端 PageTemplate：current 为当前页，page 为总页数
      derivedHasMore = current < totalPages;
    } else if (totalPages != null && pageSize != null && total != null) {
      derivedHasMore = totalPages * pageSize < total;
    } else if (current != null && pageSize != null && total != null) {
      derivedHasMore = current * pageSize < total;
    } else {
      derivedHasMore = false;
    }

    final page = current ?? totalPages;
    return PageDto<T>(
      items: items,
      hasMore: explicitHasMore ?? derivedHasMore,
      nextCursor:
          JsonReader.string(map['next_cursor'] ?? map['nextCursor']) ??
          (page == null ? null : '${page + 1}'),
      page: page,
      total: total,
    );
  }

  /// 转换为领域分页模型。
  PageResult<R> toEntity<R>(R Function(T item) transform) => PageResult<R>(
    items: items.map(transform).toList(growable: false),
    hasMore: hasMore,
    nextCursor: nextCursor,
    page: page,
    total: total,
  );
}

/// 章节响应体。
final class ChapterDto {
  /// 创建 DTO。
  const ChapterDto({required this.id, required this.title, this.index});

  /// 标识。
  final String id;

  /// 标题。
  final String title;

  /// 序号。
  final int? index;

  /// 解析。
  static ChapterDto fromJson(Object? json) {
    final map = JsonReader.object(json) ?? const <String, Object?>{};
    final id = JsonReader.string(map['id'] ?? map['chapter_id']) ?? '';
    final title =
        JsonReader.string(map['title'] ?? map['name'] ?? map['chapter_name']) ??
        id;
    return ChapterDto(
      id: id,
      title: title,
      index: JsonReader.integer(map['index'] ?? map['order'] ?? map['no']),
    );
  }

  /// 转换为领域模型。
  ContentChapter toEntity() =>
      ContentChapter(id: id, title: title, index: index);
}

/// 内容详情响应体。
final class ContentDetailDto {
  /// 创建 DTO。
  const ContentDetailDto({
    required this.item,
    this.overview,
    this.episodeCount,
    this.status,
    this.author,
    this.chapters = const <ChapterDto>[],
    this.related = const <ContentItemDto>[],
    this.attributes = const <String, String>{},
    this.gallery = const <String>[],
    this.files = const <MediaFileDto>[],
  });

  /// 基础条目。
  final ContentItemDto item;

  /// 简介。
  final String? overview;

  /// 集数。
  final int? episodeCount;

  /// 状态。
  final String? status;

  /// 作者。
  final String? author;

  /// 章节。
  final List<ChapterDto> chapters;

  /// 关联内容。
  final List<ContentItemDto> related;

  /// 扩展属性（服务端下发的键值表）。
  final Map<String, String> attributes;

  /// 图集（图片地址原始值）。
  final List<String> gallery;

  /// 可播放文件（影视）。
  final List<MediaFileDto> files;

  /// 解析。
  ///
  /// 兼容三种形态：
  /// * Client API：字段平铺在 `data` 根上；
  /// * `{ "detail": { ... } }` 嵌套；
  /// * 既有公开接口的小说详情：`{ "book": { ... }, "chapters": [ ... ] }`
  ///   （书籍字段在 `book` 内，章节列表在根上）。
  static ContentDetailDto fromJson(Object? json) {
    final map = JsonReader.object(json) ?? const <String, Object?>{};
    final nested =
        JsonReader.object(map['detail']) ??
        JsonReader.object(map['book']) ??
        JsonReader.object(map['album']);
    final detailSource = nested == null
        ? map
        : <String, Object?>{...nested, ...map};
    return ContentDetailDto(
      item: ContentItemDto.fromJson(detailSource),
      overview: JsonReader.string(
        detailSource['overview'] ??
            detailSource['summary'] ??
            detailSource['description'] ??
            detailSource['intro'] ??
            detailSource['plot_cn'] ??
            detailSource['plotCn'] ??
            detailSource['plot'] ??
            detailSource['outline'] ??
            detailSource['bio'],
      ),
      episodeCount: JsonReader.integer(
        detailSource['episode_count'] ??
            detailSource['episodeCount'] ??
            detailSource['episodes'] ??
            detailSource['chapter_count'] ??
            detailSource['chapterCount'],
      ),
      status: JsonReader.string(detailSource['status']),
      author: JsonReader.firstString(
        detailSource['author'] ??
            detailSource['writer'] ??
            detailSource['director'],
      ),
      chapters: JsonReader.objects(detailSource['chapters'])
          .map(ChapterDto.fromJson)
          .toList(growable: false),
      related: JsonReader.objects(
        detailSource['related'] ?? detailSource['relations'],
      ).map(ContentItemDto.fromJson).toList(growable: false),
      attributes: _attributes(detailSource['attributes']),
      gallery: JsonReader.strings(detailSource['gallery']),
      files: JsonReader.objects(detailSource['files'])
          .map(MediaFileDto.fromJson)
          .whereType<MediaFileDto>()
          .toList(growable: false),
    );
  }

  /// 扩展属性只保留可展示的标量值。
  static Map<String, String> _attributes(Object? value) {
    final map = JsonReader.object(value);
    if (map == null || map.isEmpty) {
      return const <String, String>{};
    }
    final result = <String, String>{};
    map.forEach((key, item) {
      if (item == null || item is Map || item is List) {
        return;
      }
      final text = JsonReader.string(item);
      if (text != null) {
        result[key] = text;
      }
    });
    return result;
  }

  /// 转换为领域模型。
  ContentDetail toEntity({Uri? base}) => ContentDetail(
    item: item.toEntity(base: base),
    overview: overview,
    episodeCount: episodeCount,
    status: status,
    author: author,
    chapters: chapters
        .map((chapter) => chapter.toEntity())
        .toList(growable: false),
    related: related
        .map((item) => item.toEntity(base: base))
        .toList(growable: false),
    attributes: attributes,
    gallery: JsonReader.strings(gallery)
        .map((value) => JsonReader.resource(value, base: base))
        .whereType<Uri>()
        .toList(growable: false),
    files: files.map((file) => file.toEntity()).toList(growable: false),
  );
}

/// 影视可播放文件（`GET /api/client/v1/media/{id}` 的 `files` 字段）。
///
/// 服务端不下发服务器绝对路径，只给出 `file_id` 等元信息；
/// 播放地址由播放决策接口按 `file_id` 返回。
final class MediaFileDto {
  /// 创建 DTO。
  const MediaFileDto({
    required this.id,
    required this.name,
    this.size,
    this.resolution,
    this.episodeIndex,
    this.partIndex,
    this.partTitle,
    this.available = true,
    this.source,
  });

  /// 文件标识。
  final String id;

  /// 文件名。
  final String name;

  /// 文件大小（字节）。
  final int? size;

  /// 分辨率。
  final String? resolution;

  /// 分集 / 片段序号。
  final int? episodeIndex;

  /// 同一分集内的片段序号。
  final int? partIndex;

  /// 分集标题。
  final String? partTitle;

  /// 是否可用。
  final bool available;

  /// 绑定来源。
  final String? source;

  /// 解析；缺少 `file_id` 的条目视为无效。
  static MediaFileDto? fromJson(Object? json) {
    final map = JsonReader.object(json);
    if (map == null) {
      return null;
    }
    final id = JsonReader.string(map['file_id'] ?? map['fileId'] ?? map['id']);
    if (id == null || id.isEmpty) {
      return null;
    }
    return MediaFileDto(
      id: id,
      name: JsonReader.string(map['file_name'] ?? map['fileName']) ?? '',
      size: JsonReader.integer(map['size']),
      resolution: JsonReader.string(map['resolution']),
      episodeIndex: JsonReader.integer(
        map['episode_index'] ?? map['episodeIndex'],
      ),
      partIndex: JsonReader.integer(map['part_index'] ?? map['partIndex']),
      partTitle: JsonReader.string(map['part_title'] ?? map['partTitle']),
      available: JsonReader.boolean(map['available']) ?? true,
      source: JsonReader.string(map['source']),
    );
  }

  /// 转换为领域模型。
  MediaFile toEntity() => MediaFile(
    id: id,
    name: name,
    size: size,
    resolution: resolution,
    episodeIndex: episodeIndex,
    partIndex: partIndex,
    partTitle: partTitle,
    available: available,
    source: source,
  );
}

/// 播放决策响应（`POST /api/client/v1/media/files/{fileId}/playback`）。
final class PlaybackDecisionDto {
  /// 创建 DTO。
  const PlaybackDecisionDto({
    required this.mode,
    this.url,
    this.mimeType,
    this.reason,
    this.targetBitrate,
  });

  /// 播放方式编码。
  final String mode;

  /// 播放地址（相对服务端根路径）。
  final String? url;

  /// 内容类型。
  final String? mimeType;

  /// 说明 / 不可播放原因。
  final String? reason;

  /// 建议码率。
  final int? targetBitrate;

  /// 解析。
  static PlaybackDecisionDto fromJson(Object? json) {
    final map = JsonReader.object(json) ?? const <String, Object?>{};
    return PlaybackDecisionDto(
      mode: JsonReader.string(map['mode']) ?? 'unsupported',
      url: JsonReader.string(map['url']),
      mimeType: JsonReader.string(map['mime_type'] ?? map['mimeType']),
      reason: JsonReader.string(map['reason']),
      targetBitrate: JsonReader.integer(
        map['target_bitrate'] ?? map['targetBitrate'],
      ),
    );
  }

  /// 转换为领域模型。
  PlaybackDecision toEntity() => PlaybackDecision(
    mode: PlaybackMode.parse(mode),
    url: url,
    mimeType: mimeType,
    reason: reason,
    targetBitrate: targetBitrate,
  );

  /// 「不支持」的降级决策（用于方言不支持、能力不足等场景）。
  static PlaybackDecisionDto unsupported([String? reason]) =>
      PlaybackDecisionDto(mode: 'unsupported', reason: reason);
}

/// 小说章节正文响应体（文档 #39 小说阅读器）。
///
/// 兼容两种服务端形态：
/// * Client API：`{ id, book_id, title, index, content, text, word_count, prev_id, next_id }`
/// * 既有公开接口：`{ id, bookId, title, sort, wordCount, content }`（正文为 HTML）
final class ChapterContentDto {
  /// 创建 DTO。
  const ChapterContentDto({
    required this.id,
    required this.title,
    this.bookId,
    this.index,
    this.content,
    this.text,
    this.wordCount,
    this.hasContent = false,
    this.fromSource = false,
    this.prevId,
    this.nextId,
  });

  /// 章节标识。
  final String id;

  /// 章节标题。
  final String title;

  /// 所属书籍标识。
  final String? bookId;

  /// 章节序号。
  final int? index;

  /// 原始正文（可能包含 HTML）。
  final String? content;

  /// 纯文本正文（服务端未提供时为 null，由客户端转换）。
  final String? text;

  /// 字数。
  final int? wordCount;

  /// 是否存在可阅读正文。
  final bool hasContent;

  /// 是否为书源章节。
  final bool fromSource;

  /// 上一章标识。
  final String? prevId;

  /// 下一章标识。
  final String? nextId;

  /// 解析。
  static ChapterContentDto fromJson(Object? json) {
    final map = JsonReader.object(json) ?? const <String, Object?>{};
    final id = JsonReader.string(
      map['id'] ?? map['chapter_id'] ?? map['chapterId'],
    );
    if (id == null) {
      throw const DtoFormatException('Missing chapter id in response');
    }
    return ChapterContentDto(
      id: id,
      title: JsonReader.string(map['title'] ?? map['chapter_title']) ?? id,
      bookId: JsonReader.string(map['book_id'] ?? map['bookId']),
      index: JsonReader.integer(
        map['index'] ?? map['sort'] ?? map['order'] ?? map['no'],
      ),
      content: JsonReader.string(map['content']),
      text: JsonReader.string(map['text']),
      wordCount: JsonReader.integer(
        map['word_count'] ?? map['wordCount'],
      ),
      hasContent:
          JsonReader.boolean(map['has_content'] ?? map['hasContent']) ??
          (JsonReader.string(map['content'] ?? map['text']) != null),
      fromSource:
          JsonReader.boolean(map['from_source'] ?? map['fromSource']) ?? false,
      prevId: JsonReader.string(map['prev_id'] ?? map['prevId']),
      nextId: JsonReader.string(map['next_id'] ?? map['nextId']),
    );
  }

  /// 转换为领域模型。
  ///
  /// 服务端未下发纯文本时，由客户端从 HTML 正文转换，保证旧版服务端同样可读。
  ChapterContent toEntity() {
    final plain =
        text ?? NovelTextParser.htmlToPlainText(content ?? text);
    return ChapterContent(
      id: id,
      title: title,
      bookId: bookId,
      index: index,
      text: plain,
      content: content,
      wordCount: wordCount ?? NovelTextParser.countWords(plain),
      hasContent: plain != null && plain.isNotEmpty,
      fromSource: fromSource,
      prevId: prevId,
      nextId: nextId,
    );
  }
}

/// 漫画章节图片响应体（文档 #40 漫画阅读器）。
///
/// 兼容两种服务端形态：
/// * Client API：`{ chapter_id, chapter_title, album_id, index, page_count, pages: [{sequence, image}] }`
/// * 既有公开接口：`{ chapterId, chapterTitle, pages: [{sequence, imagePath}] }`
final class ComicChapterPagesDto {
  /// 创建 DTO。
  const ComicChapterPagesDto({
    required this.chapterId,
    required this.title,
    this.albumId,
    this.index,
    this.pages = const <ComicPageDto>[],
    this.prevId,
    this.nextId,
  });

  /// 章节标识。
  final String chapterId;

  /// 章节标题。
  final String title;

  /// 所属相册标识。
  final String? albumId;

  /// 章节序号。
  final int? index;

  /// 图片页。
  final List<ComicPageDto> pages;

  /// 上一章标识。
  final String? prevId;

  /// 下一章标识。
  final String? nextId;

  /// 解析。
  static ComicChapterPagesDto fromJson(Object? json) {
    final map = JsonReader.object(json) ?? const <String, Object?>{};
    return ComicChapterPagesDto(
      chapterId:
          JsonReader.string(
            map['chapter_id'] ?? map['chapterId'] ?? map['id'],
          ) ??
          '',
      title:
          JsonReader.string(map['chapter_title'] ?? map['chapterTitle']) ?? '',
      albumId: JsonReader.string(map['album_id'] ?? map['albumId']),
      index: JsonReader.integer(map['index']),
      pages: JsonReader.objects(map['pages']).map(ComicPageDto.fromJson).toList(
        growable: false,
      ),
      prevId: JsonReader.string(map['prev_id'] ?? map['prevId']),
      nextId: JsonReader.string(map['next_id'] ?? map['nextId']),
    );
  }

  /// 转换为领域模型（图片地址在此解析为可访问地址）。
  ComicChapterPages toEntity({Uri? base}) {
    final resolved = <ComicImage>[];
    for (final page in pages) {
      final uri = JsonReader.resource(page.image, base: base);
      if (uri == null) {
        continue;
      }
      resolved.add(
        ComicImage(
          sequence: page.sequence ?? resolved.length + 1,
          imageUri: uri,
        ),
      );
    }
    return ComicChapterPages(
      chapterId: chapterId,
      title: title,
      albumId: albumId,
      index: index,
      pages: resolved,
      prevId: prevId,
      nextId: nextId,
    );
  }
}

/// 漫画图片页响应体。
final class ComicPageDto {
  /// 创建 DTO。
  const ComicPageDto({this.sequence, this.image});

  /// 页序号。
  final int? sequence;

  /// 图片地址原始值。
  final String? image;

  /// 解析。
  static ComicPageDto fromJson(Object? json) {
    final map = JsonReader.object(json) ?? const <String, Object?>{};
    return ComicPageDto(
      sequence: JsonReader.integer(map['sequence'] ?? map['index']),
      image: JsonReader.string(map['image'] ?? map['imagePath'] ?? map['path']),
    );
  }
}

/// 服务端阅读进度响应体（文档 #39 / #40 跨设备续读）。
///
/// 兼容两种服务端形态：
/// * Client API：`{ kind, content_id, chapter_id, chapter_title, chapter_index, percent, page_no, updated_at }`
/// * 既有公开接口：直接返回进度实体（camelCase：`chapterId` / `percent` / `pageNo` / `updatedTime`）
///
/// 服务端把「章内位置」按内容类型分开存储：小说是 0~1 的比例，
/// 漫画是页码；客户端模型统一用 [ReadingProgress.page]（小说为 0~100 百分数、
/// 漫画为页码），换算集中在本 DTO，避免散落到阅读器里。
final class ReadingProgressDto {
  /// 创建 DTO。
  const ReadingProgressDto({
    this.chapterId,
    this.chapterTitle,
    this.chapterIndex,
    this.percent,
    this.pageNo,
    this.updatedAt,
  });

  /// 章节 ID。
  final String? chapterId;

  /// 章节标题。
  final String? chapterTitle;

  /// 章节序号（从 1 开始）。
  final int? chapterIndex;

  /// 小说章内进度（0~1）。
  final double? percent;

  /// 漫画页码（从 1 开始）。
  final int? pageNo;

  /// 服务端记录的最后更新时间（用于「本地 vs 服务端」合并判定）。
  final DateTime? updatedAt;

  /// 解析；无有效章节位置时返回 null。
  static ReadingProgressDto? fromJson(Object? json) {
    final map = JsonReader.object(json);
    if (map == null) {
      return null;
    }
    final chapterId = JsonReader.string(
      map['chapter_id'] ?? map['chapterId'],
    );
    if (chapterId == null) {
      return null;
    }
    return ReadingProgressDto(
      chapterId: chapterId,
      chapterTitle: JsonReader.string(
        map['chapter_title'] ?? map['chapterTitle'],
      ),
      chapterIndex: JsonReader.integer(
        map['chapter_index'] ?? map['chapterIndex'],
      ),
      percent: JsonReader.decimal(map['percent']),
      pageNo: JsonReader.integer(map['page_no'] ?? map['pageNo']),
      updatedAt: _time(map['updated_at'] ?? map['updatedAt'] ?? map['updatedTime']),
    );
  }

  /// 服务端时间可能是毫秒时间戳，也可能是 `yyyy-MM-dd HH:mm:ss` 文本。
  static DateTime? _time(Object? value) {
    final millis = JsonReader.integer(value);
    if (millis != null) {
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    final raw = JsonReader.string(value);
    return raw == null ? null : DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  }

  /// 转换为领域模型。
  ReadingProgress toEntity(ContentKind kind, String id, {String? title}) =>
      ReadingProgress(
        kind: kind,
        id: id,
        title: title ?? id,
        chapterId: chapterId,
        chapterTitle: chapterTitle,
        chapterIndex: chapterIndex,
        page: _pageOf(kind),
        updatedAt: updatedAt,
      );

  int _pageOf(ContentKind kind) {
    if (kind == ContentKind.novel) {
      return ((percent ?? 0) * 100).clamp(0, 100).round();
    }
    return pageNo ?? 1;
  }

  /// 构造 Client API 的保存请求体（snake_case，内容 ID 由路径携带）。
  static Map<String, Object?> clientRequestBody(ReadingProgress progress) {
    if (progress.kind == ContentKind.novel) {
      return <String, Object?>{
        'chapter_id': progress.chapterId,
        'chapter_title': progress.chapterTitle,
        'chapter_index': progress.chapterIndex,
        // 客户端用 0~100 百分数，服务端存 0~1 比例
        'percent': progress.page.clamp(0, 100) / 100,
      };
    }
    return <String, Object?>{
      'chapter_id': progress.chapterId,
      'page_no': progress.page,
    };
  }
}

/// DTO 解析失败。
final class DtoFormatException implements Exception {
  /// 创建异常。
  const DtoFormatException(this.message);

  /// 描述。
  final String message;

  @override
  String toString() => 'DtoFormatException: $message';
}
