import 'dart:async';

import 'package:flutter/material.dart';

import 'big_button.dart';

Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmText = '确定',
  String cancelText = '取消',
  bool danger = false,
  int confirmDelaySeconds = 0,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ConfirmDialog(
      title: title,
      message: message,
      confirmText: confirmText,
      cancelText: cancelText,
      danger: danger,
      confirmDelaySeconds: confirmDelaySeconds,
    ),
  );
  return result ?? false;
}

class ConfirmDialog extends StatefulWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmText,
    required this.cancelText,
    required this.danger,
    this.confirmDelaySeconds = 0,
  });

  final String title;
  final String message;
  final String confirmText;
  final String cancelText;
  final bool danger;
  final int confirmDelaySeconds;

  @override
  State<ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<ConfirmDialog> {
  Timer? _timer;
  Timer? _confirmDelayTimer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.confirmDelaySeconds;
    _timer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        Navigator.of(context).pop(false);
      }
    });
    if (_remainingSeconds > 0) {
      _confirmDelayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _remainingSeconds -= 1;
          if (_remainingSeconds <= 0) {
            timer.cancel();
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _confirmDelayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Text(widget.title),
      content: Text(
        widget.message,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actions: [
        BigButton(
          text: widget.cancelText,
          isPrimary: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        const SizedBox(height: 12),
        BigButton(
          text: _remainingSeconds > 0
              ? '$_remainingSeconds 秒后可发'
              : widget.confirmText,
          backgroundColor: widget.danger
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.primary,
          onPressed: _remainingSeconds > 0
              ? null
              : () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
