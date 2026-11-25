import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../domain/entities/content.dart';
import '../../../media/presentation/pages/content_list_page.dart';

/// 漫画模块页面（文档 #40）。
class ComicPage extends StatelessWidget {
  /// 创建页面。
  const ComicPage({super.key});

  @override
  Widget build(BuildContext context) => ContentListPage(
    kind: ContentKind.comic,
    title: context.l10n.comicTitle,
    searchHint: context.l10n.comicSearchHint,
    aspectRatio: 3 / 4,
  );
}

/// 漫画详情页面。
class ComicDetailPage extends StatelessWidget {
  /// 创建页面。
  const ComicDetailPage({super.key, required this.id});

  /// 漫画 ID。
  final String id;

  @override
  Widget build(BuildContext context) => ContentDetailPage(
    kind: ContentKind.comic,
    id: id,
    title: context.l10n.comicDetailTitle,
  );
}
