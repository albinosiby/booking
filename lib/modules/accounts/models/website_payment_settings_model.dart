import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import '../../../utils/services/logo_picker_service.dart';
import 'website_payment_details.dart';

bool samePaymentQr(LogoSelection? a, LogoSelection? b) =>
    identical(a, b) ||
    (a != null &&
        b != null &&
        a.contentType == b.contentType &&
        listEquals(a.bytes, b.bytes));

class WebsitePaymentSettingsModel extends Equatable {
  const WebsitePaymentSettingsModel({
    this.saved,
    this.upiId = '',
    this.qr,
    this.loading = true,
    this.picking = false,
    this.saving = false,
    this.error,
    this.success,
  });
  final WebsitePaymentDetails? saved;
  final String upiId;
  final LogoSelection? qr;
  final bool loading, picking, saving;
  final String? error, success;
  bool get busy => loading || picking || saving;
  bool get dirty =>
      saved != null &&
      (upiId.trim() != saved!.upiId.trim() || !samePaymentQr(qr, saved!.qr));
  bool get canSave => saved != null && dirty && !busy;
  @override
  List<Object?> get props => [
    saved,
    upiId,
    qr,
    loading,
    picking,
    saving,
    error,
    success,
  ];
}
