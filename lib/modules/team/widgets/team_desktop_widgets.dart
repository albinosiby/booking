import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';

String roleLabel(String role) =>
    role.isEmpty ? role : role[0].toUpperCase() + role.substring(1);

/// Small rounded label, tinted with [color] (the primary colour by default).
class TeamChip extends StatelessWidget {
  const TeamChip(this.label, {super.key, this.color, this.icon});
  final String label;
  final Color? color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tint),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tint,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circle with a person's initials.
class TeamAvatar extends StatelessWidget {
  const TeamAvatar(this.name, {super.key, this.muted = false, this.icon});
  final String name;
  final bool muted;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    final tint = muted ? colors.onSurfaceVariant : colors.primary;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .14),
        shape: BoxShape.circle,
      ),
      child: icon != null || initials.isEmpty
          ? Icon(icon ?? Icons.person_outline, color: tint, size: 21)
          : Text(
              initials,
              style: TextStyle(
                color: tint,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
    );
  }
}

/// Desktop card for one person: avatar, name, email, chips and actions.
class TeamPersonCard extends StatelessWidget {
  const TeamPersonCard({
    super.key,
    required this.name,
    required this.email,
    required this.chips,
    this.actions = const [],
    this.muted = false,
    this.note,
  });
  final String name, email;

  /// Shown in place of actions when there are none.
  final String? note;
  final List<Widget> chips, actions;
  final bool muted;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TeamAvatar(name, muted: muted),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurface.withValues(alpha: .65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Wrap(spacing: 8, runSpacing: 6, children: chips),
          ),
          const SizedBox(height: 8),
          Divider(color: colors.outline.withValues(alpha: .35)),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: actions.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Text(note ?? '', style: theme.textTheme.bodySmall),
                    ),
                  )
                : OverflowBar(
                    alignment: MainAxisAlignment.spaceBetween,
                    children: actions,
                  ),
          ),
        ],
      ),
    );
  }
}
