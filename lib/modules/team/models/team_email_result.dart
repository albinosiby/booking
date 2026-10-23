/// The access grant is saved even when the notification could not be sent.
class TeamEmailResult {
  const TeamEmailResult(this.delivery);
  final String delivery;
  bool get sent => delivery == 'sent';
  String get message => sent
      ? 'Team access saved. The access email was sent. They can sign in with the same email to open their dashboard.'
      : 'Team access saved, but the email could not be sent. Check server SMTP settings, then resend the email from Team. They can already sign in with the same email.';
  factory TeamEmailResult.fromJson(Map<String, dynamic> json) =>
      TeamEmailResult(json['delivery'] as String);
}
