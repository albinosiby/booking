import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/admission_cubit.dart';
import '../cubit/admission_state.dart';
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

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<AdmissionCubit, AdmissionState>(
        bloc: cubit,
        builder: (context, s) {
          defaultKind(s);
          final available = kinds(s);
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
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Admissions')),
                  ButtonSegment(value: true, label: Text('Plans')),
                ],
                selected: {plans},
                onSelectionChanged: (v) => setState(() => plans = v.first),
              ),
              SizedBox(height: 12.h),
              if (available.length > 1 || s.kind != available.first)
                Wrap(
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
                ),
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
}
