import 'package:equatable/equatable.dart';

class BookingWebsiteLink extends Equatable {
  const BookingWebsiteLink({
    required this.status,
    this.url,
    this.canManage = false,
  });
  final String status;
  final String? url;
  final bool canManage;
  bool get available =>
      ['published', 'paused'].contains(status) && url?.isNotEmpty == true;
  factory BookingWebsiteLink.fromJson(Map<String, dynamic> json) =>
      BookingWebsiteLink(
        status: json['status'] as String? ?? 'unconfigured',
        url: json['url'] as String?,
        canManage: json['can_manage'] == true,
      );
  @override
  List<Object?> get props => [status, url, canManage];
}
