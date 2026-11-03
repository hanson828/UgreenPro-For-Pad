import 'dart:async';

import 'package:flutter/services.dart';

/// 指纹硬件状态（来自原生 FingerprintManager）。
class FingerprintAvailability {
  const FingerprintAvailability({
    required this.hardware,
    required this.enrolled,
    required this.deviceSecure,
  });

  const FingerprintAvailability.unknown()
    : hardware = false,
      enrolled = false,
      deviceSecure = false;

  final bool hardware;
  final bool enrolled;
  final bool deviceSecure;

  /// 有传感器且系统里至少录入了一枚指纹。
  bool get usable => hardware && enrolled;

  /// 给用户看的一句话说明。
  String get reason {
    if (!hardware) {
      return '当前设备没有指纹传感器';
    }
    if (!enrolled) {
      return '系统里还没有录入指纹';
    }
    return '使用系统指纹代替输入密码';
  }
}

/// 原生推上来的指纹事件。
class FingerprintEvent {
  const FingerprintEvent({
    required this.state,
    required this.code,
    required this.message,
  });

  final String state; // success / failed / help / error
  final int code;
  final String message;

  bool get isSuccess => state == 'success';
  bool get isMismatch => state == 'failed';
  bool get isHelp => state == 'help';
  bool get isError => state == 'error';

  /// 用户主动取消（原生返回 CANCELED / USER_CANCELED）。
  bool get isCanceled => isError && (code == 5 || code == 10);
}

/// 指纹识别：不走系统 BiometricPrompt，弹窗由 Flutter 自己画。
class FingerprintAuth {
  FingerprintAuth._();

  static final FingerprintAuth instance = FingerprintAuth._();

  static const MethodChannel _channel = MethodChannel('ugreen_shell/fingerprint');
  static const EventChannel _events = EventChannel(
    'ugreen_shell/fingerprint_events',
  );

  Stream<FingerprintEvent>? _eventStream;

  Stream<FingerprintEvent> get events {
    return _eventStream ??= _events.receiveBroadcastStream().map((dynamic raw) {
      final map = (raw as Map).cast<Object?, Object?>();
      return FingerprintEvent(
        state: '${map['state'] ?? ''}',
        code: (map['code'] as int?) ?? 0,
        message: '${map['message'] ?? ''}',
      );
    });
  }

  Future<FingerprintAvailability> status() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('status');
      if (map == null) {
        return const FingerprintAvailability.unknown();
      }
      return FingerprintAvailability(
        hardware: map['hardware'] == true,
        enrolled: map['enrolled'] == true,
        deviceSecure: map['deviceSecure'] == true,
      );
    } catch (_) {
      return const FingerprintAvailability.unknown();
    }
  }

  /// 开始监听指纹（原生侧会覆盖上一次未结束的监听）。
  Future<void> start() async {
    try {
      await _channel.invokeMethod<void>('start');
    } catch (_) {
      // 弹窗那边会等不到事件，按失败处理。
    }
  }

  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (_) {
      // 已经结束了。
    }
  }

  /// 打开系统的指纹录入页面。
  Future<void> openEnrollment() async {
    try {
      await _channel.invokeMethod<void>('openEnroll');
    } catch (_) {
      // 打不开就算了，用户自己去设置里加。
    }
  }
}
