import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/admission_cubit.dart';
import '../cubit/admission_state.dart';
import '../widgets/admission_cards.dart';

/// Enrolled students, scoped to Plans/Coaching and a business and pool/court.
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

  void enroll() {
    final selection = cubit.state.overview;
    open(
      Uri(
        path: '/admissions/new',
        queryParameters: {
          'kind': selection.coaching ? 'coaching' : 'plans',
          'business_id': ?selection.businessId,
          'space_id': ?selection.spaceId,
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

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<AdmissionCubit, AdmissionState>(
    bloc: cubit,
    builder: (context, s) {
      final overview = s.overview;
      final students = overview.rosters.values.expand((r) => r.items).toList();
      final loading =
          s.loading || overview.rosters.values.any((r) => r.loading);
      final more = overview.rosters.values.any((r) => r.next != null);
      final errors = overview.rosters.values.where((r) => r.error != null);
      final filtered = overview.query.isNotEmpty || overview.status != null;
      final empty =
          !loading &&
          s.error == null &&
          errors.isEmpty &&
          students.isEmpty &&
          cubit.overviewSpace != null;
      return AppPage(
        title: 'Plans & Coaching',
        showAppBar: true,
        compactHeader: true,
        subtitle: 'Choose a pool or court to view enrolled students.',
        back: true,
        scrollId: 'admissions',
        maxWidth: 1240,
        fillRemaining: empty
            ? IntrinsicHeight(
                child: AppEmptyState(
                  showCard: false,
                  title: filtered
                      ? 'No students match these filters'
                      : 'No students enrolled yet',
                  message: filtered
                      ? 'Try another search or status.'
                      : overview.coaching
                      ? 'Coaching students for this space will appear here.'
                      : 'Students subscribed to plans for this space will appear here.',
                ),
              )
            : null,
        slivers: empty
            ? null
            : [
                SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final columns = (constraints.crossAxisExtent / 336)
                        .floor()
                        .clamp(1, 3);
                    return SliverList.builder(
                      itemCount: (students.length / columns).ceil(),
                      itemBuilder: (context, row) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (
                              var column = 0;
                              column < columns;
                              column++
                            ) ...[
                              if (column > 0) const SizedBox(width: 16),
                              Expanded(
                                child: row * columns + column < students.length
                                    ? AdmissionListCard(
                                        key: ValueKey(
                                          'admission-${students[row * columns + column].id}',
                                        ),
                                        admission:
                                            students[row * columns + column],
                                        currency: s.catalog.currency,
                                        onTap: () => open(
                                          '/admissions/${students[row * columns + column].id}',
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (more)
                  SliverToBoxAdapter(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        key: const ValueKey('admissions-load-more'),
                        onPressed: loading ? null : cubit.loadMoreStudents,
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Load more students'),
                      ),
                    ),
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
              label: 'Loading students…',
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
            Text(
              loading && students.isEmpty
                  ? 'Enrolled students'
                  : '${students.length}${more ? '+' : ''} enrolled ${students.length == 1 ? 'student' : 'students'}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            if (!s.loading && loading)
              AppLoadingState(
                initial: students.isEmpty,
                label: 'Loading students…',
              ),
            if (errors.isNotEmpty)
              AppErrorWidget(
                message: errors.first.error!,
                onRetry: cubit.loadOverview,
              ),
          ],
        ],
      );
    },
  );
}
