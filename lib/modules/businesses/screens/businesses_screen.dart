import '../cubit/businesses_cubit.dart';
import '../../../config/routes/routes.dart';
import '../models/businesses_screen_model.dart';
import '../../../di/injection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../utils/helpers/validation.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../../workspace/models/workspace.dart';
import '../widgets/business_icon.dart';

class BusinessesScreen extends StatefulWidget {
  const BusinessesScreen({super.key, this.onboarding = false});
  final bool onboarding;
  @override
  State<BusinessesScreen> createState() => _BusinessesScreenState();
}

class _BusinessesScreenState extends State<BusinessesScreen> {
  late final cubit = getIt<BusinessesCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  final form = GlobalKey<FormState>();
  late final names = {
    for (final type in BusinessType.values)
      type: TextEditingController(text: cubit.state.names[type]),
  };
  @override
  void dispose() {
    for (final controller in names.values) {
      controller.dispose();
    }
    cubit.close();
    super.dispose();
  }

  Widget serviceCard(
    BuildContext context,
    BusinessType type,
    BusinessesScreenModel state,
  ) {
    final selected = state.selected.contains(type);
    final theme = Theme.of(context);
    void toggle() => cubit.toggleService(type);
    return Semantics(
      key: ValueKey('service-card-${type.code}'),
      button: true,
      selected: selected,
      enabled: !state.disabled,
      label: type.label,
      onTap: state.disabled ? null : toggle,
      child: ExcludeSemantics(
        child: Material(
          color: selected
              ? AppColors.lime.withValues(alpha: .12)
              : theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: selected
                  ? AppColors.lime
                  : theme.colorScheme.outline.withValues(alpha: .4),
              width: selected ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: state.disabled ? null : toggle,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        businessIcon(type),
                        size: 28,
                        color: selected
                            ? AppColors.lime
                            : theme.colorScheme.onSurface,
                      ),
                      const Spacer(),
                      Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 22,
                        color: selected
                            ? AppColors.lime
                            : theme.colorScheme.outline,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(type.label, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    selected ? 'Selected' : 'Tap to select',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<BusinessesCubit, BusinessesScreenModel>(
    bloc: cubit,
    builder: (c, s) => AppPage(
      back: !widget.onboarding,
      eyebrow: widget.onboarding ? 'STEP 2 OF 2' : 'ORGANIZATION SETTINGS',
      title: widget.onboarding ? 'What do\nyou operate?' : 'Add businesses',
      subtitle:
          'Select your services and name each business. Configure spaces and pricing after adding them.',
      children: [
        if (!s.data.isOwner)
          const AppErrorWidget(message: 'Only the owner can add businesses.')
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
              final columns = constraints.maxWidth < 300 || largeText
                  ? 1
                  : constraints.maxWidth >= 600
                  ? 3
                  : 2;
              final width =
                  (constraints.maxWidth - 12 * (columns - 1)) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: BusinessType.values
                    .map(
                      (type) => SizedBox(
                        width: width,
                        child: serviceCard(context, type, s),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          if (s.selected.isNotEmpty)
            Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Name your selected businesses',
                    style: Theme.of(c).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Keep the suggested names or enter your own.'),
                  const SizedBox(height: 18),
                  ...BusinessType.values
                      .where(s.selected.contains)
                      .map(
                        (type) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: AppTextField(
                            key: ValueKey('business-name-${type.code}'),
                            label: '${type.label} name',
                            controller: names[type]!,
                            enabled: !s.disabled,
                            validator: Validation.name,
                            onChanged: (name) => cubit.nameService(type, name),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          AppButton(
            label: s.selected.isEmpty
                ? 'Add selected businesses'
                : 'Add selected businesses (${s.selected.length})',
            icon: Icons.add,
            busy: s.adding,
            onPressed: s.selected.isEmpty || s.disabled
                ? null
                : () async {
                    if (form.currentState?.validate() != true) return;
                    final saved = await cubit.addSelected();
                    if (saved && c.mounted && !widget.onboarding) {
                      if (c.canPop()) {
                        c.pop();
                      } else {
                        c.go(Routes.businesses);
                      }
                    }
                  },
          ),
        ],
        const SizedBox(height: 28),
        Text(
          'Your businesses · ${s.data.businesses.length}',
          style: Theme.of(c).textTheme.titleMedium,
        ),
        const SizedBox(height: 14),
        ...s.data.businesses.map(
          (b) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              child: Row(
                children: [
                  Icon(businessIcon(b.type), color: AppColors.lime),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.name, style: Theme.of(c).textTheme.titleMedium),
                        Text(b.type.label),
                        const SizedBox(height: 6),
                        Text(
                          b.ready ? 'Ready' : 'Setup needed',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (s.error != null) AppErrorWidget(message: s.error!),
        const SizedBox(height: 20),
        AppButton(
          label: widget.onboarding ? 'Continue to Home' : 'Back to businesses',
          icon: Icons.arrow_forward,
          onPressed: s.data.businesses.isEmpty || s.disabled
              ? null
              : () => widget.onboarding
                    ? c.go('/home')
                    : c.canPop()
                    ? c.pop()
                    : c.go(Routes.businesses),
        ),
      ],
    ),
  );
}
