import 'package:flutter/material.dart';

/// Presentation only: WhatsApp formatting never changes the underlying message.
class MessageChatPreview extends StatelessWidget {
  const MessageChatPreview({
    super.key,
    required this.message,
    this.sample = false,
  });
  final String message;
  final bool sample;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context), c = t.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                sample
                    ? Icons.science_outlined
                    : Icons.chat_bubble_outline_rounded,
                size: 18,
                color: c.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sample ? 'Sample booking' : 'Message preview',
                  style: t.textTheme.labelLarge?.copyWith(
                    color: c.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                c.primary.withValues(alpha: .09),
                c.surface,
              ),
              border: Border.all(color: c.primary.withValues(alpha: .15)),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: SelectableText.rich(
              messagePreviewSpan(
                message.isEmpty
                    ? 'Your message preview appears here.'
                    : message,
              ),
              style: t.textTheme.bodyMedium?.copyWith(
                color: c.onSurface,
                height: 1.55,
              ),
            ),
          ),
          if (sample) ...[
            const SizedBox(height: 12),
            Text(
              'Sample values replace booking fields. Your saved message keeps its placeholders.',
              style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

TextSpan messagePreviewSpan(String value, {TextStyle? style}) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(r'\*([^*\n]+)\*|_([^_\n]+)_');
  var cursor = 0;
  for (final match in pattern.allMatches(value)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: value.substring(cursor, match.start)));
    }
    final bold = match.group(1) != null;
    spans.add(
      messagePreviewSpan(
        match.group(bold ? 1 : 2)!,
        style: bold
            ? const TextStyle(fontWeight: FontWeight.w700)
            : const TextStyle(fontStyle: FontStyle.italic),
      ),
    );
    cursor = match.end;
  }
  if (cursor < value.length) spans.add(TextSpan(text: value.substring(cursor)));
  return TextSpan(style: style, children: spans);
}
