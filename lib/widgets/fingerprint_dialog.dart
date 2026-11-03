import 'dart:async';

import 'package:flutter/material.dart';

import '../services/fingerprint_auth.dart';
import '../theme/app_theme.dart';

/// 在页面内（不用 Navigator）显示指纹卡片，通过 [onDone] 回传结果。
/// 应用锁的锁屏是盖在 MaterialApp 之外的，那里没有 Navigator，
/// 所以走这个内嵌卡片；普通页面用 [showFingerprintDialog] 更像"弹窗"。
class FingerprintPrompt extends StatefulWidget {
  const FingerprintPrompt({
    super.key,
    required this.onDone,
    this.onCancel,
    this.hint = '请按压指纹传感器',
  });

  final ValueChanged<bool> onDone;

  /// 用户主动改用密码 / 系统取消，不算验证失败。
  final VoidCallback? onCancel;

  final String hint;

  @override
  State<FingerprintPrompt> createState() => _FingerprintPromptState();
}

class _FingerprintPromptState extends State<FingerprintPrompt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  StreamSubscription<FingerprintEvent>? _sub;
  String _status = '';
  String? _error;
  bool _mismatch = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _sub = FingerprintAuth.instance.events.listen(_onEvent);
    FingerprintAuth.instance.start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulse.dispose();
    FingerprintAuth.instance.cancel();
    super.dispose();
  }

  void _finish(bool ok) {
    if (_finished) {
      return;
    }
    _finished = true;
    FingerprintAuth.instance.cancel();
    widget.onDone(ok);
  }

  void _cancel() {
    if (_finished) {
      return;
    }
    _finished = true;
    FingerprintAuth.instance.cancel();
    final onCancel = widget.onCancel;
    if (onCancel != null) {
      onCancel();
    } else {
      widget.onDone(false);
    }
  }

  void _onEvent(FingerprintEvent event) {
    if (!mounted || _finished) {
      return;
    }
    if (event.isSuccess) {
      _finish(true);
      return;
    }
    if (event.isMismatch) {
      setState(() {
        _mismatch = true;
        _status = '没识别到，请再按一次';
      });
      return;
    }
    if (event.isHelp) {
      setState(() => _status = event.message);
      return;
    }
    if (event.isCanceled) {
      _cancel();
      return;
    }
    setState(() => _error = _describeError(event));
  }

  String _describeError(FingerprintEvent event) {
    switch (event.code) {
      case 1:
        return '指纹硬件暂时不可用';
      case 2:
        return '没能处理这次指纹，请重试';
      case 3:
        return '太久没按压，已超时';
      case 7:
        return '尝试次数过多，请稍后再试或改用密码';
      case 9:
        return '指纹已被系统永久锁定，请先用密码解锁设备';
      default:
        if (event.message.isNotEmpty) {
          return event.message;
        }
        return '指纹识别失败';
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _mismatch = false;
      _status = '';
    });
    FingerprintAuth.instance.start();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = _error != null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  final t = _pulse.value;
                  return SizedBox(
                    width: 124,
                    height: 124,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (!hasError)
                          Container(
                            width: 92 + 28 * t,
                            height: 92 + 28 * t,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.brand.withValues(
                                alpha: 0.10 * (1 - t) + 0.03,
                              ),
                            ),
                          ),
                        Container(
                          width: 82,
                          height: 82,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasError
                                ? AppColors.danger.withValues(alpha: 0.10)
                                : AppColors.brand.withValues(alpha: 0.12),
                          ),
                          child: Icon(
                            hasError
                                ? Icons.error_outline_rounded
                                : Icons.fingerprint_rounded,
                            size: 42,
                            color: hasError
                                ? AppColors.danger
                                : AppColors.brandDark,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              Text(
                hasError ? '指纹验证失败' : '指纹解锁',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasError ? _error! : widget.hint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 18,
                child: Text(
                  !hasError && _mismatch ? _status : '',
                  style: const TextStyle(fontSize: 12, color: AppColors.danger),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _cancel,
                      child: const Text('改用密码'),
                    ),
                  ),
                  if (hasError) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _retry,
                        child: const Text('重试'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 普通页面用的"弹窗"版本（需要所在位置上方有 Navigator）。
Future<bool> showFingerprintDialog(
  BuildContext context, {
  String hint = '请按压指纹传感器',
}) async {
  final navigator = Navigator.maybeOf(context);
  if (navigator == null) {
    return false;
  }
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: FingerprintPrompt(
        hint: hint,
        onDone: (result) {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop(result);
          }
        },
      ),
    ),
  );
  return ok ?? false;
}
