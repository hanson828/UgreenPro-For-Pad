import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 3x3 九点图形密码输入板：手指按下拖动连线，抬手回调已连接的点位。
///
/// 坐标约定：索引 0..8 从左到右、从上到下（0 1 2 / 3 4 5 / 6 7 8）。
/// 和系统一样，两点之间如果跨过中间那个点，会自动把中间点也算进去。
class PatternPad extends StatefulWidget {
  const PatternPad({
    super.key,
    required this.onCompleted,
    this.enabled = true,
    this.maxSize = 300,
    this.error = false,
  });

  /// 抬手时回调，参数是点位索引列表（长度 < 4 时也会回调，由调用方判断）。
  final ValueChanged<List<int>> onCompleted;

  final bool enabled;
  final double maxSize;

  /// 上一次是错的，连线画成红色。
  final bool error;

  @override
  State<PatternPad> createState() => PatternPadState();
}

class PatternPadState extends State<PatternPad> {
  final List<int> _picked = <int>[];
  Offset? _cursor;
  Timer? _clearTimer;

  /// 外部可以用 GlobalKey 调它清空。
  void clear() {
    _clearTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _picked.clear();
      _cursor = null;
    });
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, widget.maxSize);
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: widget.enabled
                  ? (details) => _onDown(details.localPosition, size)
                  : null,
              onPanUpdate: widget.enabled
                  ? (details) => _onMove(details.localPosition, size)
                  : null,
              onPanEnd: widget.enabled
                  ? (details) => _onUp(size)
                  : null,
              onPanCancel: widget.enabled ? () => _reset(soon: false) : null,
              child: CustomPaint(
                painter: _PatternPainter(
                  picked: _picked,
                  cursor: _cursor,
                  size: size,
                  color: widget.error ? AppColors.danger : AppColors.brand,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Offset> _centers(double size) {
    final pad = size * 0.16;
    final span = size - pad * 2;
    final step = span / 2;
    return List<Offset>.generate(9, (i) {
      final col = i % 3;
      final row = i ~/ 3;
      return Offset(pad + col * step, pad + row * step);
    });
  }

  int? _hitTest(Offset point, double size) {
    final centers = _centers(size);
    final threshold = size * 0.115;
    for (var i = 0; i < centers.length; i++) {
      if ((centers[i] - point).distance <= threshold) {
        return i;
      }
    }
    return null;
  }

  void _onDown(Offset point, double size) {
    _clearTimer?.cancel();
    setState(() {
      _picked.clear();
      _cursor = point;
    });
    final hit = _hitTest(point, size);
    if (hit != null) {
      setState(() => _picked.add(hit));
    }
  }

  void _onMove(Offset point, double size) {
    if (!mounted) {
      return;
    }
    setState(() => _cursor = point);
    final hit = _hitTest(point, size);
    if (hit == null || _picked.contains(hit)) {
      return;
    }
    // 跨过中间点时把中间点补上（0 → 2 自动带上 1）。
    if (_picked.isNotEmpty) {
      final mid = _midpoint(_picked.last, hit);
      if (mid != null && !_picked.contains(mid)) {
        setState(() => _picked.add(mid));
      }
    }
    setState(() => _picked.add(hit));
  }

  /// (row, col) 中间夹着点的两个索引 → 中间那个点。
  int? _midpoint(int a, int b) {
    final ar = a ~/ 3, ac = a % 3;
    final br = b ~/ 3, bc = b % 3;
    if ((ar + br).isEven && (ac + bc).isEven) {
      final mr = (ar + br) ~/ 2;
      final mc = (ac + bc) ~/ 2;
      final mid = mr * 3 + mc;
      if (mid != a && mid != b) {
        return mid;
      }
    }
    return null;
  }

  void _onUp(double size) {
    final result = List<int>.of(_picked);
    widget.onCompleted(result);
    _reset(soon: true);
  }

  void _reset({required bool soon}) {
    if (soon) {
      _clearTimer?.cancel();
      _clearTimer = Timer(const Duration(milliseconds: 220), () {
        if (!mounted) {
          return;
        }
        setState(() {
          _picked.clear();
          _cursor = null;
        });
      });
      return;
    }
    setState(() {
      _picked.clear();
      _cursor = null;
    });
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.picked,
    required this.cursor,
    required this.size,
    required this.color,
  });

  final List<int> picked;
  final Offset? cursor;
  final double size;
  final Color color;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final pad = size * 0.16;
    final span = size - pad * 2;
    final step = span / 2;
    final centers = List<Offset>.generate(9, (i) {
      final col = i % 3;
      final row = i ~/ 3;
      return Offset(pad + col * step, pad + row * step);
    });
    final dotRadius = size * 0.033;
    final selectedRadius = size * 0.055;

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..strokeWidth = size * 0.016
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // 连线
    for (var i = 0; i < picked.length - 1; i++) {
      canvas.drawLine(centers[picked[i]], centers[picked[i + 1]], linePaint);
    }
    if (picked.isNotEmpty && cursor != null) {
      canvas.drawLine(centers[picked.last], cursor!, linePaint);
    }

    // 点
    for (var i = 0; i < centers.length; i++) {
      final isPicked = picked.contains(i);
      canvas.drawCircle(
        centers[i],
        dotRadius,
        Paint()..color = AppColors.line,
      );
      if (isPicked) {
        canvas.drawCircle(
          centers[i],
          selectedRadius,
          Paint()..color = color.withValues(alpha: 0.18),
        );
        canvas.drawCircle(centers[i], dotRadius * 1.35, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter oldDelegate) => true;
}
