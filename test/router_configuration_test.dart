import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/config/routes/routes_config.dart';
import 'package:eden_booking/modules/auth/cubit/auth_cubit.dart';
import 'package:eden_booking/modules/auth/models/app_user.dart';
import 'package:eden_booking/modules/auth/repositories/auth_repository_interface.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';

class _Auth extends Fake implements AuthRepository {
  @override
  Stream<AppUser?> get changes => const Stream.empty();
}

class _Workspace extends Fake implements WorkspaceRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('the full application router accepts every configured route', () async {
    final auth = AuthCubit(_Auth()), workspace = WorkspaceCubit(_Workspace());
    final refresh = RouterRefresh([auth.stream, workspace.stream]);
    final router = createRouter(auth, workspace, refresh);
    expect(router.configuration.routes, isNotEmpty);
    router.dispose();
    refresh.dispose();
    await auth.close();
    await workspace.close();
  });
}
