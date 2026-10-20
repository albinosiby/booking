import '../models/organization_draft.dart';
import '../cubit/organization_cubit.dart';
import '../models/organization_screen_model.dart';
import 'dart:typed_data';
import '../../../utils/services/logo_picker_service.dart';
import '../../../utils/exceptions/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../../utils/helpers/validation.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/location_catalog_cubit.dart';

class OrganizationScreen extends StatefulWidget {
  const OrganizationScreen({super.key});
  @override
  State<OrganizationScreen> createState() => _OrganizationScreenState();
}

class _OrganizationScreenState extends State<OrganizationScreen> {
  late final cubit = getIt<OrganizationCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  final form = GlobalKey<FormState>();
  final org = TextEditingController(),
      phone = TextEditingController(),
      location = TextEditingController(),
      line1 = TextEditingController(),
      line2 = TextEditingController(),
      city = TextEditingController(),
      postal = TextEditingController();
  late final LocationCatalogCubit catalog = getIt<LocationCatalogCubit>()
    ..load();
  String? get stateCode => cubit.state.stateCode;
  String get timezone => cubit.state.timezone;
  String get currency => cubit.state.currency;
  Uint8List? get logo => cubit.state.logo;
  String? get logoType => cubit.state.logoType;
  @override
  void dispose() {
    for (final c in [org, phone, location, line1, line2, city, postal]) {
      c.dispose();
    }
    catalog.close();
    cubit.close();
    super.dispose();
  }

  Future<void> pickLogo() async {
    try {
      final selection = await getIt<LogoPickerService>().pick();
      if (!mounted || selection == null) return;
      cubit.selectLogo(selection.bytes, selection.contentType);
    } on AppException catch (error) {
      if (mounted) showMessage(context, error.message);
    }
  }

  Future<void> save(LocationCatalogState geo) async {
    if (geo.busy || geo.error != null || !form.currentState!.validate()) return;
    final data = OrganizationDraft(
      name: org.text.trim(),
      phone: phone.text.trim(),
      currency: currency,
      location: LocationDraft(
        name: location.text.trim(),
        line1: line1.text.trim(),
        line2: line2.text.trim().isEmpty ? null : line2.text.trim(),
        city: city.text.trim(),
        stateCode: stateCode,
        countryCode: geo.country,
        postalCode: postal.text.trim(),
        timezone: timezone,
      ),
    );
    final bytes = logo, type = logoType;
    final ok = await cubit.create(data);
    if (ok && bytes != null && type != null) {
      await cubit.uploadLogo(bytes, type);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<LocationCatalogCubit, LocationCatalogState>(
    bloc: catalog,
    builder: (context, geo) =>
        BlocBuilder<OrganizationCubit, OrganizationScreenModel>(
          bloc: cubit,
          builder: (context, s) => AppPage(
            eyebrow: 'STEP 1 OF 2',
            title: 'Meet your\norganization.',
            subtitle:
                'Name your organization, then add the property or branch where its businesses operate. Businesses at the same property share this address.',
            children: [
              AppCard(
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: logo == null
                          ? Container(
                              width: 54,
                              height: 54,
                              color: Theme.of(context).scaffoldBackgroundColor,
                              child: const Icon(
                                Icons.add_photo_alternate_outlined,
                                color: AppColors.lime,
                              ),
                            )
                          : Image.memory(
                              logo!,
                              width: 54,
                              height: 54,
                              fit: BoxFit.cover,
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Organization logo · optional'),
                          TextButton(
                            onPressed: s.busy ? null : pickLogo,
                            child: Text(
                              logo == null ? 'Choose image' : 'Change image',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (geo.error != null) ...[
                AppErrorWidget(message: geo.error!, onRetry: catalog.load),
                const SizedBox(height: 16),
              ],
              Form(
                key: form,
                child: Column(
                  children: [
                    AppTextField(
                      label: 'Organization name',
                      hint: 'For example, Eden’s Area',
                      controller: org,
                      validator: Validation.name,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'Contact number',
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      validator: (v) => v == null || v.trim().length < 6
                          ? 'Enter a valid contact number'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'Property / branch name',
                      hint: 'For example, Eden’s Area, Kochi',
                      controller: location,
                      validator: Validation.name,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'Address line 1',
                      controller: line1,
                      validator: Validation.name,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'Address line 2 · optional',
                      controller: line2,
                    ),
                    const SizedBox(height: 16),
                    AppPicker(
                      label: 'Country',
                      items: geo.countries
                          .map((o) => PickerItem(o.code, o.name))
                          .toList(),
                      value: geo.country,
                      enabled: !geo.busy,
                      required: true,
                      onChanged: (v) {
                        cubit.selectState(null);
                        catalog.selectCountry(v);
                      },
                    ),
                    const SizedBox(height: 16),
                    if (geo.busy)
                      const AppRefreshIndicator(label: 'Loading locations…'),
                    if (geo.states.isNotEmpty) ...[
                      AppPicker(
                        key: ValueKey(geo.country),
                        label: 'State / province',
                        items: geo.states
                            .map((o) => PickerItem(o.code, o.name))
                            .toList(),
                        value: stateCode,
                        required: true,
                        onChanged: (v) => cubit.selectState(v),
                      ),
                      const SizedBox(height: 16),
                    ],
                    AppTextField(
                      label: 'City',
                      controller: city,
                      validator: Validation.name,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'Pincode / postal code',
                      controller: postal,
                      validator: (v) =>
                          geo.country == 'IN' &&
                              !RegExp(r'^[1-9]\d{5}$').hasMatch(v?.trim() ?? '')
                          ? 'Enter a six-digit Indian pincode'
                          : Validation.required(v),
                    ),
                    const SizedBox(height: 16),
                    AppPicker(
                      label: 'Timezone',
                      items: geo.timezones
                          .map((v) => PickerItem(v, v))
                          .toList(),
                      value: timezone,
                      required: true,
                      onChanged: (v) => cubit.selectTimezone(v),
                    ),
                    const SizedBox(height: 16),
                    AppPicker(
                      label: 'Currency',
                      items: const [
                        PickerItem('INR', 'INR · Indian rupee'),
                        PickerItem('AED', 'AED · UAE dirham'),
                        PickerItem('GBP', 'GBP · British pound'),
                        PickerItem('USD', 'USD · US dollar'),
                        PickerItem('EUR', 'EUR · Euro'),
                      ],
                      value: currency,
                      required: true,
                      onChanged: (v) => cubit.selectCurrency(v),
                    ),
                    const SizedBox(height: 24),
                    if (s.error != null) ...[
                      AppErrorWidget(message: s.error!),
                      const SizedBox(height: 16),
                    ],
                    AppButton(
                      label: 'Continue',
                      icon: Icons.arrow_forward,
                      busy: s.busy,
                      onPressed: geo.busy || geo.error != null
                          ? null
                          : () => save(geo),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
  );
}
