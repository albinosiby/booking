import 'package:equatable/equatable.dart';

class TeamScreenModel extends Equatable {
  const TeamScreenModel({
    this.loading = true,
    this.members = const [],
    this.invitations = const [],
    this.error,
    this.busy = false,
  });
  final bool loading, busy;
  final List<Map<String, dynamic>> members, invitations;
  final String? error;
  @override
  List<Object?> get props => [loading, members, invitations, error, busy];
}
