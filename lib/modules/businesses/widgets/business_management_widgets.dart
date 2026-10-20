import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../utils/helpers/validation.dart';
import '../../workspace/models/workspace.dart';

String businessSettingsPath(Business b) =>
    '/businesses/${b.id}/${b.ready ? 'settings' : 'setup'}';
String businessStatus(Business b) => switch (b.status) {
  'ready' => 'Ready',
  'paused' => 'Paused',
  _ => 'Setup needed',
};

Future<String?> editBusinessName(BuildContext context, Business business) =>
    showDialog<String>(
      context: context,
      builder: (_) => _BusinessNameDialog(name: business.name),
    );

class _BusinessNameDialog extends StatefulWidget {
  const _BusinessNameDialog({required this.name});
  final String name;
  @override
  State<_BusinessNameDialog> createState() => _BusinessNameDialogState();
}

class _BusinessNameDialogState extends State<_BusinessNameDialog> {
  late final controller = TextEditingController(text: widget.name);
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename business'),
    content: Form(
      key: form,
      child: AppTextField(
        label: 'Business name',
        controller: controller,
        validator: Validation.name,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, controller.text.trim());
          }
        },
        child: const Text('Save'),
      ),
    ],
  );
}
