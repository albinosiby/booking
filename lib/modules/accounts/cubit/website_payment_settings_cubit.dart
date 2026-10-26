import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../../utils/services/logo_picker_service.dart';
import '../models/website_payment_settings_model.dart';
import '../repositories/website_payment_repository.dart';
import '../repositories/website_payment_qr_repository.dart';

class WebsitePaymentSettingsCubit extends Cubit<WebsitePaymentSettingsModel> {
  WebsitePaymentSettingsCubit(this.repository, this.images)
    : super(const WebsitePaymentSettingsModel());
  final WebsitePaymentRepository repository;
  final WebsitePaymentQrRepository images;
  int generation = 0;
  String message(Object error) => error is AppException
      ? error.message
      : 'Could not update payment details. Please try again.';
  WebsitePaymentSettingsModel snapshot({
    WebsitePaymentDetails? saved,
    String? upiId,
    LogoSelection? qr,
    bool removeQr = false,
    bool loading = false,
    bool picking = false,
    bool saving = false,
    String? error,
    String? success,
  }) => WebsitePaymentSettingsModel(
    saved: saved ?? state.saved,
    upiId: upiId ?? state.upiId,
    qr: removeQr ? null : qr ?? state.qr,
    loading: loading,
    picking: picking,
    saving: saving,
    error: error,
    success: success,
  );
  Future<void> load() async {
    if (isClosed || state.picking || state.saving) return;
    final g = ++generation;
    emit(snapshot(loading: true));
    try {
      final details = await repository.websitePayments();
      if (!isClosed && g == generation) {
        emit(
          WebsitePaymentSettingsModel(
            saved: details,
            upiId: details.upiId,
            qr: details.qr,
            loading: false,
          ),
        );
      }
    } catch (e) {
      if (!isClosed && g == generation) {
        emit(snapshot(error: message(e)));
      }
    }
  }

  void upiChanged(String value) {
    if (!isClosed && !state.busy && value != state.upiId) {
      emit(snapshot(upiId: value));
    }
  }

  Future<void> pick() async {
    if (isClosed || state.busy || state.saved == null) return;
    final g = ++generation;
    emit(snapshot(picking: true));
    try {
      final image = await images.pick();
      if (!isClosed && g == generation) emit(snapshot(qr: image));
    } catch (e) {
      if (!isClosed && g == generation) {
        emit(snapshot(error: message(e)));
      }
    }
  }

  void removeQr() {
    if (!isClosed && !state.busy && state.qr != null) {
      emit(snapshot(removeQr: true));
    }
  }

  Future<void> save() async {
    if (isClosed || !state.canSave) return;
    if (state.upiId.trim().isNotEmpty &&
        !RegExp(
          r'^[A-Za-z0-9._-]{2,}@[A-Za-z0-9.-]{2,}$',
        ).hasMatch(state.upiId.trim())) {
      emit(snapshot(error: 'Enter a valid UPI ID.'));
      return;
    }
    final g = ++generation;
    emit(snapshot(saving: true));
    try {
      final result = await repository.saveWebsitePayments(
        state.saved!.version,
        state.upiId,
        state.qr,
      );
      if (!isClosed && g == generation) {
        emit(
          WebsitePaymentSettingsModel(
            saved: result,
            upiId: result.upiId,
            qr: result.qr,
            loading: false,
            success: 'Website payment details saved.',
          ),
        );
      }
    } catch (e) {
      if (!isClosed && g == generation) {
        emit(snapshot(error: message(e)));
      }
    }
  }

  @override
  Future<void> close() {
    generation++;
    return super.close();
  }
}
