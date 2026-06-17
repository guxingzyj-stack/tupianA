import 'package:flutter/material.dart';

class ElderlyAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ElderlyAppBar({
    super.key,
    required this.title,
    this.showBack = true,
    this.actions,
  });

  final String title;
  final bool showBack;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(76);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: preferredSize.height,
      automaticallyImplyLeading: false,
      leadingWidth: showBack ? 76 : 0,
      leading: showBack
          ? Padding(
              padding: const EdgeInsets.only(left: 16, top: 10, bottom: 10),
              child: IconButton(
                tooltip: '返回',
                iconSize: 30,
                style: IconButton.styleFrom(
                  fixedSize: const Size(56, 56),
                  backgroundColor: const Color(0xFFE3F3EE),
                  foregroundColor: const Color(0xFF18211F),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            )
          : null,
      title: Text(title),
      actions: actions,
    );
  }
}
