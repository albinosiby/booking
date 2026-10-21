import '../../bookings/models/booking_models.dart';
import '../models/slot_block_models.dart';

abstract interface class SlotBlockRepository {
  Future<BookingCatalog> catalog();
  Stream<void> get changes;
  Future<SlotBlockPage> list(String businessId, String date, {int cursor = 0});
  Future<({List<BlockSlot> slots, int step})> slots(
    String businessId,
    String date,
    Iterable<String> spaces,
  );
  Future<String> create(BlockRequest request);
  Future<void> unblock(String id);
}
