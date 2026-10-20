import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'message_repository.dart';

class DeviceMessageShare implements MessageShareGateway {
  @override
  Future<bool> whatsapp(String message) async {
    final encoded = Uri.encodeComponent(message);
    try {
      if (await launchUrl(
        Uri.parse('whatsapp://send?text=$encoded'),
        mode: LaunchMode.externalApplication,
      )) {
        return true;
      }
    } catch (_) {
      /* Fall back to WhatsApp's web entry point. */
    }
    try {
      return await launchUrl(
        Uri.parse('https://wa.me/?text=$encoded'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> copy(String message) =>
      Clipboard.setData(ClipboardData(text: message));
}
