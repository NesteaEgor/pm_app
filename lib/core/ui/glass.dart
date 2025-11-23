import 'dart:ui';
import 'package:flutter/material.dart';

class Glass extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final double radius;
  final EdgeInsets padding;
  final Border? border;

  const Glass({
    super.key,
    required this.child,
    this.blur = 18,
    this.opacity = 0.14,
    this.radius = 24,
    this.padding = const EdgeInsets.all(16),
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: Colors.white.withValues(alpha: opacity),
            border: border ??
                Border.all(
                  color: Colors.white.withValues(alpha: 0.20),
                  width: 1,
                ),
          ),
          child: child,
        ),
      ),
    );
  }
}
