import '../models/business_draft.dart';
import '../cubit/resource_setup_cubit.dart';
import '../models/resource_setup_screen_model.dart';
import '../../../di/injection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../utils/helpers/validation.dart';
import '../../../utils/helpers/time_format.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../../workspace/models/workspace.dart';

class ResourceSetupScreen extends StatefulWidget {
  const ResourceSetupScreen({super.key, required this.businessId});
  final String businessId;
  @override
  State<ResourceSetupScreen> createState() => _ResourceSetupScreenState();
}

class _ResourceSetupScreenState extends State<ResourceSetupScreen> {
  late final cubit = getIt<ResourceSetupCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.businessId,
  );
  final resourceForm = GlobalKey<FormState>(),
      rulesForm = GlobalKey<FormState>();
  final resourceName = TextEditingController(),
      capacity = TextEditingController(text: '1'),
      price = TextEditingController(),
      buffer = TextEditingController(text: '0'),
      plan = TextEditingController(text: 'Monthly swimming plan'),
      validity = TextEditingController(text: '30'),
      limit = TextEditingController(text: '25');
  bool initialized = false;
  int get step => cubit.state.step;
  int get duration => cubit.state.duration;
  TimeOfDay get opens => parseTime(cubit.state.opens);
  TimeOfDay get closes => parseTime(cubit.state.closes);
  Set<int> get days => cubit.state.days;
  String get entitlement => cubit.state.entitlement;
  String timeString(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  TimeOfDay parseTime(String s) => TimeOfDay(
    hour: int.parse(s.split(':')[0]),
    minute: int.parse(s.split(':')[1]),
  );
  @override
  void dispose() {
    for (final c in [
      resourceName,
      capacity,
      price,
      buffer,
      plan,
      validity,
      limit,
    ]) {
      c.dispose();
    }
    cubit.close();
    super.dispose();
  }

  void initialize(Business b) {
    if (initialized) return;
    initialized = true;
    final config = b.configuration;
    if (config != null) {
      price.text = ((config['price_minor'] as num) / 100).toStringAsFixed(2);
      buffer.text = '${config['buffer_minutes']}';
      plan.text = config['plan_name'] ?? plan.text;
      validity.text = '${config['validity_days'] ?? 30}';
      limit.text = '${config['visit_limit'] ?? 25}';
    }
  }

  Future<void> pickTime(bool opening) async {
    final time = await showAppTimePicker(
      context: context,
      initialTime: opening ? cubit.state.opens : cubit.state.closes,
    );
    if (time != null && mounted) {
      cubit.selectHours(
        opens: opening ? time : null,
        closes: opening ? null : time,
      );
    }
  }

  Future<void> saveRules(Business b) async {
    if (!rulesForm.currentState!.validate()) return;
    if (days.isEmpty) {
      showMessage(context, 'Choose at least one operating day.');
      return;
    }
    if (opens == closes) {
      showMessage(context, 'Opening and closing times must differ.');
      return;
    }
    final pool = b.type == BusinessType.pool;
    final config = BusinessConfiguration(
      version: b.version,
      opensAt: timeString(opens),
      closesAt: timeString(closes),
      days: days.toList()..sort(),
      durationMinutes: duration,
      priceMinor: Validation.priceMinor(price.text)!,
      bufferMinutes: pool ? 0 : int.parse(buffer.text),
      planName: pool ? plan.text.trim() : null,
      validityDays: pool ? int.parse(validity.text) : null,
      entitlement: pool ? entitlement : null,
      visitLimit: pool && entitlement != 'unlimited'
          ? int.parse(limit.text)
          : null,
    );
    final ok = await cubit.configure(b.id, config);
    if (ok && mounted) cubit.selectStep(2);
  }

  String? positive(String? v) =>
      int.tryParse(v ?? '') == null || int.parse(v!) < 1
      ? 'Enter a positive whole number'
      : null;
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<ResourceSetupCubit, ResourceSetupScreenModel>(
    bloc: cubit,
    builder: (c, s) {
      final b = s.data.businesses
          .where((b) => b.id == widget.businessId)
          .firstOrNull;
      if (b == null) {
        return const AppPage(
          back: true,
          title: 'Business unavailable',
          children: [
            AppEmptyState(
              title: 'Business not found',
              message: 'Return Home and select an accessible business.',
            ),
          ],
        );
      }
      if (!s.data.isOwner) {
        return const AppPage(
          back: true,
          title: 'Owner access required',
          children: [],
        );
      }
      initialize(b);
      final pool = b.type == BusinessType.pool,
          hall = b.type == BusinessType.hall;
      final location = s.data.locations
          .where((l) => l['id'] == b.locationId)
          .firstOrNull;
      final desktop = isDesktopWidth(c);
      void openStep(int index) {
        if (index == 2 && b.configuration == null) {
          showMessage(c, 'Save rules and pricing before reviewing.');
          return;
        }
        cubit.selectStep(index);
      }

      final body = <Widget>[
        if (!desktop) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['Resources', 'Rules & pricing', 'Review']
                .asMap()
                .entries
                .map(
                  (entry) => ChoiceChip(
                    label: Text('${entry.key + 1}. ${entry.value}'),
                    selected: step == entry.key,
                    onSelected: s.busy ? null : (_) => openStep(entry.key),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 22),
        ],
        if (s.error != null) ...[
          AppErrorWidget(message: s.error!),
          const SizedBox(height: 16),
        ],
        if (step == 0) ...[
          AppCard(
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, color: AppColors.lime),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${location?['name'] ?? 'Location'} · ${location?['city'] ?? ''}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            pool
                ? 'Your pools'
                : hall
                ? 'Your halls'
                : 'Your playing spaces',
            style: Theme.of(c).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          ...b.resources.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${r.name}${pool || hall ? ' · capacity ${r.capacity}' : ''}',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove resource',
                      onPressed: s.busy
                          ? null
                          : () async {
                              if (await confirmAction(
                                c,
                                'Remove ${r.name}?',
                                'This will return the business to setup status.',
                              )) {
                                if (!c.mounted) return;
                                await cubit.removeResource(b.id, r.id);
                              }
                            },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Form(
            key: resourceForm,
            child: Column(
              children: [
                AppTextField(
                  label: 'Resource name',
                  controller: resourceName,
                  hint: pool
                      ? 'Pool 1'
                      : hall
                      ? 'Hall 1'
                      : b.type == BusinessType.turf
                      ? 'Turf 1'
                      : 'Court A',
                  validator: Validation.required,
                ),
                if (pool || hall) ...[
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Capacity',
                    controller: capacity,
                    keyboardType: TextInputType.number,
                    validator: positive,
                  ),
                ],
                const SizedBox(height: 16),
                AppButton(
                  label: 'Add resource',
                  icon: Icons.add,
                  secondary: true,
                  busy: s.busy,
                  onPressed: () async {
                    if (!resourceForm.currentState!.validate()) return;
                    final ok = await cubit.addResource(
                      b.id,
                      ResourceDraft(
                        name: resourceName.text.trim(),
                        capacity: pool || hall ? int.parse(capacity.text) : 1,
                      ),
                    );
                    if (ok && mounted) resourceName.clear();
                  },
                ),
              ],
            ),
          ),
        ],
        if (step == 1) ...[
          Form(
            key: rulesForm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Operating days',
                  style: Theme.of(c).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                      .asMap()
                      .entries
                      .map(
                        (e) => FilterChip(
                          label: Text(e.value),
                          selected: days.contains(e.key + 1),
                          onSelected: (v) => cubit.selectDay(e.key + 1, v),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => pickTime(true),
                        child: Text(
                          'Opens ${TimeFormat.display(cubit.state.opens)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => pickTime(false),
                        child: Text(
                          'Closes ${TimeFormat.display(cubit.state.closes)}',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Timezone: ${location?['timezone'] ?? ''}. A closing time before opening means the next day.',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 20),
                if (pool) ...[
                  AppTextField(
                    label: 'Plan name',
                    controller: plan,
                    validator: Validation.name,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Validity · calendar days',
                    controller: validity,
                    keyboardType: TextInputType.number,
                    validator: positive,
                  ),
                  const SizedBox(height: 16),
                  AppPicker(
                    label: 'Visit entitlement',
                    items: const [
                      PickerItem('unlimited', 'Unlimited visits'),
                      PickerItem('visits', 'Limited visits'),
                      PickerItem('attendance_days', 'Limited attendance days'),
                    ],
                    value: entitlement,
                    onChanged: (v) => cubit.selectEntitlement(v),
                  ),
                  if (entitlement != 'unlimited') ...[
                    const SizedBox(height: 16),
                    AppTextField(
                      label: entitlement == 'visits'
                          ? 'Number of visits'
                          : 'Number of attendance days',
                      controller: limit,
                      keyboardType: TextInputType.number,
                      validator: positive,
                    ),
                  ],
                  const SizedBox(height: 16),
                  const AppCard(
                    child: Text(
                      'A subscription grants access. It does not reserve an hourly pool slot.',
                    ),
                  ),
                ] else ...[
                  AppPicker(
                    label: hall ? 'Booking period' : 'Booking duration',
                    items: (hall ? [720, 1440] : [30, 60, 90, 120])
                        .map(
                          (n) => PickerItem(
                            '$n',
                            hall
                                ? (n == 720 ? 'Half day' : 'Full day')
                                : '$n minutes',
                          ),
                        )
                        .toList(),
                    value: '$duration',
                    onChanged: (v) => cubit.selectDuration(int.parse(v)),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Buffer between bookings · minutes',
                    controller: buffer,
                    keyboardType: TextInputType.number,
                    validator: (v) =>
                        int.tryParse(v ?? '') == null ||
                            int.parse(v!) < 0 ||
                            int.parse(v) > 240
                        ? 'Enter 0–240 minutes'
                        : null,
                  ),
                ],
                const SizedBox(height: 16),
                AppTextField(
                  label:
                      '${pool ? 'Plan price' : 'Booking price'} · ${s.data.organization!.currency}',
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    final amount = Validation.priceMinor(v ?? '');
                    return amount == null || amount > 100000000
                        ? 'Enter a valid amount with up to two decimal places'
                        : null;
                  },
                ),
                if (!desktop) const SizedBox(height: 24),
              ],
            ),
          ),
        ],
        if (step == 2) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _review('Business', b.name),
                _review('Location', '${location?['name']}'),
                _review('Resources', b.resources.map((r) => r.name).join(', ')),
                _review(
                  'Product',
                  pool
                      ? '${b.configuration?['plan_name']}'
                      : hall
                      ? '${b.configuration?['duration_minutes']} minutes'
                      : '${b.configuration?['duration_minutes']} minutes per booking',
                ),
                _review(
                  'Price',
                  '${s.data.organization!.currency} ${((b.configuration?['price_minor'] ?? 0) / 100).toStringAsFixed(2)}',
                ),
                _review(
                  'Operating hours',
                  '${TimeFormat.display(b.configuration?['opens_at'] ?? '')} – ${TimeFormat.display(b.configuration?['closes_at'] ?? '')}',
                ),
                if (pool)
                  _review(
                    'Plan entitlement',
                    '${b.configuration?['validity_days']} calendar days · ${b.configuration?['entitlement']}${b.configuration?['visit_limit'] == null ? '' : ' · ${b.configuration?['visit_limit']}'}',
                  ),
                const Text(
                  'You can operate this business yourself and invite staff later.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ];
      final footer = <Widget>[
        if (step == 0) ...[
          if (!desktop) const SizedBox(height: 24),
          AppButton(
            label: 'Continue to rules',
            onPressed: b.resources.isEmpty || s.busy
                ? null
                : () => cubit.selectStep(1),
          ),
        ],
        if (step == 1)
          AppButton(
            label: 'Save and review',
            icon: Icons.arrow_forward,
            busy: s.busy,
            onPressed: () => saveRules(b),
          ),
        if (step == 2) ...[
          if (!desktop) const SizedBox(height: 24),
          AppButton(
            label: 'Activate business',
            icon: Icons.check,
            busy: s.busy,
            onPressed: b.resources.isEmpty || b.configuration == null
                ? null
                : () async {
                    final ok = await cubit.activate(b.id);
                    if (ok && c.mounted) {
                      c.go('/home');
                      showMessage(c, '${b.name} is ready.');
                    }
                  },
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Assign staff',
            secondary: true,
            onPressed: () => c.push('/team/invite'),
          ),
        ],
      ];
      return AppPage(
        back: true,
        eyebrow: b.type.label,
        title: b.name,
        subtitle: 'Set up your spaces, products and operating rules.',
        maxWidth: desktop ? 1200 : 620,
        children: desktop
            ? [
                ConfigurationWorkspace(
                  businessName: b.name,
                  kind: b.type.label,
                  ready: b.ready,
                  sections: [
                    for (final (index, (name, label, subtitle, icon)) in [
                      (
                        'resources',
                        'Resources',
                        '${b.resources.length} ${b.resources.length == 1 ? 'resource' : 'resources'}',
                        Icons.view_module_outlined,
                      ),
                      (
                        'rules',
                        'Rules & pricing',
                        b.configuration == null
                            ? 'Days, hours, duration and price'
                            : 'Saved · edit days, hours and price',
                        Icons.schedule_outlined,
                      ),
                      (
                        'review',
                        'Review',
                        b.ready
                            ? 'Review saved settings'
                            : 'Check details and activate',
                        Icons.fact_check_outlined,
                      ),
                    ].indexed)
                      ConfigurationNavItem(
                        key: ValueKey('resource-nav-$name'),
                        label: '${index + 1}. $label',
                        subtitle: subtitle,
                        icon: icon,
                        selected: step == index,
                        onTap: s.busy ? null : () => openStep(index),
                      ),
                  ],
                  content: body,
                  actions: footer,
                ),
              ]
            : [...body, ...footer],
      );
    },
  );
  Widget _review(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
