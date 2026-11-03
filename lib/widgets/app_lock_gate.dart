import 'package:flutter/material.dart';

import '../screens/lock_screen.dart';
import '../services/app_lock_service.dart';

/// 应用锁闸门：包在 MaterialApp.builder 外面，盖住整个导航栈。
/// - 冷启动时如果开了应用锁，先要求解锁；
/// - App 退到后台超过 [_relockAfter] 再回来，重新上锁。
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  static const Duration _relockAfter = Duration(minutes: 1);

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final AppLockService _lock = AppLockService.instance;

  bool _locked = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locked = _lock.isEnabled;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        _backgroundedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final at = _backgroundedAt;
        _backgroundedAt = null;
        if (at != null &&
            _lock.isEnabled &&
            DateTime.now().difference(at) > AppLockGate._relockAfter) {
          setState(() => _locked = true);
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: AppLockOverlay(
              onUnlocked: () {
                if (mounted) {
                  setState(() => _locked = false);
                }
              },
            ),
          ),
      ],
    );
  }
}
