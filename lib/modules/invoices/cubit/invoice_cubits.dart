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
  Future<void> load() async {
    if (isClosed || state.busy) return;
    emit(InvoiceSettingsModel(enabled: state.enabled, loading: true));
    try {
      final enabled = await repository.settings();
      if (!isClosed) {
        emit(InvoiceSettingsModel(enabled: enabled, loaded: true));
      }
    } catch (e) {
      if (!isClosed) {
        emit(
          InvoiceSettingsModel(enabled: state.enabled, error: invoiceError(e)),
        );
      }
    }
  }

  Future<void> toggle(bool enabled) async {
    if (isClosed || state.busy || !state.loaded || enabled == state.enabled) {
      return;
    }
    emit(
      InvoiceSettingsModel(enabled: state.enabled, loaded: true, saving: true),
    );
    try {
      final saved = await repository.saveSettings(enabled);
      if (!isClosed) emit(InvoiceSettingsModel(enabled: saved, loaded: true));
    } catch (e) {
      if (!isClosed) {
        emit(
          InvoiceSettingsModel(
            enabled: state.enabled,
            loaded: true,
            error: invoiceError(e),
          ),
        );
      }
    }
  }
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
