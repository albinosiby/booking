import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/admission_cubit.dart';
import '../cubit/admission_state.dart';
import '../models/admission_models.dart';
import '../models/admission_overview.dart';
import '../widgets/admission_cards.dart';

/// Plans and their student rosters, scoped to a business and pool/court.
class AdmissionsScreen extends StatefulWidget {
  const AdmissionsScreen({super.key});
  @override
  State<AdmissionsScreen> createState() => _AdmissionsScreenState();
}

class _AdmissionsScreenState extends State<AdmissionsScreen> {
  late final cubit = getIt<AdmissionCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    cubit.loadOverview();
  }

  @override
  void dispose() {
    search.dispose();
    cubit.close();
    super.dispose();
  }

  Future<void> open(String path) async {
    await context.push(path);
    if (mounted) cubit.loadOverview();
  }

  void enroll({AdmissionPlan? plan}) {
    final selection = cubit.state.overview;
    open(
      Uri(
        path: '/admissions/new',
        queryParameters: {
          'kind': selection.coaching ? 'coaching' : 'plans',
          'business_id': ?selection.businessId,
          'space_id': ?selection.spaceId,
          'plan_id': ?plan?.id,
        },
      ).toString(),
    );
  }

  Widget selection(AdmissionState s) {
    final overview = s.overview;
    final business = cubit.overviewBusiness;
    final businessPicker = AppPicker(
      key: const ValueKey('admission-business'),
      label: 'Business',
      value: overview.businessId,
      enabled: !s.loading && s.catalog.businesses.isNotEmpty,
      items: s.catalog.businesses
          .map(
            (b) => PickerItem(
              b.id,
              '${b.name} · ${b.court ? 'Court' : 'Swimming'}',
            ),
          )
          .toList(),
      onChanged: (id) => cubit.selectOverview(businessId: id),
    );
    final spacePicker = AppPicker(
      key: const ValueKey('admission-space'),
      label: business?.spaceLabel ?? 'Pool or court',
      value: overview.spaceId,
      enabled: !s.loading && business?.pools.isNotEmpty == true,
      items:
          business?.pools.map((p) => PickerItem(p.id, p.name)).toList() ?? [],
      onChanged: (id) => cubit.selectOverview(spaceId: id),
    );
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 650
          ? Row(
              children: [
                Expanded(child: businessPicker),
                const SizedBox(width: 16),
                Expanded(child: spacePicker),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                businessPicker,
                const SizedBox(height: 12),
                spacePicker,
              ],
            ),
    );
  }

  Widget filters(AdmissionState s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: search,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search name, phone or admission no.',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            tooltip: 'Clear search',
            onPressed: () {
              search.clear();
              cubit.selectOverview(query: '');
            },
            icon: const Icon(Icons.close),
          ),
        ),
        onSubmitted: (value) => cubit.selectOverview(query: value.trim()),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final status in <String?>[
              null,
              'active',
              'upcoming',
              'completed',
              'expired',
              'cancelled',
            ])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(
                    status == null
                        ? 'All students'
                        : admissionStatusLabel(status),
                  ),
                  selected: s.overview.status == status,
                  onSelected: (_) => cubit.selectOverview(
                    status: status,
                    clearStatus: status == null,
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget roster(AdmissionState s, AdmissionRoster roster) {
    final plan = roster.plan;
    if (plan == null &&
        roster.items.isEmpty &&
        !roster.loading &&
        roster.error == null) {
      return const SizedBox.shrink();
    }
    final filtered = s.overview.query.isNotEmpty || s.overview.status != null;
    return Padding(
      key: ValueKey('roster-${roster.id}'),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (plan != null)
            AdmissionPlanCard(
              key: ValueKey('plan-${plan.id}'),
              plan: plan,
              business: cubit.overviewBusiness!,
              currency: s.catalog.currency,
              onEnroll: s.catalog.canManage ? () => enroll(plan: plan) : null,
              showActiveCount: false,
            )
          else ...[
            Text(
              'Previous plans',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Students whose plans are no longer available for this space.',
            ),
          ],
          const SizedBox(height: 16),
          Text(
            '${roster.items.length}${roster.next != null ? '+' : ''} enrolled ${roster.items.length == 1 ? 'student' : 'students'}${filtered ? ' matching filters' : ''}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          if (roster.loading)
            AppLoadingState(
              initial: roster.items.isEmpty,
              label: 'Loading students…',
            ),
          if (roster.error != null)
            AppErrorWidget(
              message: roster.error!,
              onRetry: () =>
                  cubit.loadRoster(roster.id, more: roster.next != null),
            ),
          if (!roster.loading && roster.error == null && roster.items.isEmpty)
            Text(
              filtered
                  ? 'No students match these filters.'
                  : 'No students enrolled yet.',
            ),
          AppGrid(
            minTileWidth: 320,
            maxColumns: 3,
            children: [
              for (final student in roster.items)
                AdmissionListCard(
                  key: ValueKey('admission-${student.id}'),
                  admission: student,
                  currency: s.catalog.currency,
                  onTap: () => open('/admissions/${student.id}'),
                ),
            ],
          ),
          if (roster.next != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: ValueKey('more-${roster.id}'),
                onPressed: roster.loading
                    ? null
                    : () => cubit.loadRoster(roster.id, more: true),
                icon: const Icon(Icons.expand_more),
                label: const Text('Load more students'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<AdmissionCubit, AdmissionState>(
    bloc: cubit,
    builder: (context, s) {
      final overview = s.overview;
      final current = overview.rosters.values
          .where((r) => r.plan != null)
          .toList();
      return AppPage(
        title: 'Plans & Coaching',
        showAppBar: true,
        compactHeader: true,
        subtitle: 'Choose a pool or court to view plans and enrolled students.',
        back: true,
        scrollId: 'admissions',
        maxWidth: 1240,
        slivers: overview.rosters.isEmpty
            ? null
            : [
                SliverList.builder(
                  itemCount: overview.rosters.length,
                  itemBuilder: (context, index) =>
                      roster(s, overview.rosters.values.elementAt(index)),
                ),
              ],
        actions: [
          IconButton(
            tooltip: 'Refresh admissions',
            onPressed: s.loading ? null : cubit.loadOverview,
            icon: const Icon(Icons.refresh),
          ),
        ],
        floatingActionButton: s.catalog.canManage
            ? FloatingActionButton.extended(
                key: const ValueKey('admissions-new'),
                onPressed: s.loading ? null : enroll,
                tooltip: overview.coaching
                    ? 'New coaching admission'
                    : 'New plan admission',
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('New admission'),
              )
            : null,
        children: [
          SizedBox(
            width: double.infinity,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SegmentedButton<bool>(
                key: const ValueKey('admission-tabs'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Plans')),
                  ButtonSegment(value: true, label: Text('Coaching')),
                ],
                selected: {overview.coaching},
                onSelectionChanged: (v) =>
                    cubit.selectOverview(coaching: v.first),
              ),
            ),
          ),
          const SizedBox(height: 20),
          selection(s),
          const SizedBox(height: 20),
          if (s.loading)
            AppLoadingState(
              initial: overview.rosters.isEmpty,
              label: 'Loading plans…',
            ),
          if (s.error != null)
            AppErrorWidget(message: s.error!, onRetry: cubit.loadOverview),
          if (!s.loading && s.error == null && cubit.overviewSpace == null)
            const AppEmptyState(
              title: 'No spaces available',
              message:
                  'An enabled pool or court is needed to view plans and enroll students.',
            ),
          if (cubit.overviewSpace != null) ...[
            filters(s),
            const SizedBox(height: 24),
            if (!s.loading && current.isEmpty) ...[
              AppEmptyState(
                title: overview.coaching
                    ? 'No coaching plans for this space'
                    : 'No plans for this space',
                message:
                    'Configure a plan in this business’s settings to start enrolling students.',
              ),
              if (s.catalog.owner)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () =>
                        open('/businesses/${overview.businessId}/settings'),
                    icon: const Icon(Icons.tune),
                    label: const Text('Configure plans'),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ],
        ],
      );
    },
  );
}
