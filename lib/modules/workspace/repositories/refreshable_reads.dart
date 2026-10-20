/// Optional repository capability for explicit user refresh. Kept independent
/// of transport so alternative persistence implementations can implement it.
abstract interface class RefreshableReads {
  void invalidateReads();
}

abstract interface class RetainedReadEvents {
  Stream<void> get readChanges;
  void revalidateReads();
}
