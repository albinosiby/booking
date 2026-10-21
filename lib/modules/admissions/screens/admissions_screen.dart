import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/admission_cubit.dart';
import '../cubit/admission_state.dart';
import '../../bookings/models/booking_models.dart' show bookingMoney;
import '../widgets/admission_cards.dart';

class AdmissionsScreen extends StatefulWidget {
  const AdmissionsScreen({super.key});
  @override
  State<AdmissionsScreen> createState() => _AdmissionsScreenState();
}

class _AdmissionsScreenState extends State<AdmissionsScreen> {
  late final cubit = getIt<AdmissionCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  @override
  void initState() {
    super.initState();
    cubit.loadList();
  }

  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Future<void> open(String path) async {
    await context.push(path);
    if (mounted) cubit.loadList();
  }

  bool plans = false, kindChecked = false;
  static const statuses = [
    'active',
    'upcoming',
    'completed',
    'expired',
    'cancelled',
  ];

  /// Plan kinds offered by the organization's pool and court businesses.
  List<String> kinds(AdmissionState s) => [
    if (s.catalog.businesses.any((b) => !b.court)) 'swimming',
    if (s.catalog.businesses.any((b) => b.court)) 'play',
    'coaching',
  ];
  static String kindLabel(String kind) => switch (kind) {
    'swimming' => 'Swimming',
    'play' => 'Court plans',
    _ => 'Coaching',
  };

  /// Court-only organizations have no swimming plans; open court plans first.
  void defaultKind(AdmissionState s) {
    if (kindChecked || s.loading || s.catalog.businesses.isEmpty) return;
    kindChecked = true;
    final available = kinds(s);
    if (!available.contains(s.kind)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) cubit.filter(kind: available.first);
      });
    }
  }

  Widget admissions(AdmissionState s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        initialValue: s.query,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          hintText: 'Search name, phone or admission no.',
          prefixIcon: Icon(Icons.search),
        ),
        onFieldSubmitted: (q) => cubit.filter(query: q),
      ),
      SizedBox(height: 12.h),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final value in [null, ...statuses])
              Padding(
                padding: EdgeInsets.only(right: 8.w),
                child: ChoiceChip(
                  label: Text(
                    value == null ? 'All' : admissionStatusLabel(value),
                  ),
                  selected: s.status == value,
                  onSelected: (_) =>
                      cubit.filter(status: value, clearStatus: value == null),
                ),
              ),
          ],
        ),
      ),
      SizedBox(height: 16.h),
      if (s.loading) AppLoadingState(initial: s.items.isEmpty),
      if (s.error != null)
        AppErrorWidget(message: s.error!, onRetry: () => cubit.loadList()),
      if (!s.loading && s.error == null && s.items.isEmpty)
        AppEmptyState(
          title: 'No admissions found',
          message: s.query.isNotEmpty || s.status != null
              ? 'Try another search or status.'
              : 'Enroll a student from one of your plans.',
        ),
      if (s.items.isNotEmpty) ...[
        Text(
          '${s.items.length}${s.next != null ? '+' : ''} admissions',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        SizedBox(height: 10.h),
      ],
      for (final a in s.items)
        Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: AdmissionListCard(
            key: ValueKey('admission-${a.id}'),
            admission: a,
            currency: s.catalog.currency,
            onTap: () => open('/admissions/${a.id}'),
          ),
        ),
      if (s.next != null)
        AppButton(
          label: 'Load more',
          secondary: true,
          onPressed: s.loading ? null : () => cubit.loadList(more: true),
        ),
    ],
  );

  Widget planList(AdmissionState s) {
    final groups = [
      for (final b in s.catalog.businesses)
        (b, b.plans.where((p) => p.kind == s.kind).toList()),
    ].where((g) => g.$2.isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.loading && s.catalog.businesses.isEmpty)
          const AppLoadingState(initial: true),
        if (!s.loading && groups.isEmpty)
          AppEmptyState(
            title: switch (s.kind) {
              'swimming' => 'No swimming plans',
              'play' => 'No court plans',
              _ => 'No coaching plans',
            },
            message:
                'Add plans in the pool or court business settings, then enroll students here.',
          ),
        for (final g in groups) ...[
          Row(
            children: [
              Icon(
                g.$1.court ? Icons.sports_tennis : Icons.pool_outlined,
                size: 18,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  g.$1.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${g.$2.length} ${g.$2.length == 1 ? 'plan' : 'plans'}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
          SizedBox(height: 10.h),
          for (final p in g.$2)
            Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: AdmissionPlanCard(
                key: ValueKey('plan-${p.id}'),
                plan: p,
                business: g.$1,
                currency: s.catalog.currency,
                onEnroll: s.catalog.canManage
                    ? () => open(
                        '/admissions/new?business_id=${g.$1.id}&plan_id=${p.id}',
                      )
                    : null,
              ),
            ),
          SizedBox(height: 8.h),
        ],
      ],
    );
  }

  Widget tabs() => SegmentedButton<bool>(
    showSelectedIcon: false,
    segments: const [
      ButtonSegment(value: false, label: Text('Admissions')),
      ButtonSegment(value: true, label: Text('Plans')),
    ],
    selected: {plans},
    onSelectionChanged: (v) => setState(() => plans = v.first),
  );

  Widget kindChips(AdmissionState s, List<String> available) => Wrap(
    spacing: 8.w,
    runSpacing: 8.h,
    children: [
      for (final kind in available)
        ChoiceChip(
          avatar: Icon(switch (kind) {
            'swimming' => Icons.pool_outlined,
            'play' => Icons.sports_tennis,
            _ => Icons.sports_outlined,
          }, size: 18),
          label: Text(kindLabel(kind)),
          selected: s.kind == kind,
          onSelected: (_) => cubit.filter(kind: kind),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<AdmissionCubit, AdmissionState>(
        bloc: cubit,
        builder: (context, s) {
          defaultKind(s);
          final available = kinds(s);
          if (isDesktopWidth(context)) return desktop(s, available);
          return AppPage(
            title: 'Admissions & Coaching',
            back: true,
            scrollId: 'admissions',
            subtitle: 'Students, plans, attendance and renewals.',
            actions: [
              IconButton(
                tooltip: 'Refresh admissions',
                onPressed: s.loading ? null : () => cubit.loadList(),
                icon: const Icon(Icons.refresh),
              ),
            ],
            children: [
              tabs(),
              SizedBox(height: 12.h),
              if (available.length > 1 || s.kind != available.first)
                kindChips(s, available),
              SizedBox(height: 16.h),
              if (s.catalog.canManage) ...[
                AppButton(
                  label: 'New admission',
                  icon: Icons.person_add_alt_1_outlined,
                  onPressed: () => open('/admissions/new'),
                ),
                SizedBox(height: 16.h),
              ],
              plans ? planList(s) : admissions(s),
            ],
          );
        },
      );

  // Desktop web: header actions, toolbar, stat tiles and a card grid.
  Widget desktop(AdmissionState s, List<String> available) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    return AppPage(
      title: 'Admissions & Coaching',
      back: true,
      scrollId: 'admissions',
      maxWidth: 1240,
      header: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admissions & Coaching',
                  style: theme.textTheme.headlineLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Students, plans, attendance and renewals.',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: .65),
                  ),
                ),
              ],
            ),
          ),
          IconButton.outlined(
            tooltip: 'Refresh admissions',
            onPressed: s.loading ? null : () => cubit.loadList(),
            icon: const Icon(Icons.refresh),
          ),
          if (s.catalog.canManage) ...[
            const SizedBox(width: 10),
            FilledButton.icon(
              key: const ValueKey('admissions-new'),
              onPressed: () => open('/admissions/new'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('New admission'),
            ),
          ],
        ],
      ),
      children: [
        AppToolbar(
          leading: Row(
            children: [
              tabs(),
              if (available.length > 1 || s.kind != available.first) ...[
                const SizedBox(width: 20),
                Flexible(child: kindChips(s, available)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        plans ? desktopPlans(s) : desktopAdmissions(s),
      ],
    );
  }

  Widget desktopAdmissions(AdmissionState s) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final active = s.items.where((a) => a.status == 'active').toList();
    final upcoming = s.items.where((a) => a.status == 'upcoming').length;
    final expiring = active.where((a) {
      final expiry = DateTime.tryParse(a.expiry);
      return expiry != null && expiry.difference(now).inDays <= 7;
    }).length;
    final low = active.where((a) => a.remaining <= 3).length;
    final dues = s.items.where((a) => a.balance > 0).toList();
    final due = dues.fold(0, (n, a) => n + a.balance);
    final more = s.next != null;
    const amber = Color(0xFFFFB74D);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.items.isNotEmpty) ...[
          AppStatRow(
            children: [
              AppStatTile(
                highlight: true,
                icon: admissionKindIcon(s.kind),
                label: 'Students',
                value: '${s.items.length}${more ? '+' : ''}',
                caption: more
                    ? '${kindLabel(s.kind)} · more to load'
                    : kindLabel(s.kind),
              ),
              AppStatTile(
                icon: Icons.how_to_reg_outlined,
                label: 'Active',
                value: '${active.length}',
                caption: upcoming == 0
                    ? 'Currently attending'
                    : '$upcoming upcoming',
                onTap: s.status == 'active'
                    ? null
                    : () => cubit.filter(status: 'active'),
              ),
              AppStatTile(
                icon: Icons.schedule,
                accent: expiring > 0 ? amber : null,
                label: 'Expiring in 7 days',
                value: '$expiring',
                caption: low == 0
                    ? 'No low balances'
                    : '$low with 3 or fewer left',
              ),
              AppStatTile(
                icon: due > 0
                    ? Icons.payments_outlined
                    : Icons.check_circle_outline,
                accent: due > 0 ? scheme.error : null,
                label: 'Payments due',
                value: bookingMoney(due, s.catalog.currency),
                caption: dues.isEmpty
                    ? 'All shown students paid'
                    : '${dues.length} ${dues.length == 1 ? 'student' : 'students'} with dues',
              ),
            ],
          ),
          const SizedBox(height: 28),
        ],
        AppToolbar(
          leading: Row(
            children: [
              SizedBox(
                width: 340,
                child: TextFormField(
                  initialValue: s.query,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Search name, phone or admission no.',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onFieldSubmitted: (q) => cubit.filter(query: q),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final value in [null, ...statuses])
                      ChoiceChip(
                        label: Text(
                          value == null ? 'All' : admissionStatusLabel(value),
                        ),
                        selected: s.status == value,
                        onSelected: (_) => cubit.filter(
                          status: value,
                          clearStatus: value == null,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            if (s.items.isNotEmpty)
              Text(
                '${s.items.length}${more ? '+' : ''} admissions',
                style: Theme.of(context).textTheme.labelLarge,
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (s.loading) AppLoadingState(initial: s.items.isEmpty),
        if (s.error != null)
          AppErrorWidget(message: s.error!, onRetry: () => cubit.loadList()),
        if (!s.loading && s.error == null && s.items.isEmpty)
          AppEmptyState(
            title: 'No admissions found',
            message: s.query.isNotEmpty || s.status != null
                ? 'Try another search or status.'
                : 'Enroll a student from one of your plans.',
          ),
        AppGrid(
          minTileWidth: 340,
          maxColumns: 3,
          children: [
            for (final a in s.items)
              AdmissionListCard(
                key: ValueKey('admission-${a.id}'),
                admission: a,
                currency: s.catalog.currency,
                onTap: () => open('/admissions/${a.id}'),
              ),
          ],
        ),
        if (more) ...[
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 260,
              child: AppButton(
                label: 'Load more',
                secondary: true,
                onPressed: s.loading ? null : () => cubit.loadList(more: true),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget desktopPlans(AdmissionState s) {
    final groups = [
      for (final b in s.catalog.businesses)
        (b, b.plans.where((p) => p.kind == s.kind).toList()),
    ].where((g) => g.$2.isNotEmpty).toList();
    if (groups.isEmpty) return planList(s);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in groups)
          AppPanel(
            title: g.$1.name,
            subtitle:
                '${g.$2.length} ${g.$2.length == 1 ? 'plan' : 'plans'} · ${g.$1.court ? 'Court' : 'Pool'}',
            child: AppGrid(
              minTileWidth: 340,
              maxColumns: 3,
              children: [
                for (final p in g.$2)
                  AdmissionPlanCard(
                    key: ValueKey('plan-${p.id}'),
                    plan: p,
                    business: g.$1,
                    currency: s.catalog.currency,
                    onEnroll: s.catalog.canManage
                        ? () => open(
                            '/admissions/new?business_id=${g.$1.id}&plan_id=${p.id}',
                          )
                        : null,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
