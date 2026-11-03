import 'package:flutter/material.dart';

import '../services/pin_hash.dart';
import '../theme/app_theme.dart';
import '../widgets/pattern_pad.dart';

/// 设置图形密码：画一次 → 再画一次确认，成功后返回点位串（"0-1-2-5"）。
/// 取消返回 null。
Future<String?> askPatternSetup(
  BuildContext context, {
  String title = '设置图形密码',
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => _PatternSetupScreen(title: title)),
  );
}

class _PatternSetupScreen extends StatefulWidget {
  const _PatternSetupScreen({required this.title});

  final String title;

  @override
  State<_PatternSetupScreen> createState() => _PatternSetupScreenState();
}

class _PatternSetupScreenState extends State<_PatternSetupScreen> {
  final GlobalKey<PatternPadState> _padKey = GlobalKey<PatternPadState>();

  String? _first;
  String? _error;
  bool _hasError = false;

  String get _hint =>
      _first == null ? '至少连接 4 个点，抬手结束' : '再画一次以确认';

  void _onCompleted(List<int> dots) {
    if (!isValidPattern(dots)) {
      setState(() {
        _error = '至少连接 $kPatternMinDots 个点';
        _hasError = true;
      });
      return;
    }
    final encoded = encodePattern(dots);
    if (_first == null) {
      setState(() {
        _first = encoded;
        _error = null;
        _hasError = false;
      });
      return;
    }
    if (_first == encoded) {
      Navigator.of(context).pop(encoded);
      return;
    }
    setState(() {
      _first = null;
      _error = '两次不一致，请重新设置';
      _hasError = true;
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
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _hint,
                    style: const TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                  const SizedBox(height: 6),
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
                  const SizedBox(height: 4),
                  PatternPad(
                    key: _padKey,
                    maxSize: 280,
                    error: _hasError,
                    onCompleted: _onCompleted,
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
