import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/admissions/cubit/admission_cubit.dart';
import 'package:eden_booking/modules/admissions/models/admission_models.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'admissions_test.dart' show AdmissionsFake, example;
import 'booking_module_test.dart' show BookingSource;

class UpdatingAdmissions extends AdmissionsFake {
  final updates = StreamController<void>.broadcast();
  Completer<AdmissionCatalog>? catalogGate;
  bool detailStarted = false;
  int catalogReads = 0;
  @override
  Stream<void> get changes => updates.stream;
  @override
  Future<AdmissionCatalog> catalog() {
    catalogReads++;
    return catalogGate?.future ?? super.catalog();
  }

  @override
  Future<Admission> detail(String id) {
    detailStarted = true;
    return super.detail(id);
  }
}

void main() {
  test(
    'admission detail and catalog start together instead of serial network waits',
    () async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final r = UpdatingAdmissions();
      final catalog = await r.catalog();
      r.catalogGate = Completer();
      final c = AdmissionCubit(w, r);
      final loading = c.loadDetail('admission');
      await Future<void>.delayed(Duration.zero);
      expect(r.detailStarted, isTrue);
      r.catalogGate!.complete(catalog);
      await loading;
      expect(c.state.detail?.id, 'admission');
      await c.close();
      await r.updates.close();
      await w.close();
    },
  );
  test(
    'retained admission list updates after background changes without discarding loaded items',
    () async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final r = UpdatingAdmissions(), c = AdmissionCubit(w, r);
      await c.loadList();
      expect(c.state.items.single.status, 'active');
      final updated = c.stream.firstWhere(
        (s) => s.items.isNotEmpty && s.items.single.status == 'expired',
      );
      r.record = example(status: 'expired');
      r.updates.add(null);
      expect(c.state.items.single.status, 'active');
      await updated.timeout(const Duration(seconds: 5));
      expect(c.state.items.single.status, 'expired');
      await c.loadForm();
      final reads = r.catalogReads;
      c.update(c.state.draft.copyWith(time: '10:00'));
      r.updates.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(r.catalogReads, reads);
      expect(c.state.draft.time, '10:00');
      await c.close();
      await r.updates.close();
      await w.close();
    },
  );
}
