import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import '../services/pin_hash.dart';
import '../theme/app_theme.dart';
import '../widgets/fingerprint_dialog.dart';
import '../widgets/pattern_pad.dart';
import '../widgets/pin_keypad.dart';

/// 应用锁的解锁界面：按用户设置的方式输入数字密码或图形密码，
/// 也可以按指纹（弹窗自绘）。以覆盖层形式盖在整个 App 之上，不依赖路由。
class AppLockOverlay extends StatefulWidget {
  const AppLockOverlay({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<AppLockOverlay> createState() => _AppLockOverlayState();
}

class _AppLockOverlayState extends State<AppLockOverlay> {
  final AppLockService _lock = AppLockService.instance;
  final GlobalKey<PatternPadState> _padKey = GlobalKey<PatternPadState>();

  String _pin = '';
  String? _error;
  bool _verifying = false;
  bool _hasError = false;
  bool _showFingerprint = false;

  bool get _isPattern => _lock.method == UnlockMethod.pattern;

  @override
  void initState() {
    super.initState();
    if (_lock.biometricEnabled) {
      // 进锁屏就先弹一次指纹，失败再退回密码。
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlockWithFingerprint());
    }
  }

  void _append(String digit) {
    if (_verifying || _pin.length >= 6) {
      return;
    }
    setState(() {
      _pin += digit;
      _error = null;
      _hasError = false;
    });
    if (_pin.length == 6) {
      _submitPin();
    }
  }

  void _backspace() {
    if (_verifying || _pin.isEmpty) {
      return;
    }
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
      _hasError = false;
    });
  }

  Future<void> _submitPin() async {
    if (_verifying || _pin.length < 4) {
      return;
    }
    await _verify(_pin);
  }

  Future<void> _submitPattern(List<int> dots) async {
    if (_verifying) {
      return;
    }
    if (!isValidPattern(dots)) {
      setState(() {
        _error = '至少连接 $kPatternMinDots 个点';
        _hasError = true;
      });
      return;
    }
    await _verify(encodePattern(dots));
  }

  Future<void> _verify(String secret) async {
    if (_verifying) {
      return;
    }
    setState(() => _verifying = true);
    final ok = await _lock.verifySecret(secret);
    if (!mounted) {
      return;
    }
    if (ok) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _verifying = false;
      _pin = '';
      _hasError = true;
      _error = _isPattern ? '图形密码不正确，请重试' : '密码不正确，请重试';
    });
    _padKey.currentState?.clear();
  }

  Future<void> _unlockWithFingerprint() async {
    if (_showFingerprint || _verifying || !_lock.biometricEnabled) {
      return;
    }
    // 锁屏没有 Navigator（盖在 MaterialApp 外面），所以用内嵌卡片而不是 showDialog。
    final status = _lock.biometricAvailable
        ? _lock.fingerprintStatus
        : await _lock.refreshFingerprint();
    if (!mounted) {
      return;
    }
    if (!status.usable) {
      setState(() => _error = status.reason);
      return;
    }
    setState(() {
      _showFingerprint = true;
      _error = null;
    });
  }

  void _onFingerprintDone(bool ok) {
    if (!mounted) {
      return;
    }
    if (ok) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _showFingerprint = false;
      _error = '指纹没有通过，请再试一次或改用密码';
    });
  }

  /// 用户主动改用密码：不当成验证失败。
  void _onFingerprintCancel() {
    if (!mounted) {
      return;
    }
    setState(() {
      _showFingerprint = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: _buildLockBody(context)),
        if (_showFingerprint)
          Positioned.fill(
            child: Stack(
              children: [
                ModalBarrier(
                  dismissible: false,
                  color: Colors.black.withValues(alpha: 0.38),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: FingerprintPrompt(
                      hint: '请按压指纹传感器',
                      onDone: _onFingerprintDone,
                      onCancel: _onFingerprintCancel,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildLockBody(BuildContext context) {
    final canSubmitPin = _pin.length >= 4 && !_verifying;
    return Material(
      color: AppColors.canvasTop,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.canvasTop, AppColors.canvasBottom],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_outline_rounded,
                        size: 30,
                        color: AppColors.brandDark,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '应用已锁定',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_isPattern) _buildPatternArea() else _buildPinArea(),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 18,
                      child: Text(
                        _error ?? (_verifying ? '验证中…' : ''),
                        style: TextStyle(
                          fontSize: 12,
                          color: _error == null
                              ? AppColors.muted
                              : AppColors.danger,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _isPattern
                              ? const SizedBox(
                                  height: 46,
                                  child: Center(
                                    child: Text(
                                      '连完至少 4 个点后抬手即验证',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ),
                                )
                              : FilledButton(
                                  onPressed: canSubmitPin ? _submitPin : null,
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(46),
                                  ),
                                  child: const Text('解锁'),
                                ),
                        ),
                        if (_lock.biometricEnabled) ...[
                          const SizedBox(width: 10),
                          IconButton.filledTonal(
                            tooltip: '指纹解锁',
                            onPressed: _verifying ? null : _unlockWithFingerprint,
                            icon: const Icon(Icons.fingerprint_rounded),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(46, 46),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _subtitle {
    final method = _isPattern ? '图形密码' : '密码';
    if (_lock.biometricEnabled) {
      return _isPattern ? '画出$method，或按压指纹解锁' : '输入$method，或按压指纹解锁';
    }
    return _isPattern ? '请画出图形密码解锁' : '请输入密码解锁';
  }

  Widget _buildPinArea() {
    return Column(
      children: [
        PinDots(length: _pin.length, total: 6),
        const SizedBox(height: 16),
        PinKeypad(enabled: !_verifying, onDigit: _append, onBackspace: _backspace),
      ],
    );
  }

  Widget _buildPatternArea() {
    return PatternPad(
      key: _padKey,
      maxSize: 300,
      enabled: !_verifying,
      error: _hasError,
      onCompleted: _submitPattern,
    );
  }
}
