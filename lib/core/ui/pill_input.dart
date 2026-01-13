import 'package:flutter/material.dart';
//не юзаю
class PillInput extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final Widget? leading;
  final Widget? trailing;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final VoidCallback? onSubmitted;

  const PillInput({
    super.key,
    required this.controller,
    required this.hintText,
    this.leading,
    this.trailing,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.textInputAction,
    this.keyboardType,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.65),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                if (leading != null) ...[
                  const SizedBox(width: 12),
                  IconTheme(
                    data: IconThemeData(color: cs.onSurfaceVariant),
                    child: leading!,
                  ),
                ],
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: minLines,
                    maxLines: maxLines,
                    maxLength: maxLength,
                    textInputAction: textInputAction,
                    keyboardType: keyboardType,
                    onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
                    decoration: InputDecoration(
                      hintText: hintText,
                      counterText: '',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: leading == null ? 16 : 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            height: 48,
            child: trailing!,
          ),
        ],
      ],
    );
  }
}
