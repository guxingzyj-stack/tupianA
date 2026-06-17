import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.subtitle,
    this.isPrimary = true,
    this.height = 66,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String text;
  final IconData? icon;
  final String? subtitle;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final double height;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    final bg =
        backgroundColor ??
        (isPrimary ? theme.colorScheme.primary : theme.colorScheme.surface);
    final fg =
        foregroundColor ??
        (isPrimary ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface);
    final borderColor = isPrimary
        ? Colors.transparent
        : const Color(0xFFDDE4DF);
    final disabledBg = isPrimary
        ? bg.withValues(alpha: 0.42)
        : theme.colorScheme.surface.withValues(alpha: 0.65);
    final compact = height < 88;
    final iconBoxSize = compact ? 42.0 : 54.0;
    final horizontalPadding = compact ? 16.0 : 18.0;
    final verticalPadding = compact ? 8.0 : 12.0;

    final wrappedOnPressed = onPressed == null
        ? null
        : () {
            HapticFeedback.lightImpact();
            onPressed?.call();
          };

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: wrappedOnPressed,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              color: enabled ? bg : disabledBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: borderColor,
                width: isPrimary ? 0 : 1.4,
              ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isPrimary ? 0.12 : 0.05,
                        ),
                        blurRadius: isPrimary ? 18 : 10,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: iconBoxSize,
                      height: iconBoxSize,
                      decoration: BoxDecoration(
                        color: isPrimary
                            ? Colors.white.withValues(alpha: 0.18)
                            : theme.colorScheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, size: compact ? 28 : 32, color: fg),
                    ),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: fg,
                            fontSize: subtitle == null ? 24 : 22,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isPrimary
                                  ? Colors.white.withValues(alpha: 0.86)
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
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
