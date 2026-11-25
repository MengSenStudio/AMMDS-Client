import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../domain/entities/content.dart';
import '../../../media/presentation/pages/content_list_page.dart';

/// 人物模块页面（文档 #38）。
class PeoplePage extends StatelessWidget {
  /// 创建页面。
  const PeoplePage({super.key});

  @override
  Widget build(BuildContext context) => ContentListPage(
    kind: ContentKind.people,
    title: context.l10n.peopleTitle,
    searchHint: context.l10n.peopleSearchHint,
    aspectRatio: 1,
  );
}

/// 人物详情页面。
class PeopleDetailPage extends StatelessWidget {
  /// 创建页面。
  const PeopleDetailPage({super.key, required this.id});

  /// 人物 ID。
  final String id;

  @override
  Widget build(BuildContext context) => ContentDetailPage(
    kind: ContentKind.people,
    id: id,
    title: context.l10n.peopleDetailTitle,
  );
}
