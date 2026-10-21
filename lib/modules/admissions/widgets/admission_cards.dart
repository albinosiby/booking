import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import '../../bookings/models/booking_models.dart' show bookingMoney;
import '../models/admission_models.dart';

/// Small rounded label used for admission status and alerts.
class AdmissionTag extends StatelessWidget {
  const AdmissionTag(this.label, {super.key, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .35)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

Color admissionStatusColor(BuildContext context, String status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    'active' => scheme.primary,
    'upcoming' => const Color(0xFF64B5F6),
    'expired' => const Color(0xFFFFB74D),
    'cancelled' => scheme.error,
    _ => scheme.onSurface.withValues(alpha: .7),
  };
}

IconData admissionKindIcon(String kind) => switch (kind) {
  'swimming' => Icons.pool_outlined,
  'play' => Icons.sports_tennis,
  _ => Icons.sports_outlined,
};

String admissionStatusLabel(String status) =>
    status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1);

class AdmissionListCard extends StatelessWidget {
  const AdmissionListCard({
    super.key,
    required this.admission,
    required this.currency,
    required this.onTap,
  });
  final Admission admission;
  final String currency;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final a = admission,
        theme = Theme.of(context),
        scheme = theme.colorScheme,
        muted = scheme.onSurface.withValues(alpha: .65),
        coaching = a.kind == 'coaching',
        unit = coaching ? 'classes' : 'days',
        status = admissionStatusColor(context, a.status);
    final expiry = DateTime.tryParse(a.expiry);
    final expiringSoon =
        a.status == 'active' &&
        expiry != null &&
        expiry.difference(DateTime.now()).inDays <= 7;
    final initials = a.customer.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: scheme.primary.withValues(alpha: .16),
                child: Text(
                  initials.isEmpty ? '?' : initials,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      a.reference,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AdmissionTag(admissionStatusLabel(a.status), color: status),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(admissionKindIcon(a.kind), size: 18, color: muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${a.planName} · ${a.mode == 'fixed' ? 'Fixed schedule' : 'Flexible'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${a.remaining} of ${a.allowance} $unit left',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${a.used} used',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: a.allowance == 0 ? 0 : a.used / a.allowance,
              color: status,
              backgroundColor: scheme.outline.withValues(alpha: .35),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _Meta(Icons.event_outlined, 'Expires ${a.expiry}', muted),
              _Meta(
                Icons.place_outlined,
                [
                  a.poolName,
                  a.businessName,
                ].where((v) => v.isNotEmpty).join(' · '),
                muted,
              ),
            ],
          ),
          if (a.balance > 0 ||
              expiringSoon ||
              (a.remaining <= 3 && a.status == 'active')) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (a.balance > 0)
                  AdmissionTag(
                    'Due ${bookingMoney(a.balance, currency)}',
                    color: scheme.error,
                    icon: Icons.payments_outlined,
                  ),
                if (a.remaining <= 3 && a.status == 'active')
                  const AdmissionTag(
                    'Low balance',
                    color: Color(0xFFFFB74D),
                    icon: Icons.hourglass_bottom,
                  ),
                if (expiringSoon)
                  const AdmissionTag(
                    'Expiring soon',
                    color: Color(0xFFFFB74D),
                    icon: Icons.schedule,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text, this.color);
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ),
    ],
  );
}

class AdmissionPlanCard extends StatelessWidget {
  const AdmissionPlanCard({
    super.key,
    required this.plan,
    required this.business,
    required this.currency,
    this.onEnroll,
  });
  final AdmissionPlan plan;
  final AdmissionBusiness business;
  final String currency;
  final VoidCallback? onEnroll;
  @override
  Widget build(BuildContext context) {
    final p = plan,
        theme = Theme.of(context),
        scheme = theme.colorScheme,
        muted = scheme.onSurface.withValues(alpha: .65),
        coaching = p.kind == 'coaching';
    final spaces = business.pools
        .where((s) => p.poolIds.contains(s.id))
        .map((s) => s.name)
        .join(', ');
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(admissionKindIcon(p.kind), color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bookingMoney(p.total, currency),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (p.activeCount != null)
                AdmissionTag(
                  '${p.activeCount} active',
                  color: scheme.primary,
                  icon: Icons.people_outline,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Fact(
                Icons.confirmation_number_outlined,
                '${p.allowance} ${coaching ? 'classes' : 'days'}',
              ),
              _Fact(Icons.event_available_outlined, p.validityLabel),
              if (coaching && p.duration != null)
                _Fact(Icons.timer_outlined, '${p.duration} min'),
              if (coaching && p.seats != null)
                _Fact(Icons.groups_outlined, '${p.seats} per class'),
            ],
          ),
          const SizedBox(height: 12),
          if (coaching) _Meta(Icons.person_outline, p.coach, muted),
          if (spaces.isNotEmpty) ...[
            const SizedBox(height: 4),
            _Meta(Icons.place_outlined, spaces, muted),
          ],
          if (onEnroll != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onEnroll,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Enroll student'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSurface.withValues(alpha: .7)),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
