import 'business_detail_model.dart';
import '../../workspace/models/workspace.dart';
import '../../workspace/models/workspace_state.dart';

class BusinessManagementModel extends WorkspaceState {
  BusinessManagementModel(
    WorkspaceState snapshot, {
    Iterable<String>? draftOrder,
    this.orderRevision,
    this.message,
    Map<String, BusinessDetailSummary> details = const {},
  }) : details = Map.unmodifiable(details),
       draftOrder = draftOrder == null ? null : List.unmodifiable(draftOrder),
       super(
         status: snapshot.status,
         data: snapshot.data,
         busy: snapshot.busy,
         error: snapshot.error,
       );
  final Map<String, BusinessDetailSummary> details;
  String get ownerName => data.membership?['display_name'] as String? ?? '';
  String get ownerEmail => data.membership?['email'] as String? ?? '';
  final List<String>? draftOrder;
  final int? orderRevision;
  final String? message;
  bool get reordering => draftOrder != null;
  List<Business> get businesses {
    if (draftOrder == null) return data.businesses;
    final byId = {for (final b in data.businesses) b.id: b};
    return [
      for (final id in draftOrder!)
        if (byId[id] != null) byId[id]!,
    ];
  }

  BusinessLocationSummary? locationFor(Business business) {
    final location = data.locations
        .where((l) => l['id'] == business.locationId)
        .firstOrNull;
    if (location == null) return null;
    return BusinessLocationSummary(
      location['name'] as String,
      [
        location['address_line_1'],
        location['address_line_2'],
        location['city'],
        location['state_code'],
        location['country_code'],
        location['postal_code'],
      ].where((v) => v != null && v.toString().isNotEmpty).join(', '),
      location['timezone'] as String,
    );
  }

  BusinessManagementModel copyWith({
    WorkspaceState? snapshot,
    Map<String, BusinessDetailSummary>? details,
    List<String>? draftOrder,
    int? orderRevision,
    String? message,
    bool clearDraft = false,
  }) => BusinessManagementModel(
    snapshot ?? this,
    details: details ?? this.details,
    draftOrder: clearDraft ? null : draftOrder ?? this.draftOrder,
    orderRevision: clearDraft ? null : orderRevision ?? this.orderRevision,
    message: message,
  );
  @override
  List<Object?> get props => [
    ...super.props,
    details,
    draftOrder,
    orderRevision,
    message,
  ];
}

class BusinessLocationSummary {
  const BusinessLocationSummary(this.name, this.address, this.timezone);
  final String name, address, timezone;
}
