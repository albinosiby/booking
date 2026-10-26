import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../models/invoice_models.dart';
import '../repositories/invoice_repository.dart';

String invoiceError(Object e) => e is AppException
    ? e.message
    : 'Could not complete this action. Please try again.';

class InvoiceSettingsCubit extends Cubit<InvoiceSettingsModel> {
  InvoiceSettingsCubit(this.repository) : super(const InvoiceSettingsModel());
  final IInvoiceRepository repository;
  InvoiceSettingsModel _from(
    InvoiceSettings s, {
    bool saving = false,
    String? error,
  }) => InvoiceSettingsModel(
    enabled: s.enabled,
    template: s.template,
    templates: s.templates,
    loaded: true,
    saving: saving,
    error: error,
  );
  InvoiceSettingsModel _keep({bool loading = false, String? error}) =>
      InvoiceSettingsModel(
        enabled: state.enabled,
        template: state.template,
        templates: state.templates,
        loaded: state.loaded,
        loading: loading,
        error: error,
      );
  Future<void> load() async {
    if (isClosed || state.busy) return;
    emit(_keep(loading: true));
    try {
      final settings = await repository.settings();
      if (!isClosed) emit(_from(settings));
    } catch (e) {
      if (!isClosed) emit(_keep(error: invoiceError(e)));
    }
  }

  Future<void> _save({bool? enabled, String? template}) async {
    if (isClosed || state.busy || !state.loaded) return;
    emit(
      InvoiceSettingsModel(
        enabled: state.enabled,
        template: state.template,
        templates: state.templates,
        loaded: true,
        saving: true,
      ),
    );
    try {
      final saved = await repository.saveSettings(
        enabled: enabled,
        template: template,
      );
      if (!isClosed) emit(_from(saved));
    } catch (e) {
      if (!isClosed) emit(_keep(error: invoiceError(e)));
    }
  }

  Future<void> toggle(bool enabled) =>
      enabled == state.enabled ? Future.value() : _save(enabled: enabled);
  Future<void> chooseTemplate(String template) =>
      template == state.template ? Future.value() : _save(template: template);
  Future<List<int>> preview(String template) =>
      repository.previewTemplate(template);
}

class BookingInvoicesCubit extends Cubit<BookingInvoicesModel> {
  BookingInvoicesCubit(this.repository, this.files, this.bookingId)
    : super(const BookingInvoicesModel());
  final IInvoiceRepository repository;
  final InvoiceFileGateway files;
  final String bookingId;
  static const _uuid = Uuid();
  Future<void> load() async {
    if (isClosed || state.workingOn != null) return;
    emit(
      BookingInvoicesModel(
        enabled: state.enabled,
        invoices: state.invoices,
        loading: true,
      ),
    );
    try {
      final list = await repository.list(bookingId);
      if (!isClosed) {
        emit(
          BookingInvoicesModel(
            enabled: list.enabled,
            invoices: list.invoices,
            loading: false,
          ),
        );
      }
    } catch (e) {
      if (!isClosed) {
        emit(
          BookingInvoicesModel(
            enabled: state.enabled,
            invoices: state.invoices,
            loading: false,
            error: invoiceError(e),
          ),
        );
      }
    }
  }

  /// Saves a stored invoice, or a freshly generated one when [invoice] is null.
  Future<void> download([BookingInvoice? invoice]) =>
      _run(invoice, (bytes, name) async {
        final saved = await files.save(bytes, name);
        return saved ? 'Invoice saved.' : 'Download cancelled.';
      });

  /// Opens the system share sheet for a stored invoice, or a freshly generated one.
  Future<void> share([BookingInvoice? invoice]) =>
      _run(invoice, (bytes, name) async {
        await files.share(bytes, name);
        return null;
      });

  Future<void> _run(
    BookingInvoice? invoice,
    Future<String?> Function(List<int> bytes, String filename) deliver,
  ) async {
    if (isClosed || state.busy || !state.enabled && invoice == null) return;
    emit(
      BookingInvoicesModel(
        enabled: state.enabled,
        invoices: state.invoices,
        loading: false,
        workingOn: invoice?.id ?? BookingInvoicesModel.newInvoice,
      ),
    );
    try {
      final target =
          invoice ?? await repository.generate(bookingId, _uuid.v4());
      final bytes = await repository.pdf(target.id);
      final message = await deliver(bytes, target.filename);
      var invoices = state.invoices;
      if (invoice == null) {
        // The new invoice is already delivered; a failed refresh must not hide that.
        try {
          invoices = (await repository.list(bookingId)).invoices;
        } catch (_) {
          invoices = [target, ...invoices.where((i) => i.id != target.id)];
        }
      }
      if (isClosed) return;
      emit(
        BookingInvoicesModel(
          enabled: state.enabled,
          invoices: invoices,
          loading: false,
          message: message,
        ),
      );
    } catch (e) {
      if (!isClosed) {
        emit(
          BookingInvoicesModel(
            enabled: state.enabled,
            invoices: state.invoices,
            loading: false,
            error: invoiceError(e),
          ),
        );
      }
    }
  }
}
