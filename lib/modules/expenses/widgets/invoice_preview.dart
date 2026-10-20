import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../models/expense_models.dart';

Future<void> showInvoicePreview(
  BuildContext context,
  ExpenseInvoice invoice,
  Uint8List bytes,
) => showDialog<void>(
  context: context,
  useSafeArea: true,
  builder: (c) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text(invoice.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          tooltip: 'Close invoice',
          onPressed: () => Navigator.pop(c),
          icon: const Icon(Icons.close),
        ),
      ),
      body: invoice.type == 'application/pdf'
          ? PdfViewer.data(bytes, sourceName: invoice.id)
          : Center(
              child: InteractiveViewer(
                minScale: .5,
                maxScale: 5,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) =>
                      const Text('This image could not be displayed.'),
                ),
              ),
            ),
    ),
  ),
);
