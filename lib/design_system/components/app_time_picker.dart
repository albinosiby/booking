import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/helpers/time_format.dart';

/// Returns canonical backend time, including 00:00 for UI entry 24:00.
Future<String?> showAppTimePicker({
  required BuildContext context,
  required String initialTime,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TimeEntryDialog(initialTime: initialTime),
);

class _TimeEntryDialog extends StatefulWidget {
  const _TimeEntryDialog({required this.initialTime});
  final String initialTime;
  @override
  State<_TimeEntryDialog> createState() => _TimeEntryDialogState();
}

class _TimeEntryDialogState extends State<_TimeEntryDialog> {
  final form = GlobalKey<FormState>();
  late final hour = TextEditingController(
    text: TimeFormat.display(widget.initialTime).split(':')[0],
  );
  late final minute = TextEditingController(
    text: TimeFormat.display(widget.initialTime).split(':')[1],
  );

  void submit() {
    if (form.currentState!.validate()) {
      Navigator.of(
        context,
      ).pop(TimeFormat.normalize('${hour.text}:${minute.text}'));
    }
  }

  @override
  void dispose() {
    hour.dispose();
    minute.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Enter time'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: hour,
                    decoration: const InputDecoration(labelText: 'Hour'),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    validator: (_) =>
                        TimeFormat.normalize('${hour.text}:${minute.text}') ==
                            null
                        ? 'Use 00–23, or 24 with minute 00.'
                        : null,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 16),
                  child: Text(':'),
                ),
                Expanded(
                  child: TextFormField(
                    controller: minute,
                    decoration: const InputDecoration(labelText: 'Minute'),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    validator: (value) {
                      final number = int.tryParse(value ?? '');
                      return number == null || number < 0 || number > 59
                          ? 'Use 00–59.'
                          : null;
                    },
                    onFieldSubmitted: (_) => submit(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('24-hour time. Use 24:00 for midnight.'),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: submit, child: const Text('OK')),
    ],
  );
}
