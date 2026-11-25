import 'package:flutter/foundation.dart';

/// 客户端播放能力探测。
///
/// 播放前把「本机解码能力」上报给服务端，由服务端决定直接播放 / 重封装 /
/// 转码 / 不可播放，避免客户端盲目拉流后黑屏。
///
/// 这里刻意使用**静态能力表**而不是运行时探测：
/// * Flutter 没有统一的「查询系统解码器」API，逐平台探测成本高且不可靠；
/// * 平台默认播放器的能力在相当长时间内是稳定的，静态表足以给出安全的决策输入
///   （宁可保守上报，也不要上报实际上不支持的编码）。
///
/// 若某天需要更精确的能力，只需替换 [detect] 的实现，调用方无需改动。
abstract final class PlaybackCapability {
  /// 探测当前平台的可播放能力。
  ///
  /// 返回值为服务端播放决策接口的请求体（下划线字段）。
  static Map<String, Object?> detect() {
    final profile = _profile();
    return <String, Object?>{
      'containers': profile.containers,
      'video_codecs': profile.videoCodecs,
      'audio_codecs': profile.audioCodecs,
      'max_bitrate': profile.maxBitrate,
      'hls': profile.hls,
    };
  }

  static _Profile _profile() {
    if (kIsWeb) {
      // 浏览器 <video>：主流浏览器对 MP4/H.264 与 WebM 支持最好；
      // 不声明 HLS（Web 端需额外引入 hls.js 才能播 m3u8）。
      return const _Profile(
        containers: <String>['mp4', 'm4v', 'mov', 'webm'],
        videoCodecs: <String>['h264', 'vp8', 'vp9', 'av1'],
        audioCodecs: <String>['aac', 'mp3', 'opus', 'vorbis'],
        maxBitrate: 20000000,
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        // Windows 走 Media Foundation，容器与编码支持面较宽
        return const _Profile(
          containers: <String>['mp4', 'm4v', 'mov', 'mkv', 'avi', 'wmv', 'webm', 'ts', 'm2ts'],
          videoCodecs: <String>['h264', 'hevc', 'mpeg4', 'vp8', 'vp9', 'av1', 'vc1', 'wmv3'],
          audioCodecs: <String>['aac', 'mp3', 'ac3', 'eac3', 'flac', 'pcm', 'opus', 'vorbis', 'wma'],
          maxBitrate: 60000000,
        );
      case TargetPlatform.macOS:
        return const _Profile(
          containers: <String>['mp4', 'm4v', 'mov', 'webm'],
          videoCodecs: <String>['h264', 'hevc', 'vp9', 'av1'],
          audioCodecs: <String>['aac', 'mp3', 'ac3', 'eac3', 'flac', 'opus', 'vorbis'],
          maxBitrate: 60000000,
        );
      case TargetPlatform.linux:
        return const _Profile(
          containers: <String>['mp4', 'm4v', 'mov', 'mkv', 'webm', 'ts'],
          videoCodecs: <String>['h264', 'hevc', 'vp8', 'vp9', 'av1'],
          audioCodecs: <String>['aac', 'mp3', 'opus', 'vorbis', 'flac'],
          maxBitrate: 40000000,
        );
      default:
        // Android / iOS：系统播放器对 H.264/AAC 的 MP4 兼容性最好，
        // MKV 等容器在部分机型上依赖厂商实现，因此保守不声明。
        return const _Profile(
          containers: <String>['mp4', 'm4v', 'mov', 'webm', 'ts'],
          videoCodecs: <String>['h264', 'hevc', 'vp8', 'vp9', 'av1'],
          audioCodecs: <String>['aac', 'mp3', 'opus', 'vorbis', 'flac', 'ac3', 'eac3'],
          maxBitrate: 30000000,
          hls: true,
        );
    }
  }
}

/// 单个平台的能力描述。
final class _Profile {
  const _Profile({
    required this.containers,
    required this.videoCodecs,
    required this.audioCodecs,
    required this.maxBitrate,
    this.hls = false,
  });

  final List<String> containers;
  final List<String> videoCodecs;
  final List<String> audioCodecs;
  final int maxBitrate;
  final bool hls;
}
