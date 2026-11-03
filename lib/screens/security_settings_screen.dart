import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import '../services/fingerprint_auth.dart';
import '../theme/app_theme.dart';
import 'secret_verify_screen.dart';
import 'unlock_method_screen.dart';

/// 安全设置（一级菜单）：总开关、解锁方式（进入二级菜单）、指纹解锁。
class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen>
    with WidgetsBindingObserver {
  final AppLockService _lock = AppLockService.instance;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 用户可能刚从系统设置里录完指纹 / 从二级菜单回来，重新检测一次。
    _lock.refreshFingerprint();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lock.refreshFingerprint().then((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  Future<void> _toggleLock(bool value) async {
    if (_busy) {
      return;
    }
    if (!value) {
      // 关闭前先验证当前凭据，避免别人拿到已解锁的设备直接关掉。
      final ok = await verifyCurrentSecret(context, title: '关闭应用锁');
      if (!ok || !mounted) {
        return;
      }
      setState(() => _busy = true);
      await _lock.disable();
      if (mounted) {
        setState(() => _busy = false);
      }
      return;
    }

    // 开启前得有凭据：没有就去二级菜单里设一个。
    if (!_lock.hasSecret) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const UnlockMethodScreen()),
      );
      if (!mounted) {
        return;
      }
      if (!_lock.hasSecret) {
        _toast('请先设置解锁方式');
        return;
      }
    }
    setState(() => _busy = true);
    await _lock.setEnabled(true);
    if (mounted) {
      setState(() => _busy = false);
    }
    _toast('已开启应用锁');
  }

  Future<void> _openMethodScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UnlockMethodScreen()),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (!value) {
      await _lock.setBiometricEnabled(false);
      if (mounted) {
        setState(() {});
      }
      return;
    }
    // 开之前先看系统里到底能不能用：没录入就直接引导去录入。
    final status = await _lock.refreshFingerprint();
    if (!mounted) {
      return;
    }
    setState(() {});
    if (!status.usable) {
      _toast(
        status.reason,
        actionLabel: status.hardware ? '去录入' : null,
        onAction: FingerprintAuth.instance.openEnrollment,
      );
      return;
    }
    final ok = await _lock.authenticateFingerprint(context);
    if (!mounted) {
      return;
    }
    if (!ok) {
      _toast('未通过指纹验证，无法开启');
      return;
    }
    await _lock.setBiometricEnabled(true);
    if (mounted) {
      setState(() {});
    }
  }

  void _toast(
    String text, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 4),
        action: actionLabel == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _lock.isEnabled;
    final bioAvailable = _lock.biometricAvailable;
    return Scaffold(
      backgroundColor: AppColors.canvasTop,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '返回',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Text(
                          '安全设置',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.only(right: 10),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Column(
                          children: [
                            SwitchListTile.adaptive(
                              value: enabled,
                              onChanged: _busy ? null : _toggleLock,
                              title: const Text(
                                '进入应用需要验证',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: const Text(
                                '冷启动或后台超过一分钟返回时，先解锁再进入',
                                style: TextStyle(fontSize: 12, color: AppColors.muted),
                              ),
                              secondary: const Icon(
                                Icons.lock_outline_rounded,
                                color: AppColors.brandDark,
                              ),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            ListTile(
                              onTap: _busy ? null : _openMethodScreen,
                              leading: const Icon(
                                Icons.tune_rounded,
                                color: AppColors.brandDark,
                              ),
                              title: const Text(
                                '解锁方式',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                _lock.hasSecret
                                    ? '当前：${_lock.method.label}'
                                    : '还没有设置，点进去选数字或图形密码',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.muted,
                              ),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            SwitchListTile.adaptive(
                              value: _lock.biometricEnabled,
                              onChanged: (!enabled || _busy)
                                  ? null
                                  : _toggleBiometric,
                              title: const Text(
                                '指纹解锁',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                enabled
                                    ? (bioAvailable
                                        ? '按压指纹代替输入密码，弹窗为本应用自绘'
                                        : _lock.fingerprintStatus.reason)
                                    : '需要先开启上面的应用锁',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                ),
                              ),
                              secondary: const Icon(
                                Icons.fingerprint_rounded,
                                color: AppColors.brandDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '数字密码和图形密码只能二选一，两者都只保存在本机的加密存储里'
                        '（Android Keystore + 加盐哈希），不会上传；'
                        '忘记凭证只能关闭应用锁后重新设置。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
