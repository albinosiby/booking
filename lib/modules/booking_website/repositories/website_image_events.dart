import 'dart:async';

/// Signals that a saved website photo changed without carrying image bytes.
class WebsiteImageEvents {
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  void changed() => _changes.add(null);
  Future<void> dispose() => _changes.close();
}
