import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/bookings/models/booking_list_model.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';

void main() {
  test('booking payment totals separate net cash and bank receipts', () {
    final state = BookingListModel(
      totals: const [
        CollectionTotal('collection', 'cash', 15000),
        CollectionTotal('refund', 'cash', 2000),
        CollectionTotal('collection', 'upi', 10000),
        CollectionTotal('collection', 'card', 5000),
        CollectionTotal('refund', 'upi', 1000),
      ],
    );
    expect(state.cashReceivedNet, 13000);
    expect(state.bankReceivedNet, 14000);
  });
}
