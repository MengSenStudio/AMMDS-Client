import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

/// 安全返回（文档 #10）。
///
/// 页面上的返回按钮必须能应对「直接通过 URL / 深链进入页面，导致没有可弹出的
/// 路由栈」的情况：此时 `context.pop()` 会抛出
/// `GoError: There is nothing to pop`，用户看到的是一条异常而不是返回动作。
///
/// 该函数在可返回时执行返回，否则回退到 [fallback]（通常是上一个逻辑入口），
/// 保证任何入口进入页面后都能正常离开。
void popOrGo(BuildContext context, String fallback) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
    return;
  }
  router.go(fallback);
}

/// 顶部导航栏的返回按钮（配合 `TDNavBar(useDefaultBack: false)` 使用）。
///
/// TDesign 的默认返回按钮在触发 `onBack` 之后**还会再执行一次**
/// `Navigator.maybePop`；而 [popOrGo] 内部已经完成了一次返回，
/// 两者叠加会让一次点击退两层——阅读器因此会跳过详情页直接回到列表。
///
/// 所以这里统一关闭默认返回按钮，改用本方法提供的按钮，
/// 保证「点一次、退一层」，同时保留深链场景下的 [popOrGo] 兜底。
List<TDNavBarItem> appBackBarItems(
  BuildContext context,
  String fallback, {
  Color? iconColor,
}) => <TDNavBarItem>[
  TDNavBarItem(
    icon: TDIcons.chevron_left,
    iconSize: 28,
    iconColor: iconColor,
    action: () => popOrGo(context, fallback),
  ),
];
