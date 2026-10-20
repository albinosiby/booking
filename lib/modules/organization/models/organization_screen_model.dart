import '../../workspace/models/workspace_state.dart';
import 'dart:typed_data';

class OrganizationScreenModel extends WorkspaceState {
  OrganizationScreenModel.fromSnapshot(
    WorkspaceState snapshot, {
    this.stateCode,
    this.timezone = 'Asia/Kolkata',
    this.currency = 'INR',
    this.logo,
    this.logoType,
  }) : super(
         status: snapshot.status,
         data: snapshot.data,
         busy: snapshot.busy,
         error: snapshot.error,
       );
  final String? stateCode;
  final String timezone, currency;
  final Uint8List? logo;
  final String? logoType;
  OrganizationScreenModel copyWith({
    WorkspaceState? snapshot,
    String? stateCode,
    bool clearState = false,
    String? timezone,
    String? currency,
    Uint8List? logo,
    String? logoType,
  }) => OrganizationScreenModel.fromSnapshot(
    snapshot ?? this,
    stateCode: clearState ? null : stateCode ?? this.stateCode,
    timezone: timezone ?? this.timezone,
    currency: currency ?? this.currency,
    logo: logo ?? this.logo,
    logoType: logoType ?? this.logoType,
  );
  @override
  List<Object?> get props => [
    ...super.props,
    stateCode,
    timezone,
    currency,
    logo,
    logoType,
  ];
}
