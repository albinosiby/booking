import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../../design_system/design_system.dart';
import '../cubit/invoice_cubits.dart';
import '../models/invoice_models.dart';

/// Full-screen chooser: browse the invoice designs, open a sample PDF of each and pick one.
Future<void> showInvoiceTemplatePicker(
  BuildContext context,
  InvoiceSettingsCubit cubit,
) => showDialog<void>(
  context: context,
  useSafeArea: true,
  builder: (_) => Dialog.fullscreen(child: InvoiceTemplatePicker(cubit: cubit)),
);

class InvoiceTemplatePicker extends StatefulWidget {
  const InvoiceTemplatePicker({super.key, required this.cubit});
  final InvoiceSettingsCubit cubit;
  @override
  State<InvoiceTemplatePicker> createState() => _InvoiceTemplatePickerState();
}

class _InvoiceTemplatePickerState extends State<InvoiceTemplatePicker> {
  String? previewing;
  Future<void> preview(InvoiceTemplateInfo t) async {
    if (previewing != null) return;
    setState(() => previewing = t.id);
    try {
      final bytes = await widget.cubit.preview(t.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useSafeArea: true,
        builder: (c) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text('${t.name} sample'),
              leading: IconButton(
                tooltip: 'Close sample',
                onPressed: () => Navigator.pop(c),
                icon: const Icon(Icons.close),
              ),
            ),
            body: PdfViewer.data(
              Uint8List.fromList(bytes),
              sourceName: 'invoice-sample-${t.id}',
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) showMessage(context, invoiceError(e));
    } finally {
      if (mounted) setState(() => previewing = null);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<InvoiceSettingsCubit, InvoiceSettingsModel>(
    bloc: widget.cubit,
    listenWhen: (a, b) => b.error != null && a.error != b.error,
    listener: (context, s) => showMessage(context, s.error!),
    builder: (context, s) => Scaffold(
      appBar: AppBar(
        title: const Text('Invoice design'),
        leading: IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Choose how your invoices look. Open a sample to see it with your own name, address and logo. New invoices use the selected design; invoices already generated keep the design they were made with.',
          ),
          const SizedBox(height: 16),
          if (s.saving) const LinearProgressIndicator(),
          for (final t in s.templates)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                key: ValueKey('invoice-template-${t.id}'),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InvoiceTemplateThumbnail(id: t.id),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(t.description),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                key: ValueKey('invoice-preview-${t.id}'),
                                onPressed: previewing != null
                                    ? null
                                    : () => preview(t),
                                child: Text(
                                  previewing == t.id
                                      ? 'Loading…'
                                      : 'Preview sample',
                                ),
                              ),
                              if (t.id == s.template)
                                const Chip(
                                  avatar: Icon(Icons.check, size: 18),
                                  label: Text('Selected'),
                                )
                              else
                                FilledButton(
                                  key: ValueKey('invoice-use-${t.id}'),
                                  onPressed: s.busy
                                      ? null
                                      : () => widget.cubit.chooseTemplate(t.id),
                                  child: const Text('Use this design'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A small drawn miniature of each design so the choice is visible before opening a sample.
class InvoiceTemplateThumbnail extends StatelessWidget {
  const InvoiceTemplateThumbnail({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final accent = switch (id) {
      'modern' => const Color(0xFF1F4E8C),
      'minimal' => const Color(0xFF202020),
      _ => const Color(0xFF337418),
    };
    Widget bar(double w, {Color? color, double h = 4}) => Container(
      width: w,
      height: h,
      margin: const EdgeInsets.only(bottom: 4),
      color: color ?? Colors.black26,
    );
    return Container(
      width: 84,
      height: 118,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (id == 'modern')
            Container(height: 26, color: accent)
          else
            const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(id == 'minimal' ? 24 : 36, color: accent, h: 5),
                const SizedBox(height: 4),
                for (var i = 0; i < 2; i++) ...[
                  bar(26, color: id == 'minimal' ? Colors.black45 : accent),
                  if (id == 'classic')
                    Container(
                      height: 1,
                      width: 64,
                      margin: const EdgeInsets.only(bottom: 4),
                      color: Colors.black12,
                    ),
                  bar(60),
                  bar(52),
                ],
                Container(
                  width: 64,
                  height: 8,
                  color: id == 'modern' ? const Color(0xFFE8F0FA) : null,
                  child: id == 'modern'
                      ? null
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: bar(40, color: accent),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
