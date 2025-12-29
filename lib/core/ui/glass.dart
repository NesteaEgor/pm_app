import 'dart:ui';
import 'package:flutter/material.dart';

class Glass extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final double radius;
  final EdgeInsets padding;
  final Border? border;

  /// Optional: можно принудительно задать цвет стекла
  final Color? color;

  const Glass({
    super.key,
    required this.child,
    this.blur = 18,
    this.opacity = 0.12,
    this.radius = 24,
    this.padding = const EdgeInsets.all(16),
    this.border,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Нежный tint под primary, но база — surface.
    final base = color ??
        Color.alphaBlend(
          scheme.primary.withOpacity(0.06),
          scheme.surface,
        );

    final stroke = (border != null)
        ? null
        : Border.all(
      color: scheme.outlineVariant.withOpacity(0.55),
      width: 1,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: base.withOpacity(opacity),
            border: border ?? stroke,
          ),
          child: child,
        ),
      ),
    );
  }
}
