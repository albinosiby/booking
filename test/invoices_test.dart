import 'package:eden_booking/modules/invoices/cubit/invoice_cubits.dart';
import 'package:eden_booking/modules/invoices/models/invoice_models.dart';
import 'package:eden_booking/modules/invoices/repositories/invoice_repository.dart';
import 'package:eden_booking/modules/invoices/widgets/booking_invoices_card.dart';
import 'package:eden_booking/modules/invoices/widgets/invoice_settings_card.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

BookingInvoice invoice(String id, String number, {int due = 4500}) =>
    BookingInvoice(
      id: id,
      bookingId: 'booking',
      number: number,
      totalMinor: 6500,
      paidMinor: 6500 - due,
      balanceMinor: due,
      currency: 'INR',
      generatedByName: 'Asha',
      generatedAt: DateTime(2030, 6, 5, 9, 30),
    );

class FakeInvoices implements IInvoiceRepository {
  bool enabled = true, failGenerate = false;
  String template = 'classic';
  final previews = <String>[];
  final stored = <BookingInvoice>[invoice('old', 'INV-000001')];
  final generated = <String>[];
  InvoiceSettings get current =>
      InvoiceSettings(enabled: enabled, template: template);
  @override
  Future<InvoiceSettings> settings() async => current;
  @override
  Future<InvoiceSettings> saveSettings({
    bool? enabled,
    String? template,
  }) async {
    this.enabled = enabled ?? this.enabled;
    this.template = template ?? this.template;
    return current;
  }

  @override
  Future<List<int>> previewTemplate(String template) async {
    previews.add(template);
    return [37, 80, 68, 70, 45];
  }

  @override
  Future<BookingInvoiceList> list(String bookingId) async =>
      BookingInvoiceList(enabled: enabled, invoices: [...stored.reversed]);
  @override
  Future<BookingInvoice> generate(String bookingId, String commandKey) async {
    if (failGenerate) throw const AppException('Invoices are turned off.');
    generated.add(commandKey);
    final created = invoice('new', 'INV-000002', due: 0);
    stored.add(created);
    return created;
  }

  @override
  Future<List<int>> pdf(String invoiceId) async => [37, 80, 68, 70, 45];
}

class FakeFiles implements InvoiceFileGateway {
  final saved = <String>[], shared = <String>[];
  bool accept = true;
  @override
  Future<bool> save(List<int> bytes, String filename) async {
    if (accept) saved.add(filename);
    return accept;
  }

  @override
  Future<void> share(List<int> bytes, String filename) async =>
      shared.add(filename);
}

Widget host(Widget child) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (_, _) => MaterialApp(home: Scaffold(body: child)),
);

void main() {
  test('settings default to on, load and persist the owner toggle', () async {
    final repo = FakeInvoices();
    final cubit = InvoiceSettingsCubit(repo);
    expect(cubit.state.enabled, isTrue);
    await cubit.load();
    expect(cubit.state.loaded, isTrue);
    await cubit.toggle(false);
    expect(repo.enabled, isFalse);
    expect(cubit.state.enabled, isFalse);
    await cubit.close();
  });

  test('choosing a design saves it and keeps the on/off setting', () async {
    final repo = FakeInvoices();
    final cubit = InvoiceSettingsCubit(repo);
    await cubit.load();
    expect(cubit.state.template, 'classic');
    expect(cubit.state.templates.map((t) => t.id), [
      'classic',
      'modern',
      'minimal',
    ]);
    await cubit.chooseTemplate('modern');
    expect(repo.template, 'modern');
    expect(repo.enabled, isTrue);
    expect(cubit.state.selected.name, 'Modern');
    expect(await cubit.preview('minimal'), isNotEmpty);
    expect(repo.previews, ['minimal']);
    await cubit.close();
  });

  test('a failed toggle keeps the saved value and shows the error', () async {
    final repo = _Rejecting();
    final cubit = InvoiceSettingsCubit(repo);
    await cubit.load();
    await cubit.toggle(false);
    expect(cubit.state.enabled, isTrue);
    expect(cubit.state.error, 'Only the owner can manage organization setup.');
    await cubit.close();
  });

  test(
    'download and share generate a new invoice once, then refresh history',
    () async {
      final repo = FakeInvoices(), files = FakeFiles();
      final cubit = BookingInvoicesCubit(repo, files, 'booking');
      await cubit.load();
      expect(cubit.state.enabled, isTrue);
      expect(cubit.state.invoices.map((i) => i.number), ['INV-000001']);
      await cubit.download();
      expect(files.saved, ['INV-000002.pdf']);
      expect(repo.generated, hasLength(1));
      expect(cubit.state.invoices.map((i) => i.number), [
        'INV-000002',
        'INV-000001',
      ]);
      expect(cubit.state.message, 'Invoice saved.');
      await cubit.share();
      expect(files.shared, ['INV-000002.pdf']);
      await cubit.close();
    },
  );

  test(
    'stored invoices are re-downloaded and shared without generating',
    () async {
      final repo = FakeInvoices(), files = FakeFiles();
      final cubit = BookingInvoicesCubit(repo, files, 'booking');
      await cubit.load();
      final old = cubit.state.invoices.single;
      await cubit.download(old);
      await cubit.share(old);
      expect(files.saved, ['INV-000001.pdf']);
      expect(files.shared, ['INV-000001.pdf']);
      expect(repo.generated, isEmpty);
      files.accept = false;
      await cubit.download(old);
      expect(cubit.state.message, 'Download cancelled.');
      await cubit.close();
    },
  );

  test(
    'turned-off invoices block generation and generation errors surface',
    () async {
      final repo = FakeInvoices()..enabled = false, files = FakeFiles();
      final cubit = BookingInvoicesCubit(repo, files, 'booking');
      await cubit.load();
      expect(cubit.state.enabled, isFalse);
      await cubit.download();
      expect(repo.generated, isEmpty);
      repo.enabled = true;
      repo.failGenerate = true;
      await cubit.load();
      await cubit.share();
      expect(cubit.state.error, 'Invoices are turned off.');
      expect(files.shared, isEmpty);
      expect(cubit.state.workingOn, isNull);
      await cubit.close();
    },
  );

  testWidgets('booking card shows actions and history, and hides when off', (
    tester,
  ) async {
    final repo = FakeInvoices(), files = FakeFiles();
    await tester.pumpWidget(
      host(
        SingleChildScrollView(
          child: BookingInvoicesSection(
            create: () => BookingInvoicesCubit(repo, files, 'booking'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Download invoice'), findsOneWidget);
    expect(find.text('Share invoice'), findsOneWidget);
    expect(find.text('INV-000001'), findsOneWidget);
    await tester.tap(find.byTooltip('Share INV-000001'));
    await tester.pumpAndSettle();
    expect(files.shared, ['INV-000001.pdf']);
    await tester.tap(find.text('Download invoice'));
    await tester.pumpAndSettle();
    expect(files.saved, ['INV-000002.pdf']);
    expect(find.text('INV-000002'), findsOneWidget);

    repo.enabled = false;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      host(
        BookingInvoicesSection(
          create: () => BookingInvoicesCubit(repo, files, 'booking'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Download invoice'), findsNothing);
  });

  testWidgets('settings card switch starts on and saves the owner change', (
    tester,
  ) async {
    final repo = FakeInvoices();
    await tester.pumpWidget(
      host(InvoiceSettingsSection(create: () => InvoiceSettingsCubit(repo))),
    );
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('invoice-toggle'));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(repo.enabled, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
  });

  testWidgets('design picker lists the designs, previews and selects one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeInvoices();
    await tester.pumpWidget(
      host(InvoiceSettingsSection(create: () => InvoiceSettingsCubit(repo))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Classic'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('invoice-template-open')));
    await tester.pumpAndSettle();
    for (final id in ['classic', 'modern', 'minimal']) {
      expect(find.byKey(ValueKey('invoice-template-$id')), findsOneWidget);
      expect(find.byKey(ValueKey('invoice-preview-$id')), findsOneWidget);
    }
    expect(find.text('Selected'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('invoice-use-minimal')),
    );
    await tester.tap(find.byKey(const ValueKey('invoice-use-minimal')));
    await tester.pumpAndSettle();
    expect(repo.template, 'minimal');
    expect(find.byKey(const ValueKey('invoice-use-minimal')), findsNothing);
    expect(find.byKey(const ValueKey('invoice-use-modern')), findsOneWidget);
  });
}

class _Rejecting extends FakeInvoices {
  @override
  Future<InvoiceSettings> saveSettings({
    bool? enabled,
    String? template,
  }) async =>
      throw const AppException('Only the owner can manage organization setup.');
}
