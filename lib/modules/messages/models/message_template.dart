import 'package:equatable/equatable.dart';
import '../../bookings/models/booking_models.dart';
import '../../../utils/helpers/time_format.dart';

const defaultMessageBody = '''Dear {customer_name},
Your booking has been {booking_status}.

*Booking Details*

• Booking ID: *{booking_reference}*
• Venue: *{venue_name}*
• Slot: *{space_name}*
• Date: *{booking_date}*
• Time: *{start_time} - {end_time}*

*Payment Summary*

• Slot Amount: *{booking_total}*
• Pending Amount: *{balance_due}*

Thank you for booking with us!
We look forward to seeing you!

Best regards,
{organization_name}''';
const messageFields = <String, String>{
  'customer_name': 'Customer name',
  'booking_reference': 'Booking ID',
  'venue_name': 'Venue',
  'space_name': 'Space',
  'booking_date': 'Date',
  'start_time': 'Start time',
  'end_time': 'End time',
  'subtotal': 'Subtotal',
  'discount': 'Discount',
  'booking_total': 'Total',
  'amount_received': 'Received',
  'balance_due': 'Pending',
  'organization_name': 'Organization',
  'website': 'Website',
  'booking_status': 'Booking status',
};
String? validateMessageBody(String value) {
  if (value.trim().isEmpty || value.length > 6000) {
    return 'Write a message of 1–6000 characters.';
  }
  final tokens = RegExp(r'\{([^{}]*)\}');
  for (final m in tokens.allMatches(value)) {
    if (!messageFields.containsKey(m[1])) return 'Unknown field: {${m[1]}}.';
  }
  if (RegExp(r'[{}]').hasMatch(value.replaceAll(tokens, ''))) {
    return 'Complete every field using {field_name}.';
  }
  return null;
}

class MessageTemplate extends Equatable {
  const MessageTemplate({
    required this.id,
    required this.name,
    required this.body,
    this.website = '',
    this.primary = false,
    this.builtin = false,
  });
  static const predefined = MessageTemplate(
    id: 'default',
    name: 'Booking confirmation',
    body: defaultMessageBody,
    primary: true,
    builtin: true,
  );
  final String id, name, body, website;
  final bool primary, builtin;
  factory MessageTemplate.fromJson(Map<String, dynamic> j) => MessageTemplate(
    id: j['id'],
    name: j['name'],
    body: j['body'],
    website: j['website_url'] ?? '',
    primary: j['is_primary'] ?? false,
    builtin: j['is_builtin'] ?? false,
  );
  String render(Map<String, String> fields) =>
      body.replaceAllMapped(RegExp(r'\{([^{}]*)\}'), (m) => fields[m[1]] ?? '');
  @override
  List<Object?> get props => [id, name, body, website, primary, builtin];
}

class MessageTemplateCatalog extends Equatable {
  MessageTemplateCatalog({
    Iterable<MessageTemplate> templates = const [MessageTemplate.predefined],
    this.canManage = false,
  }) : templates = List.unmodifiable(templates);
  final List<MessageTemplate> templates;
  final bool canManage;
  MessageTemplate get primary =>
      templates.where((t) => t.primary).firstOrNull ??
      MessageTemplate.predefined;
  factory MessageTemplateCatalog.fromJson(Map<String, dynamic> j) =>
      MessageTemplateCatalog(
        canManage: j['can_manage'] ?? false,
        templates: (j['templates'] as List).map(
          (t) => MessageTemplate.fromJson(Map<String, dynamic>.from(t)),
        ),
      );
  @override
  List<Object?> get props => [templates, canManage];
}

String messageMoney(int minor, String currency) =>
    '${currency == 'INR' ? '₹' : '$currency '}${minor % 100 == 0 ? (minor ~/ 100).toString() : (minor / 100).toStringAsFixed(2)}';

Map<String, String> bookingMessageFields(
  BookingRecord b,
  String organization,
  String website,
  String currency,
) {
  final date = DateTime.parse(b.localStart.substring(0, 10));
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  final overnight =
      b.localEnd.substring(0, 10) != b.localStart.substring(0, 10);
  return {
    'customer_name': b.customer.name,
    'booking_reference': b.reference,
    'venue_name': b.businessName,
    'space_name': '${b.optionName} · ${b.spaceName}',
    'booking_date':
        '${date.day} ${months[date.month - 1]} ${date.year} (${days[date.weekday - 1]})',
    'start_time': TimeFormat.display(b.localStart.substring(11, 16)),
    'end_time':
        '${TimeFormat.display(b.localEnd.substring(11, 16))}${overnight ? ' (next day)' : ''}',
    'subtotal': messageMoney(b.subtotal ?? b.total + b.discountMinor, currency),
    'discount': messageMoney(b.discountMinor, currency),
    'booking_total': messageMoney(b.total, currency),
    'amount_received': messageMoney(b.netPaid, currency),
    'balance_due': messageMoney(b.balance, currency),
    'organization_name': organization,
    'website': website,
    'booking_status': switch (b.status) {
      'no_show' => 'marked as no-show',
      _ => b.status,
    },
  };
}

const sampleMessageFields = <String, String>{
  'customer_name': 'Abin',
  'booking_reference': 'BK-000123',
  'venue_name': 'Eden Sports Arena',
  'space_name': 'Football · Half A',
  'booking_date': '26 Sep 2026 (Saturday)',
  'start_time': '16:00',
  'end_time': '17:00',
  'subtotal': '₹700',
  'discount': '₹50',
  'booking_total': '₹650',
  'amount_received': '₹200',
  'balance_due': '₹450',
  'organization_name': 'Eden Sports Arena',
  'website': '',
  'booking_status': 'confirmed',
};
