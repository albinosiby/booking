import 'package:flutter/material.dart';

class PickerItem {
  const PickerItem(this.value, this.label);
  final String value, label;
}

class AppPicker extends StatelessWidget {
  const AppPicker({
    super.key,
    required this.label,
    required this.items,
    required this.onChanged,
    this.value,
    this.required = false,
    this.enabled = true,
  });
  final String label;
  final List<PickerItem> items;
  final String? value;
  final ValueChanged<String> onChanged;
  final bool required, enabled;
  @override
  Widget build(BuildContext context) => FormField<String>(
    initialValue: value,
    validator: (_) => required && value == null ? 'Select $label' : null,
    builder: (field) => InkWell(
      onTap: !enabled
          ? null
          : () async {
              final result = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => _PickerSheet(label: label, items: items),
              );
              if (result != null) {
                field.didChange(result);
                onChanged(result);
              }
            },
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: field.errorText,
          enabled: enabled,
          suffixIcon: const Icon(Icons.expand_more),
        ),
        child: Text(
          items.where((i) => i.value == value).firstOrNull?.label ??
              'Select $label',
          style: const TextStyle(fontSize: 16),
        ),
      ),
    ),
  );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.label, required this.items});
  final String label;
  final List<PickerItem> items;
  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final list = widget.items
        .where((i) => i.label.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('No matching options'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, index) => ListTile(
                        title: Text(list[index].label),
                        onTap: () => Navigator.pop(context, list[index].value),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
