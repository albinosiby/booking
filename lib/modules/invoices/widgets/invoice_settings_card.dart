import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../design_system/design_system.dart';
import '../cubit/invoice_cubits.dart';
import '../models/invoice_models.dart';

/// Owner switch on the payment settings page. Invoice generation is on by default.
class InvoiceSettingsCard extends StatelessWidget {
  const InvoiceSettingsCard({super.key, required this.cubit});
  final InvoiceSettingsCubit cubit;
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<InvoiceSettingsCubit, InvoiceSettingsModel>(
    bloc: cubit,
    builder: (context, s) => AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const ValueKey('invoice-toggle'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Generate invoices',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            subtitle: const Text(
              'Lets your team download and share a PDF invoice from each booking. It shows the customer, booking, amount paid, balance due, and your bank and UPI payment details. Every invoice is kept in the booking history.',
            ),
            value: s.enabled,
            onChanged: s.loaded && !s.busy ? cubit.toggle : null,
          ),
          if (s.busy) const LinearProgressIndicator(),
          if (s.error != null)
            AppErrorWidget(
              message: s.error!,
              onRetry: s.loaded ? null : cubit.load,
            ),
        ],
      ),
    ),
  );
}

/// Creates and loads its cubit once.
class InvoiceSettingsSection extends StatefulWidget {
  const InvoiceSettingsSection({super.key, required this.create});
  final InvoiceSettingsCubit Function() create;
  @override
  State<InvoiceSettingsSection> createState() => _InvoiceSettingsSectionState();
}

class _InvoiceSettingsSectionState extends State<InvoiceSettingsSection> {
  late final cubit = widget.create()..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InvoiceSettingsCard(cubit: cubit);
}
