import 'dart:convert';
import 'dart:typed_data';
import '../../../utils/services/logo_picker_service.dart';

class WebsitePaymentDetails {
  const WebsitePaymentDetails({
    required this.version,
    required this.upiId,
    this.qr,
  });
  final int version;
  final String upiId;
  final LogoSelection? qr;
  factory WebsitePaymentDetails.fromJson(Map<String, dynamic> value) {
    final image = value['qr'];
    return WebsitePaymentDetails(
      version: value['version'] as int,
      upiId: value['upi_id'] as String,
      qr: image == null
          ? null
          : LogoSelection(
              Uint8List.fromList(base64Decode(image['base64'] as String)),
              image['content_type'] as String,
            ),
    );
  }
}

abstract interface class WebsitePaymentRepository {
  Future<WebsitePaymentDetails> websitePayments();
  Future<WebsitePaymentDetails> saveWebsitePayments(
    int version,
    String upiId,
    LogoSelection? qr,
  );
}
