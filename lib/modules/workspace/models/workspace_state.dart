import 'package:equatable/equatable.dart';
import 'workspace.dart';

enum LoadStatus { initial, loading, ready, failure }

class WorkspaceState extends Equatable {
  const WorkspaceState({
    this.status = LoadStatus.initial,
    this.data = const Workspace(),
    this.busy = false,
    this.error,
  });
  final LoadStatus status;
  final Workspace data;
  final bool busy;
  final String? error;
  @override
  List<Object?> get props => [status, data, busy, error];
}
