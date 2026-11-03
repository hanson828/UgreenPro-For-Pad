import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import '../services/pin_hash.dart';
import '../theme/app_theme.dart';
import '../widgets/pattern_pad.dart';
import '../widgets/pin_keypad.dart';

/// 验证当前凭据（数字密码或图形密码，按用户当前设置自动选界面）。
/// 通过返回 true；取消或连续输错 3 次返回 false。
Future<bool> verifyCurrentSecret(
  BuildContext context, {
  String title = '验证身份',
}) async {
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => SecretVerifyScreen(title: title)),
  );
  return ok ?? false;
}

class SecretVerifyScreen extends StatefulWidget {
  const SecretVerifyScreen({super.key, required this.title});

  final String title;

  @override
  State<SecretVerifyScreen> createState() => _SecretVerifyScreenState();
}

class _SecretVerifyScreenState extends State<SecretVerifyScreen> {
  static const int _maxTries = 3;

  final AppLockService _lock = AppLockService.instance;
  final GlobalKey<PatternPadState> _padKey = GlobalKey<PatternPadState>();

  String _pin = '';
  String? _error;
  bool _busy = false;
  bool _hasError = false;
  int _tries = 0;

  bool get _isPattern => _lock.method == UnlockMethod.pattern;

  Future<void> _submit(String secret) async {
    if (_busy || secret.isEmpty) {
      return;
    }
    setState(() => _busy = true);
    final ok = await _lock.verifySecret(secret);
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    _tries++;
    if (_tries >= _maxTries) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _busy = false;
      _pin = '';
      _hasError = true;
      _error = '${_isPattern ? '图形' : '密码'}不正确，还可尝试 ${_maxTries - _tries} 次';
    });
    _padKey.currentState?.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvasTop,
      appBar: AppBar(
        backgroundColor: AppColors.canvasTop,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isPattern ? '请画出当前图形密码' : '请输入当前数字密码',
                    style: const TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 20,
                    child: Text(
                      _error ?? '',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_isPattern) ...[
                    PatternPad(
                      key: _padKey,
                      maxSize: 280,
                      enabled: !_busy,
                      error: _hasError,
                      onCompleted: (dots) {
                        if (dots.length >= kPatternMinDots) {
                          _submit(encodePattern(dots));
                        }
                      },
                    ),
                  ] else ...[
                    PinDots(length: _pin.length),
                    const SizedBox(height: 16),
                    PinKeypad(
                      enabled: !_busy,
                      onDigit: (digit) {
                        if (_busy || _pin.length >= 6) {
                          return;
                        }
                        setState(() {
                          _pin += digit;
                          _error = null;
                          _hasError = false;
                        });
                      },
                      onBackspace: () {
                        if (_busy || _pin.isEmpty) {
                          return;
                        }
                        setState(() {
                          _pin = _pin.substring(0, _pin.length - 1);
                          _error = null;
                          _hasError = false;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: (!_busy && _pin.length >= 4)
                            ? () => _submit(_pin)
                            : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                        child: const Text('验证'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
