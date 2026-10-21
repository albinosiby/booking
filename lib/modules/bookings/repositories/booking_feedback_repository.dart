/// Optional device feedback, separate from booking persistence and validation.
abstract interface class BookingFeedbackRepository {
  Future<void> created(String bookingId);
}
