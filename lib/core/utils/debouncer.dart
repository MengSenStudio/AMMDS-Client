/// 简易防抖器（文档 #96：搜索输入必须防抖，避免每个字符都请求一次）。
final class Debouncer {
  Debouncer({this.delay = const Duration(milliseconds: 400)});

  /// 防抖窗口。
  final Duration delay;

  int _generation = 0;

  /// 触发一次防抖动作：在 [delay] 内重复调用只会执行最后一次。
  Future<void> run(Future<void> Function() action) async {
    final current = ++_generation;
    await Future<void>.delayed(delay);
    if (current != _generation) {
      return;
    }
    await action();
  }

  /// 取消待执行的动作。
  void cancel() => _generation++;
}
