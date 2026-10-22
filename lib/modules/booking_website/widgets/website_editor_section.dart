import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';

/// Keeps form fields mounted when a mobile section is collapsed, so edits and
/// validation survive section navigation.
class WebsiteEditorSection extends StatelessWidget {
  const WebsiteEditorSection({
    super.key,
    required this.index,
    required this.title,
    required this.description,
    required this.icon,
    required this.child,
    required this.expanded,
    required this.collapsible,
    required this.onToggle,
  });
  final int index;
  final String title, description;
  final IconData icon;
  final Widget child;
  final bool expanded, collapsible;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context), c = t.colorScheme;
    final open = !collapsible || expanded;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: collapsible,
            expanded: collapsible ? open : null,
            child: InkWell(
              onTap: collapsible ? onToggle : null,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: c.primary.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 20, color: c.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: t.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: t.textTheme.bodySmall?.copyWith(
                              color: c.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (collapsible) ...[
                      const SizedBox(width: 8),
                      Icon(open ? Icons.expand_less : Icons.expand_more),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Offstage(
            offstage: !open,
            child: TickerMode(
              enabled: open,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
