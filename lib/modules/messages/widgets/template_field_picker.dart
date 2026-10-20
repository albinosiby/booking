import 'package:flutter/material.dart';
import '../models/message_template.dart';

class TemplateFieldPicker extends StatefulWidget {
  const TemplateFieldPicker({super.key});
  @override
  State<TemplateFieldPicker> createState() => _TemplateFieldPickerState();
}

class _TemplateFieldPickerState extends State<TemplateFieldPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final fields = messageFields.entries
        .where(
          (f) => '${f.key} ${f.value}'.toLowerCase().contains(
            query.trim().toLowerCase(),
          ),
        )
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Insert field',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search booking fields',
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: fields.isEmpty
                    ? const Center(child: Text('No matching fields'))
                    : ListView.builder(
                        itemCount: fields.length,
                        itemBuilder: (context, i) => ListTile(
                          title: Text(fields[i].value),
                          subtitle: Text('{${fields[i].key}}'),
                          trailing: const Icon(Icons.add_rounded, size: 20),
                          onTap: () => Navigator.pop(context, fields[i].key),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
