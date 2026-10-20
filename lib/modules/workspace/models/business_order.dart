/// Preserve the original order of records within each business.
List<T> orderByBusiness<T>(
  Iterable<T> items,
  String Function(T) businessId,
  Iterable<String> businessIds,
) {
  final rank = {for (final entry in businessIds.indexed) entry.$2: entry.$1};
  final entries = items.indexed.toList();
  entries.sort((a, b) {
    final order = (rank[businessId(a.$2)] ?? rank.length).compareTo(
      rank[businessId(b.$2)] ?? rank.length,
    );
    return order == 0 ? a.$1.compareTo(b.$1) : order;
  });
  return List.unmodifiable(entries.map((entry) => entry.$2));
}
