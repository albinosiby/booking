import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubit/workspace_cubit.dart';
import '../models/business_order.dart';

/// Retained catalogs follow order changes without resetting their form drafts.
List<T> orderedWorkspaceBusinesses<T>(
  BuildContext context,
  Iterable<T> items,
  String Function(T) businessId,
) {
  final workspace = context.watch<WorkspaceCubit?>()?.state.data;
  return orderByBusiness(
    items,
    businessId,
    workspace?.businesses.map((b) => b.id) ?? const [],
  );
}
