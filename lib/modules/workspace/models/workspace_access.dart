import 'dart:convert';
import 'workspace.dart';

/// Stable access identity: map ordering and refreshed object identity must not
/// reset pages, while changes to permissions or assigned spaces must reset them.
String workspaceAccessScope(Workspace workspace) {
  Object? canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) return value.map(canonical).toList();
    return value;
  }

  return jsonEncode(
    canonical({
      'organization': workspace.organization?.id,
      'membership': workspace.membership,
      'spaces': {
        for (final business in workspace.businesses)
          business.id: business.resources.map((r) => r.id).toList()..sort(),
      },
    }),
  );
}
