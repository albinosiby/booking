import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../utils/exceptions/app_exception.dart';

Uri websiteLinkUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.host.isEmpty ||
      !(uri.scheme == 'https' ||
          (uri.scheme == 'http' &&
              (['localhost', '127.0.0.1'].contains(uri.host) ||
                  uri.host.endsWith('.localhost'))))) {
    throw const AppException('The website address is invalid.');
  }
  return uri;
}

Future<void> openWebsiteLink(String value) async {
  if (!await launchUrl(
    websiteLinkUri(value),
    mode: LaunchMode.externalApplication,
  )) {
    throw const AppException(
      'Could not open the website. Copy the link instead.',
    );
  }
}

Future<void> copyWebsiteLink(String value) {
  websiteLinkUri(value);
  return Clipboard.setData(ClipboardData(text: value));
}
