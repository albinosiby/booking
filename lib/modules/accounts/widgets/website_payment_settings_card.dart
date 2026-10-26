import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import '../../../utils/services/logo_picker_service.dart';
import '../repositories/website_payment_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubit/website_payment_settings_cubit.dart';
import '../models/website_payment_settings_model.dart';
import '../repositories/website_payment_qr_repository.dart';

class WebsitePaymentSettingsCard extends StatefulWidget {
  const WebsitePaymentSettingsCard({
    super.key,
    required this.repository,
    this.pickImage,
  });
  final WebsitePaymentRepository repository;
  final Future<LogoSelection?> Function()? pickImage;
  @override
  State<WebsitePaymentSettingsCard> createState() =>
      _WebsitePaymentSettingsCardState();
}

class _WebsitePaymentSettingsCardState
    extends State<WebsitePaymentSettingsCard> {
  final upi = TextEditingController();
  final form = GlobalKey<FormState>();
  late final cubit = WebsitePaymentSettingsCubit(
    widget.repository,
    DeviceWebsitePaymentQrRepository(picker: widget.pickImage),
  );
  @override
  void initState() {
    super.initState();
    upi.addListener(edited);
    cubit.load();
  }

  void edited() => cubit.upiChanged(upi.text);
  @override
  void dispose() {
    upi.removeListener(edited);
    upi.dispose();
    cubit.close();
    super.dispose();
  }

  void save() {
    if (form.currentState?.validate() ?? false) cubit.save();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<WebsitePaymentSettingsCubit, WebsitePaymentSettingsModel>(
    bloc: cubit,
    listener: (_, state) {
      if (upi.text != state.upiId) upi.text = state.upiId;
    },
    builder: (context, s) => AppCard(
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Website payment details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Customers see these details at web checkout. Make sure the QR code and UPI ID belong to the same account. Transaction IDs are not proof of payment; verify your bank before recording a collection.',
            ),
            const SizedBox(height: 16),
            if (s.loading)
              const LinearProgressIndicator()
            else ...[
              if (s.error != null)
                AppErrorWidget(
                  message: s.error!,
                  onRetry: s.saved == null ? cubit.load : null,
                ),
              if (s.picking) const LinearProgressIndicator(),
              TextFormField(
                controller: upi,
                enabled: !s.busy && s.saved != null,
                maxLength: 100,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'UPI ID',
                  hintText: 'venue@bank',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ||
                        RegExp(
                          r'^[A-Za-z0-9._-]{2,}@[A-Za-z0-9.-]{2,}$',
                        ).hasMatch(value!.trim())
                    ? null
                    : 'Enter a valid UPI ID.',
              ),
              const SizedBox(height: 12),
              if (s.qr != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    key: const ValueKey('payment-qr-preview'),
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Image.memory(
                      s.qr!.bytes,
                      width: 200,
                      height: 200,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      semanticLabel: 'Payment QR code',
                      errorBuilder: (_, _, _) => const SizedBox(
                        width: 200,
                        height: 200,
                        child: Center(
                          child: Text(
                            'Cannot preview this image. Choose another QR image.',
                            style: TextStyle(color: Colors.black87),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: s.busy || s.saved == null ? null : cubit.pick,
                    icon: const Icon(Icons.qr_code),
                    label: Text(
                      s.picking
                          ? 'Choosing QR image…'
                          : s.qr == null
                          ? 'Upload QR code'
                          : 'Replace QR code',
                    ),
                  ),
                  if (s.qr != null)
                    TextButton(
                      onPressed: s.busy ? null : cubit.removeQr,
                      child: const Text('Remove QR code'),
                    ),
                ],
              ),
              const Text(
                'PNG, JPEG or WebP · up to 1 MB. Save to publish changes.',
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: s.canSave ? save : null,
                  child: Text(s.saving ? 'Saving…' : 'Save payment details'),
                ),
              ),
              if (s.success != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(s.success!),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}
