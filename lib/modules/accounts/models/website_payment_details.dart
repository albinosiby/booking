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
}
