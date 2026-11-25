import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/content.dart';

/// 详情页扩展属性表（文档 #37 ~ #40）。
///
/// 服务端用「英文键 + 值」下发四类内容各自差异较大的元信息
/// （人物身高 / 血型、影视语言 / 分辨率、小说出版社、漫画卷号等）。
/// 客户端在此把已知键映射为本地化标签并固定展示顺序，
/// 未知键退化为「键名 + 值」原样展示，保证服务端新增字段无需客户端发版。
class ContentAttributes extends StatelessWidget {
  /// 创建属性表。
  const ContentAttributes({
    super.key,
    required this.kind,
    required this.attributes,
  });

  /// 内容类型（决定展示顺序）。
  final ContentKind kind;

  /// 属性键值。
  final Map<String, String> attributes;

  /// 各内容类型的展示顺序。
  static const Map<ContentKind, List<String>> _order =
      <ContentKind, List<String>>{
        ContentKind.media: <String>[
          'original_title',
          'tagline',
          'runtime_minutes',
          'premiered',
          'country',
          'language',
          'mpaa',
          'studio',
          'resolution',
          'video_codec',
          'audio_codec',
          'file_size',
          'cast',
        ],
        ContentKind.people: <String>[
          'gender',
          'birth_date',
          'age',
          'height_cm',
          'weight_kg',
          'nationality',
          'blood_type',
          'cup_size',
          'debut_date',
          'retired',
          'deceased',
          'aliases',
          'style',
          'special_features',
        ],
        ContentKind.novel: <String>[
          'status',
          'genre',
          'author',
          'publisher',
          'publish_year',
          'language',
          'page_count',
          'chapter_count',
          'isbn',
          'series',
          'source_name',
        ],
        ContentKind.comic: <String>[
          'type',
          'series',
          'season',
          'photo_count',
          'publisher',
          'publish_date',
          'language',
          'format',
          'age_rating',
          'community_rating',
          'manga',
          'full_chapter',
          'black_white',
          'writer',
          'penciller',
          'inker',
          'colorist',
          'letterer',
          'cover_artist',
          'editor',
          'translator',
          'characters',
          'teams',
          'locations',
        ],
      };

  /// 标签映射表（键 → 本地化文案）。
  static String label(AppLocalizations l10n, String key) => switch (key) {
    'original_title' => l10n.attrOriginalTitle,
    'tagline' => l10n.attrTagline,
    'runtime_minutes' => l10n.attrRuntime,
    'premiered' => l10n.attrPremiered,
    'country' => l10n.attrCountry,
    'language' => l10n.attrLanguage,
    'mpaa' => l10n.attrMpaa,
    'studio' => l10n.attrStudio,
    'resolution' => l10n.attrResolution,
    'video_codec' => l10n.attrVideoCodec,
    'audio_codec' => l10n.attrAudioCodec,
    'file_size' => l10n.attrFileSize,
    'cast' => l10n.attrCast,
    'gender' => l10n.attrGender,
    'birth_date' => l10n.attrBirthDate,
    'age' => l10n.attrAge,
    'height_cm' => l10n.attrHeight,
    'weight_kg' => l10n.attrWeight,
    'nationality' => l10n.attrNationality,
    'blood_type' => l10n.attrBloodType,
    'cup_size' => l10n.attrCupSize,
    'debut_date' => l10n.attrDebutDate,
    'retired' => l10n.attrRetired,
    'deceased' => l10n.attrDeceased,
    'aliases' => l10n.attrAliases,
    'style' => l10n.attrStyle,
    'special_features' => l10n.attrSpecialFeatures,
    'status' => l10n.attrStatus,
    'genre' => l10n.attrGenre,
    'publisher' => l10n.attrPublisher,
    'publish_year' => l10n.attrPublishYear,
    'page_count' => l10n.attrPageCount,
    'chapter_count' => l10n.attrChapterCount,
    'isbn' => l10n.attrIsbn,
    'series' => l10n.attrSeries,
    'source_name' => l10n.attrSource,
    'type' => l10n.attrType,
    'season' => l10n.attrSeason,
    'photo_count' => l10n.attrPhotoCount,
    'publish_date' => l10n.attrPublishDate,
    'format' => l10n.attrFormat,
    'age_rating' => l10n.attrAgeRating,
    'community_rating' => l10n.attrCommunityRating,
    'manga' => l10n.attrManga,
    'full_chapter' => l10n.attrFullChapter,
    'black_white' => l10n.attrBlackWhite,
    'writer' => l10n.attrWriter,
    'penciller' => l10n.attrPenciller,
    'inker' => l10n.attrInker,
    'colorist' => l10n.attrColorist,
    'letterer' => l10n.attrLetterer,
    'cover_artist' => l10n.attrCoverArtist,
    'editor' => l10n.attrEditor,
    'translator' => l10n.attrTranslator,
    'characters' => l10n.attrCharacters,
    'teams' => l10n.attrTeams,
    'locations' => l10n.attrLocations,
    _ => key,
  };

  /// 值为布尔语义时转换为「是 / 否」。
  static String value(BuildContext context, String raw) => switch (raw) {
    'true' => context.l10n.yes,
    'false' => context.l10n.no,
    _ => raw,
  };

  /// 按「已知顺序 + 其余键」排列后的条目。
  List<MapEntry<String, String>> get _entries {
    final ordered = <MapEntry<String, String>>[];
    final used = <String>{};
    for (final key in _order[kind] ?? const <String>[]) {
      final value = attributes[key];
      if (value != null && value.isNotEmpty) {
        ordered.add(MapEntry(key, value));
        used.add(key);
      }
    }
    attributes.forEach((key, value) {
      if (!used.contains(key) && value.isNotEmpty) {
        ordered.add(MapEntry(key, value));
      }
    });
    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 96,
                  child: Text(
                    label(context.l10n, entry.key),
                    style: AppTypography.caption.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    value(context, entry.value),
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
