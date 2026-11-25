import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../domain/entities/content.dart';
import 'content_list_page.dart';

/// 影视模块页面（文档 #37）。
class MediaPage extends StatelessWidget {
  /// 创建页面。
  const MediaPage({super.key});

  @override
  Widget build(BuildContext context) => ContentListPage(
    kind: ContentKind.media,
    title: context.l10n.mediaTitle,
    searchHint: context.l10n.mediaSearchHint,
    aspectRatio: 2 / 3,
  );
}

/// 影视详情页面。
class MediaDetailPage extends StatelessWidget {
  /// 创建页面。
  const MediaDetailPage({super.key, required this.id});

  /// 影视 ID。
  final String id;

  @override
  Widget build(BuildContext context) => ContentDetailPage(
    kind: ContentKind.media,
    id: id,
    title: context.l10n.mediaDetailTitle,
  );
}
