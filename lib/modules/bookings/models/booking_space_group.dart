import 'booking_models.dart';

/// Display projection only: stored names and inventory IDs remain unchanged.
class BookingSpaceChoice {
  const BookingSpaceChoice(this.space, this.title, this.fullGround);
  final BookingSpace space;
  final String title;
  final bool fullGround;
}

class BookingSpaceGroup {
  const BookingSpaceGroup(this.name, this.choices);
  final String name;
  final List<BookingSpaceChoice> choices;

  static List<BookingSpaceGroup> turf(List<BookingSpace> spaces) {
    final groups = <String, List<BookingSpaceChoice>>{};
    for (final space in spaces) {
      final parts = <String>[];
      for (final part
          in space.name
              .split('·')
              .map((p) => p.trim())
              .where((p) => p.isNotEmpty)) {
        if (parts.isEmpty || parts.last.toLowerCase() != part.toLowerCase()) {
          parts.add(part);
        }
      }
      final ground = parts.length > 1 ? parts.first : 'Turf spaces';
      final label = parts.length > 1 ? parts.skip(1).join(' · ') : space.name;
      final full = RegExp(
        r'^(full|whole)\s+(ground|turf|court)$',
        caseSensitive: false,
      ).hasMatch(label);
      groups
          .putIfAbsent(ground, () => [])
          .add(BookingSpaceChoice(space, full ? 'Full Ground' : label, full));
    }
    return List.unmodifiable(
      groups.entries.map(
        (g) => BookingSpaceGroup(
          g.key,
          List.unmodifiable([
            ...(g.value.where((c) => !c.fullGround).toList()..sort((a, b) {
              int rank(String title) => switch (title.toLowerCase()) {
                'half a' => 0,
                'half b' => 1,
                _ => 2,
              };
              final order = rank(a.title).compareTo(rank(b.title));
              return order != 0
                  ? order
                  : g.value.indexOf(a).compareTo(g.value.indexOf(b));
            })),
            ...g.value.where((c) => c.fullGround),
          ]),
        ),
      ),
    );
  }
}
