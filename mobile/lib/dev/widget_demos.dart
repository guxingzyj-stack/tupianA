import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/widgets/big_button.dart';
import '../core/widgets/confirm_dialog.dart';
import '../core/widgets/elderly_app_bar.dart';
import '../core/widgets/long_press_compare.dart';
import '../core/widgets/option_picker.dart';
import '../core/widgets/waiting_card.dart';

class WidgetDemosPage extends StatefulWidget {
  const WidgetDemosPage({super.key});

  @override
  State<WidgetDemosPage> createState() => _WidgetDemosPageState();
}

class _WidgetDemosPageState extends State<WidgetDemosPage> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final sampleImage = MemoryImage(base64Decode(_samplePngBase64));
    return Scaffold(
      appBar: const ElderlyAppBar(title: '组件'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            BigButton(
              text: '修照片',
              icon: Icons.auto_fix_high_rounded,
              onPressed: () {},
            ),
            const SizedBox(height: 14),
            BigButton(
              text: '保存',
              icon: Icons.download_rounded,
              isPrimary: false,
              onPressed: () {},
            ),
            const SizedBox(height: 24),
            LongPressCompareView(
              originalImage: sampleImage,
              resultImage: sampleImage,
            ),
            const SizedBox(height: 24),
            OptionPicker(
              options: const [
                RepairOptionViewModel(name: '更明亮'),
                RepairOptionViewModel(name: '更鲜艳'),
                RepairOptionViewModel(name: '更柔和'),
              ],
              selectedIndex: _selected,
              onSelect: (index) => setState(() => _selected = index),
            ),
            const SizedBox(height: 24),
            const WaitingCard(estimatedSeconds: 120, message: '正在制作'),
            const SizedBox(height: 24),
            BigButton(
              text: '删除',
              backgroundColor: Theme.of(context).colorScheme.error,
              onPressed: () {
                showConfirmDialog(
                  context: context,
                  title: '确认删除?',
                  message: '删除后这条记录就没有了',
                  confirmText: '删除',
                  danger: true,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

const _samplePngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAcElEQVR4nO3PsQ0AIAwDQeD/'
    'p9MOCiQK9GXuqmYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMDPW2Yd4L7rYg8AAAAAAAAAAAD4'
    'O1IAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADw54EBAAAAAAAAAAAAAAAAAAAAAAAAgD8hfQIMoI'
    'G5+gAAAABJRU5ErkJggg==';
