import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import '../../../utils/services/logo_picker_service.dart';
import '../repositories/website_payment_repository.dart';
import '../cubit/accounts_cubits.dart' show financeError;

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
  LogoSelection? qr;
  int version = 0;
  bool loading = true, saving = false;
  bool loaded = false;
  String? error, success;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    upi.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final details = await widget.repository.websitePayments();
      if (!mounted) return;
      upi.text = details.upiId;
      setState(() {
        version = details.version;
        qr = details.qr;
        loaded = true;
      });
    } catch (failure) {
      if (mounted) setState(() => error = financeError(failure));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> pick() async {
    setState(() {
      saving = true;
      error = null;
      success = null;
    });
    try {
      final image =
          await (widget.pickImage?.call() ?? LogoPickerService().pick());
      if (!mounted || image == null) return;
      if (image.bytes.length > 1024 * 1024) {
        setState(() => error = 'Choose a QR image up to 1 MB.');
      } else {
        setState(() => qr = image);
      }
    } catch (failure) {
      if (mounted) setState(() => error = financeError(failure));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> save() async {
    if (saving || !(form.currentState?.validate() ?? false)) return;
    setState(() {
      saving = true;
      error = null;
      success = null;
    });
    try {
      final result = await widget.repository.saveWebsitePayments(
        version,
        upi.text,
        qr,
      );
      if (!mounted) return;
      setState(() {
        version = result.version;
        success = 'Website payment details saved.';
      });
    } catch (failure) {
      if (mounted) setState(() => error = financeError(failure));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppCard(
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
          if (loading)
            const LinearProgressIndicator()
          else ...[
            if (error != null) AppErrorWidget(message: error!, onRetry: load),
            TextFormField(
              controller: upi,
              enabled: !saving,
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
            if (qr != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Image.memory(
                  qr!.bytes,
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                  semanticLabel: 'Payment QR code',
                  errorBuilder: (_, _, _) => const Text(
                    'Cannot preview this image. Choose a valid QR image.',
                  ),
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: saving ? null : pick,
                  icon: const Icon(Icons.qr_code),
                  label: Text(
                    qr == null ? 'Upload QR code' : 'Replace QR code',
                  ),
                ),
                if (qr != null)
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => setState(() {
                            qr = null;
                            success = null;
                          }),
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
                onPressed: saving || !loaded ? null : save,
                child: Text(saving ? 'Saving…' : 'Save payment details'),
              ),
            ),
            if (success != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(success!),
              ),
          ],
        ],
      ),
    ),
  );
}
