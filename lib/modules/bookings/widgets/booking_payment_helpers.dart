String paymentLabel(String v) => switch (v) {
  'partial' => 'Partially paid',
  'refund_due' => 'Refund due',
  'bank_transfer' => 'Bank transfer',
  'upi' => 'UPI',
  _ =>
    v.isEmpty ? '' : v[0].toUpperCase() + v.substring(1).replaceAll('_', ' '),
};
