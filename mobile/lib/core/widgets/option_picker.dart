import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RepairOptionViewModel {
  const RepairOptionViewModel({required this.name, this.previewImage});

  final String name;
  final ImageProvider? previewImage;
}

class OptionPicker extends StatelessWidget {
  const OptionPicker({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<RepairOptionViewModel> options;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < options.length; index++) ...[
          Expanded(
            child: _OptionTile(
              option: options[index],
              selected: index == selectedIndex,
              onTap: () {
                HapticFeedback.lightImpact();
                onSelect(index);
              },
            ),
          ),
          if (index != options.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final RepairOptionViewModel option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? Theme.of(context).colorScheme.primary
        : const Color(0xFFDDE4DF);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 134),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: borderColor, width: selected ? 3 : 1.4),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.08 : 0.035),
              blurRadius: selected ? 14 : 8,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: option.previewImage == null
                    ? ColoredBox(
                        color: selected
                            ? const Color(0xFFE8F4EF)
                            : const Color(0xFFF1F3F1),
                        child: Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.auto_fix_high_rounded,
                          size: 34,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xFF68736F),
                        ),
                      )
                    : Image(image: option.previewImage!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              option.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
