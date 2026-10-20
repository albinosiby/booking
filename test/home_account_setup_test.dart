import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/dashboard/cubit/home_cubit.dart';
import 'package:eden_booking/modules/dashboard/repositories/dashboard_repository.dart';
import 'package:eden_booking/modules/accounts/models/accounts_models.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'booking_module_test.dart' show BookingSource;
import 'accounts_module_test.dart' show FakeAccountsRepository;

void main() {
  test(
    'Home prompts only when no active bank exists and updates after setup',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final accounts = FakeAccountsRepository();
      accounts.catalogValue = FinanceCatalog(
        accounts: const [MoneyAccount(id: 'cash', name: 'Cash', kind: 'cash')],
      );
      final home = HomeCubit(
        SessionDashboardRepository(workspace),
        null,
        accounts,
      );
      await home.loadAccountSetup();
      expect(home.state.needsAccountSetup, isTrue);
      accounts.catalogValue = FinanceCatalog(
        accounts: const [MoneyAccount(id: 'bank', name: 'Bank', kind: 'bank')],
      );
      accounts.events.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(home.state.needsAccountSetup, isFalse);
      accounts.catalogValue = FinanceCatalog(
        accounts: const [
          MoneyAccount(id: 'bank', name: 'Bank', kind: 'bank', active: false),
        ],
      );
      await home.loadAccountSetup();
      expect(home.state.needsAccountSetup, isTrue);
      workspace.clear();
      await Future<void>.delayed(Duration.zero);
      expect(home.state.needsAccountSetup, isFalse);
      await home.close();
      await workspace.close();
      await accounts.events.close();
    },
  );
}
