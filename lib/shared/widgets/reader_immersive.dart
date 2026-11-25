import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 阅读器沉浸式控制（文档 #8）。
///
/// 对齐市面常见阅读器的操作逻辑：
///
/// * 进入阅读器后操作栏只展示一小段时间，随后**自动隐藏**并切换为
///   全屏沉浸（隐藏系统状态栏 / 导航栏），把版面尽量留给内容；
/// * 点击内容区域随时切换操作栏；
/// * 离开阅读器时恢复系统 UI，不能把沉浸态泄漏到其它页面。
///
/// 小说与漫画阅读器共有该行为，差异只在正文渲染方式。
mixin ReaderImmersive<T extends StatefulWidget> on State<T> {
  /// 操作栏自动隐藏延时。
  static const Duration autoHideDelay = Duration(seconds: 4);

  Timer? _autoHideTimer;

  /// 当前是否展示操作栏。
  bool get readerUiVisible;

  /// 更新操作栏可见性（由使用方负责 `setState`）。
  void setReaderUiVisible(bool visible);

  /// 在 `initState` 中调用。
  void initReaderImmersive() {
    _syncSystemUi();
    _scheduleAutoHide();
  }

  /// 在 `dispose` 中调用：恢复系统 UI 并清理计时器。
  void disposeReaderImmersive() {
    _autoHideTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge).ignore();
  }

  /// 点击内容区域：切换操作栏显隐。
  void toggleReaderUi() {
    final visible = !readerUiVisible;
    setReaderUiVisible(visible);
    _syncSystemUi();
    if (visible) {
      _scheduleAutoHide();
    } else {
      _autoHideTimer?.cancel();
    }
  }

  /// 用户与操作栏交互时调用：重置自动隐藏计时。
  void keepReaderUiAlive() {
    if (!readerUiVisible) {
      return;
    }
    _scheduleAutoHide();
  }

  void _scheduleAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(autoHideDelay, () {
      if (!mounted || !readerUiVisible) {
        return;
      }
      setReaderUiVisible(false);
      _syncSystemUi();
    });
  }

  /// 操作栏可见时展示系统 UI，隐藏时进入沉浸式全屏。
  void _syncSystemUi() {
    SystemChrome.setEnabledSystemUIMode(
      readerUiVisible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    ).ignore();
  }
}
