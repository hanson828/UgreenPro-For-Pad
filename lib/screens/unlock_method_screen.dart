import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pin_input_dialog.dart';
import 'pattern_setup_screen.dart';
import 'secret_verify_screen.dart';

/// 二级菜单：选择解锁方式（数字密码 / 图形密码，二选一）与修改当前凭据。
class UnlockMethodScreen extends StatefulWidget {
  const UnlockMethodScreen({super.key});

  @override
  State<UnlockMethodScreen> createState() => _UnlockMethodScreenState();
}

class _UnlockMethodScreenState extends State<UnlockMethodScreen> {
  final AppLockService _lock = AppLockService.instance;

  bool _busy = false;

  Future<void> _select(UnlockMethod target) async {
    if (_busy || target == _lock.method) {
      return;
    }
    // 已经设过凭据时，先验证当前的，防止别人顺手换掉。
    if (_lock.hasSecret) {
      final ok = await verifyCurrentSecret(
        context,
        title: '验证当前${_lock.method.label}',
      );
      if (!ok || !mounted) {
        return;
      }
    }
    await _setNew(target);
  }

  Future<void> _changeCurrent() async {
    if (_busy) {
      return;
    }
    final ok = await verifyCurrentSecret(
      context,
      title: '验证当前${_lock.method.label}',
    );
    if (!ok || !mounted) {
      return;
    }
    await _setNew(_lock.method);
  }

  /// 设置（并切换到）指定的解锁方式。
  Future<void> _setNew(UnlockMethod method) async {
    if (!mounted) {
      return;
    }
    setState(() => _busy = true);
    if (method == UnlockMethod.pin) {
      final pin = await askPinDialog(context, title: '设置数字密码');
      if (pin == null || !mounted) {
        setState(() => _busy = false);
        return;
      }
      final confirm = await askPinDialog(context, title: '再输一次');
      if (confirm == null || !mounted) {
        setState(() => _busy = false);
        return;
      }
      if (pin != confirm) {
        setState(() => _busy = false);
        _toast('两次输入不一致，密码未修改');
        return;
      }
      await _lock.setSecret(pin, UnlockMethod.pin);
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      _toast('已使用数字密码');
      return;
    }

    final pattern = await askPatternSetup(context);
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (pattern == null) {
      return;
    }
    await _lock.setSecret(pattern, UnlockMethod.pattern);
    if (!mounted) {
      return;
    }
    setState(() {});
    _toast('已使用图形密码');
  }

  void _toast(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _lock.method;
    return Scaffold(
      backgroundColor: AppColors.canvasTop,
      appBar: AppBar(
        backgroundColor: AppColors.canvasTop,
        elevation: 0,
        title: const Text(
          '解锁方式',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    children: [
                      _MethodTile(
                        method: UnlockMethod.pin,
                        current: current,
                        icon: Icons.password_rounded,
                        subtitle: '4-6 位数字，用键盘输入',
                        onTap: _busy ? null : () => _select(UnlockMethod.pin),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _MethodTile(
                        method: UnlockMethod.pattern,
                        current: current,
                        icon: Icons.gesture_rounded,
                        subtitle: '3x3 九点连线，至少 4 个点',
                        onTap: _busy ? null : () => _select(UnlockMethod.pattern),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: ListTile(
                    enabled: _lock.hasSecret && !_busy,
                    onTap: _changeCurrent,
                    leading: const Icon(
                      Icons.edit_rounded,
                      color: AppColors.brandDark,
                    ),
                    title: Text(
                      current == UnlockMethod.pattern ? '修改图形密码' : '修改数字密码',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '两种方式只能二选一；切换时需要先验证当前方式。'
                  '凭据只保存在本机的加密存储里（随机盐 + HMAC-SHA256 迭代哈希），'
                  '不会上传。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.muted,
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

/// 解锁方式的一行：选中的打勾。
class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.current,
    required this.icon,
    required this.subtitle,
    required this.onTap,
  });

  final UnlockMethod method;
  final UnlockMethod current;
  final IconData icon;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final selected = method == current;
    return ListTile(
      enabled: onTap != null,
      onTap: onTap,
      leading: Icon(icon, color: AppColors.brandDark),
      title: Text(
        method.label,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: AppColors.brand)
          : const Icon(Icons.radio_button_unchecked_rounded,
              color: AppColors.muted),
    );
  }
}
