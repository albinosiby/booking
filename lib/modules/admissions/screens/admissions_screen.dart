import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/admission_cubit.dart';
import '../cubit/admission_state.dart';
import '../models/admission_overview.dart';
import '../widgets/admission_cards.dart';
import '../widgets/admission_filters_sheet.dart';

/// Enrolled students across permitted locations, with optional location filters.
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

  Future<void> filterStudents() async {
    final overview = cubit.state.overview;
    final result = await showAdaptiveSheet<AdmissionFilterSelection>(
      context: context,
      scrollable: false,
      showClose: false,
      builder: (_) => AdmissionFiltersSheet(
        businesses: cubit.state.catalog.businesses,
        initial: AdmissionFilterSelection(
          businessId: overview.businessId,
          spaceId: overview.spaceId,
          status: overview.status,
        ),
      ),
    );
    if (!mounted || result == null) return;
    cubit.selectOverview(
      businessId: result.businessId,
      spaceId: result.spaceId,
      clearSelection: result.businessId == null,
      clearSpace: result.spaceId == null,
      status: result.status,
      clearStatus: result.status == null,
    );
  }

  Widget searchField() => TextField(
    key: const ValueKey('admission-search'),
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
  );

  Widget appliedFilters(AdmissionState s) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (cubit.overviewBusiness != null)
        InputChip(
          label: Text(cubit.overviewBusiness!.name),
          onDeleted: () => cubit.selectOverview(clearSelection: true),
        ),
      if (cubit.overviewSpace != null)
        InputChip(
          label: Text(cubit.overviewSpace!.name),
          onDeleted: () => cubit.selectOverview(clearSpace: true),
        ),
      if (s.overview.status != null)
        InputChip(
          label: Text(admissionStatusLabel(s.overview.status!)),
          onDeleted: () => cubit.selectOverview(clearStatus: true),
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
      final filterCount = [
        overview.businessId,
        overview.spaceId,
        overview.status,
      ].where((value) => value != null).length;
      final filtered = overview.query.isNotEmpty || filterCount > 0;
      final empty =
          !loading && s.error == null && errors.isEmpty && students.isEmpty;
      return AppPage(
        title: 'Plans & Coaching',
        showAppBar: true,
        compactHeader: true,
        subtitle: 'Manage enrolled students, plans and coaching.',
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
                      ? 'Try another search or adjust your filters.'
                      : overview.coaching
                      ? 'Students enrolled in coaching will appear here.'
                      : 'Students enrolled in plans will appear here.',
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
            tooltip: 'Filter admissions',
            onPressed: s.loading ? null : filterStudents,
            icon: Badge(
              isLabelVisible: filterCount > 0,
              label: Text('$filterCount'),
              child: const Icon(Icons.filter_list),
            ),
          ),
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
          searchField(),
          const SizedBox(height: 16),
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
          if (filterCount > 0) ...[
            const SizedBox(height: 16),
            appliedFilters(s),
          ],
          const SizedBox(height: 24),
          if (s.loading)
            AppLoadingState(
              initial: overview.rosters.isEmpty,
              label: 'Loading students…',
            ),
          if (s.error != null)
            AppErrorWidget(message: s.error!, onRetry: cubit.loadOverview),
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
      );
    },
  );
}
