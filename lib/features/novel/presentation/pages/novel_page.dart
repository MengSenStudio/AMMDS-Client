import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../domain/entities/content.dart';
import '../../../media/presentation/pages/content_list_page.dart';

/// 小说模块页面（文档 #39）。
class NovelPage extends StatelessWidget {
  /// 创建页面。
  const NovelPage({super.key});

  @override
  Widget build(BuildContext context) => ContentListPage(
    kind: ContentKind.novel,
    title: context.l10n.novelTitle,
    searchHint: context.l10n.novelSearchHint,
    aspectRatio: 3 / 4,
  );
}

/// 小说详情页面。
class NovelDetailPage extends StatelessWidget {
  /// 创建页面。
  const NovelDetailPage({super.key, required this.id});

  /// 小说 ID。
  final String id;

  @override
  Widget build(BuildContext context) => ContentDetailPage(
    kind: ContentKind.novel,
    id: id,
    title: context.l10n.novelDetailTitle,
  );
}
