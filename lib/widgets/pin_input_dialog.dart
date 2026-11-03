import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/pin_hash.dart';

/// 弹出一个只收数字的输入框，格式合法返回内容，取消返回 null。
Future<String?> askPinDialog(
  BuildContext context, {
  required String title,
  String hint = '4-6 位数字',
}) async {
  final controller = TextEditingController();
  String? error;
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setLocal) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: InputDecoration(hintText: hint, errorText: error),
          onSubmitted: (_) {},
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (!isValidPin(value)) {
                setLocal(() => error = '请输入 4-6 位数字');
                return;
              }
              Navigator.of(dialogContext).pop(value);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}
