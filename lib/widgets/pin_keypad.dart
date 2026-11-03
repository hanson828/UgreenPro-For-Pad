import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 数字密码的圆点指示器。
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.length, this.total = 6});

  final int length;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(total, (index) {
        final filled = index < length;
        return Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? AppColors.brand : Colors.transparent,
            border: Border.all(
              color: filled ? AppColors.brand : AppColors.line,
              width: 1.6,
            ),
          ),
        );
      }),
    );
  }
}

/// 数字键盘（1-9、0、退格）。
class PinKeypad extends StatelessWidget {
  const PinKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                for (final digit in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: _Key(
                        onTap: enabled ? () => onDigit(digit) : null,
                        label: digit,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Row(
          children: [
            const Expanded(child: SizedBox()),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: _Key(
                  onTap: enabled ? () => onDigit('0') : null,
                  label: '0',
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: _Key(
                  onTap: enabled ? onBackspace : null,
                  icon: Icons.backspace_outlined,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.onTap, this.label, this.icon});

  final VoidCallback? onTap;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Center(
            child: icon != null
                ? Icon(icon, size: 20, color: AppColors.ink)
                : Text(
                    label ?? '',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
