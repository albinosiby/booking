import '../modules/booking_blocks/models/slot_block_models.dart';
import '../modules/booking_blocks/repositories/slot_block_repository.dart';
import '../modules/booking_blocks/repositories/rest_slot_block_repository.dart';
import '../modules/booking_blocks/cubit/slot_block_cubits.dart';
import '../modules/admissions/cubit/admission_cubit.dart';
import '../modules/admissions/repositories/admission_repository.dart';
import '../modules/admissions/repositories/rest_admission_repository.dart';
import '../modules/bookings/repositories/booking_feedback_repository.dart';
import '../modules/bookings/repositories/device_booking_feedback_repository.dart';
import '../modules/messages/cubit/message_cubits.dart';
import '../modules/messages/models/message_template.dart';
import '../modules/messages/repositories/message_repository.dart';
import '../modules/messages/repositories/rest_message_repository.dart';
import '../modules/messages/repositories/device_message_share.dart';
import '../modules/sarvam/cubit/sarvam_cubits.dart';
import '../modules/sarvam/models/sarvam_models.dart';
import '../modules/sarvam/repositories/sarvam_repository.dart';
import '../modules/sarvam/repositories/rest_sarvam_repository.dart';
import '../modules/team/cubit/team_coaches_cubit.dart';
import '../modules/team/repositories/team_coaches_repository.dart';
import '../modules/profile/cubit/organization_edit_cubit.dart';
import '../modules/profile/repositories/organization_edit_repository.dart';
import '../modules/profile/repositories/rest_organization_edit_repository.dart';
import '../modules/customers/repositories/customer_repository.dart';
import '../modules/customers/cubit/customer_cubits.dart';
import '../modules/expenses/cubit/expenses_cubit.dart';
import '../modules/expenses/cubit/expense_form_cubit.dart';
import '../modules/expenses/cubit/expense_detail_cubit.dart';
import '../modules/expenses/repositories/expenses_repository.dart';
import '../modules/expenses/repositories/rest_expenses_repository.dart';
import '../modules/expenses/repositories/device_invoice_picker.dart';
import '../modules/income/cubit/income_cubit.dart';
import '../modules/income/repositories/income_repository.dart';
import '../modules/income/repositories/rest_income_repository.dart';
import '../modules/businesses/cubit/business_management_cubit.dart';
import 'package:app_links/app_links.dart';
import '../modules/team/repositories/invitation_link_repository.dart';
import '../modules/team/cubit/invitation_link_cubit.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../modules/configuration_drafts/repositories/configuration_draft_repository.dart';
import '../modules/configuration_drafts/repositories/secure_configuration_draft_repository.dart';
import '../modules/accounts/cubit/accounts_cubits.dart';
import '../modules/accounts/models/accounts_models.dart';
import '../modules/accounts/repositories/accounts_repository.dart';
import '../modules/accounts/repositories/rest_accounts_repository.dart';
import '../modules/bookings/cubit/booking_form_cubit.dart';
import '../modules/bookings/cubit/booking_detail_cubit.dart';
import '../modules/bookings/cubit/booking_list_cubit.dart';
import '../modules/bookings/models/booking_models.dart';
import '../modules/bookings/models/booking_list_model.dart';
import '../modules/bookings/repositories/booking_repository.dart';
import '../modules/bookings/repositories/rest_booking_repository.dart';
import '../utils/services/rest_api_service.dart';
import '../modules/hall/cubit/hall_setup_cubit.dart';
import '../modules/hall/repositories/hall_repository.dart';
import '../modules/hall/repositories/rest_hall_repository.dart';
import '../modules/court/cubit/court_setup_cubit.dart';
import '../modules/court/repositories/court_repository.dart';
import '../modules/court/repositories/rest_court_repository.dart';
import '../modules/pool/cubit/pool_setup_cubit.dart';
import '../modules/pool/repositories/pool_repository.dart';
import '../modules/pool/repositories/rest_pool_repository.dart';
import '../modules/turf/cubit/turf_setup_cubit.dart';
import '../modules/turf/repositories/turf_repository.dart';
import '../modules/turf/repositories/rest_turf_repository.dart';
import '../modules/dashboard/cubit/startup_cubit.dart';
import '../modules/dashboard/cubit/module_availability_cubit.dart';
import 'package:get_it/get_it.dart';
import '../modules/workspace/repositories/workspace_session.dart';
import '../modules/organization/repositories/organization_repository.dart';
import '../modules/businesses/repositories/business_repository.dart';
import '../modules/team/repositories/team_repository.dart';
import '../modules/profile/repositories/profile_repository.dart';
import '../modules/dashboard/repositories/dashboard_repository.dart';
import '../modules/organization/cubit/organization_cubit.dart';
import '../modules/organization/cubit/location_catalog_cubit.dart';
import '../modules/businesses/cubit/businesses_cubit.dart';
import '../modules/businesses/cubit/resource_setup_cubit.dart';
import '../modules/team/cubit/team_cubit.dart';
import '../modules/team/cubit/staff_assignment_cubit.dart';
import '../modules/team/cubit/invitation_cubit.dart';
import '../modules/profile/cubit/profile_cubit.dart';
import '../modules/dashboard/cubit/home_cubit.dart';

/// Composition root: swap persistence implementations here, never in screens.
void registerFeatureDependencies(GetIt di) {
  di.registerLazySingleton<SlotBlockRepository>(
    () => RestSlotBlockRepository(di(), di()),
  );
  di.registerFactoryParam<BlockListCubit, WorkspaceSession, BlockLaunch>(
    (s, l) => BlockListCubit(s, di(), l),
  );
  di.registerFactoryParam<BlockFormCubit, WorkspaceSession, BlockLaunch>(
    (s, l) => BlockFormCubit(s, di(), l),
  );
  di.registerLazySingleton<AdmissionRepository>(
    () => RestAdmissionRepository(di(), di()),
  );
  di.registerFactoryParam<AdmissionCubit, WorkspaceSession, void>(
    (s, _) => AdmissionCubit(s, di()),
  );
  di.registerLazySingleton<BookingFeedbackRepository>(
    () => DeviceBookingFeedbackRepository(),
  );
  di.registerLazySingleton<MessageRepository>(
    () => RestMessageRepository(di()),
  );
  di.registerLazySingleton<MessageShareGateway>(() => DeviceMessageShare());
  di.registerFactoryParam<TemplatesCubit, WorkspaceSession, void>(
    (s, _) => TemplatesCubit(s, di()),
  );
  di.registerFactoryParam<
    TemplateEditorCubit,
    WorkspaceSession,
    MessageTemplate?
  >((s, t) => TemplateEditorCubit(s, di(), t));
  di.registerLazySingleton<SarvamRepository>(() => RestSarvamRepository(di()));
  di.registerLazySingleton<RecordingSaver>(() => DeviceRecordingSaver());
  di.registerFactoryParam<SarvamSettingsCubit, WorkspaceSession, void>(
    (s, _) => SarvamSettingsCubit(s, di()),
  );
  di.registerFactoryParam<CallLogsCubit, WorkspaceSession, void>(
    (s, _) => CallLogsCubit(s, di()),
  );
  di.registerFactoryParam<CallDetailCubit, WorkspaceSession, SarvamCall>(
    (s, call) => CallDetailCubit(s, di(), di(), call),
  );
  di.registerFactoryParam<MessagePreviewCubit, WorkspaceSession, String>(
    (s, id) => MessagePreviewCubit(s, di(), di(), id),
  );
  di.registerLazySingleton<OrganizationEditRepository>(
    () => RestOrganizationEditRepository(di(), di()),
  );
  di.registerFactoryParam<OrganizationEditCubit, WorkspaceSession, void>(
    (s, _) => OrganizationEditCubit(s, di()),
  );
  di.registerLazySingleton<ExpensesRepository>(
    () => RestExpensesRepository(di()),
  );
  di.registerLazySingleton<InvoicePicker>(() => DeviceInvoicePicker());
  di.registerFactoryParam<ExpensesCubit, WorkspaceSession, void>(
    (s, _) => ExpensesCubit(s, di(), di()),
  );
  di.registerFactoryParam<ExpenseFormCubit, WorkspaceSession, void>(
    (s, _) => ExpenseFormCubit(s, di(), di()),
  );
  di.registerFactoryParam<ExpenseDetailCubit, WorkspaceSession, String>(
    (s, id) => ExpenseDetailCubit(s, di(), di(), id),
  );
  di.registerLazySingleton<IncomeRepository>(() => RestIncomeRepository(di()));
  di.registerFactoryParam<IncomeCubit, WorkspaceSession, void>(
    (s, _) => IncomeCubit(s, di(), di()),
  );
  di.registerLazySingleton<InvitationLinkRepository>(
    () => DeviceInvitationLinkRepository(AppLinks()),
  );
  di.registerFactory<InvitationLinkCubit>(() => InvitationLinkCubit(di()));
  if (!di.isRegistered<ConfigurationDraftRepository>()) {
    di.registerLazySingleton<ConfigurationDraftRepository>(
      () => const SecureConfigurationDraftRepository(FlutterSecureStorage()),
    );
  }
  di.registerLazySingleton<AccountsRepository>(
    () => RestAccountsRepository(di()),
  );
  di.registerLazySingleton<ReportSaver>(() => DeviceReportSaver());
  di.registerFactoryParam<AccountsOverviewCubit, WorkspaceSession, void>(
    (s, _) => AccountsOverviewCubit(s, di(), di()),
  );
  di.registerFactoryParam<AccountSettingsCubit, WorkspaceSession, void>(
    (s, _) => AccountSettingsCubit(s, di()),
  );
  di.registerFactoryParam<BankAccountCubit, WorkspaceSession, bool>(
    (s, cash) => BankAccountCubit(s, di(), cash: cash),
  );
  di.registerFactoryParam<FinanceEntryCubit, WorkspaceSession, String>(
    (s, k) => FinanceEntryCubit(s, di(), k, income: di()),
  );
  di.registerFactoryParam<TransactionsCubit, WorkspaceSession, FinanceFilter>(
    (s, f) => TransactionsCubit(s, di(), f),
  );
  di.registerFactoryParam<
    TransactionDetailsCubit,
    WorkspaceSession,
    FinanceTransaction
  >((s, e) => TransactionDetailsCubit(s, di(), e));
  di.registerFactoryParam<ReportsCubit, WorkspaceSession, FinanceFilter>(
    (s, f) => ReportsCubit(s, di(), di(), f),
  );
  di.registerLazySingleton<BookingRepository>(
    () => RestBookingRepository(di()),
  );
  di.registerFactoryParam<BookingFormCubit, WorkspaceSession, BookingLaunch>(
    (session, launch) =>
        BookingFormCubit(session, di(), launch, feedback: di()),
  );
  di.registerFactoryParam<BookingDetailCubit, WorkspaceSession, String>(
    (session, id) => BookingDetailCubit(session, di(), id),
  );
  di.registerFactoryParam<BookingListCubit, WorkspaceSession, BookingListMode>(
    (session, mode) => BookingListCubit(session, di(), mode),
  );
  di.registerLazySingleton<HallRepository>(() => RestHallRepository(di()));
  di.registerFactoryParam<HallSetupCubit, WorkspaceSession, String>(
    (session, id) => HallSetupCubit(session, di(), id, drafts: di()),
  );
  di.registerLazySingleton<CourtRepository>(() => RestCourtRepository(di()));
  di.registerFactoryParam<CourtSetupCubit, WorkspaceSession, String>(
    (session, id) => CourtSetupCubit(session, di(), id, drafts: di()),
  );
  di.registerLazySingleton<PoolRepository>(() => RestPoolRepository(di()));
  di.registerFactoryParam<PoolSetupCubit, WorkspaceSession, String>(
    (session, id) => PoolSetupCubit(session, di(), id, drafts: di()),
  );
  di.registerLazySingleton<TurfRepository>(() => RestTurfRepository(di()));
  di.registerFactoryParam<TurfSetupCubit, WorkspaceSession, String>(
    (session, id) => TurfSetupCubit(session, di(), id, drafts: di()),
  );
  di.registerFactoryParam<StartupCubit, WorkspaceSession, void>(
    (session, _) => StartupCubit(SessionDashboardRepository(session)),
  );
  di.registerFactoryParam<ModuleAvailabilityCubit, WorkspaceSession, void>(
    (session, _) =>
        ModuleAvailabilityCubit(SessionDashboardRepository(session)),
  );
  di.registerLazySingleton<OrganizationRepository>(
    () => LocalApiOrganizationRepository(di()),
  );
  di.registerLazySingleton<BusinessRepository>(
    () => LocalApiBusinessRepository(di()),
  );
  di.registerLazySingleton<TeamRepository>(() => LocalApiTeamRepository(di()));
  di.registerLazySingleton<ProfileRepository>(
    () => OrganizationProfileRepository(di(), di()),
  );
  di.registerFactory<LocationCatalogCubit>(() => LocationCatalogCubit(di()));
  di.registerFactory<TeamCubit>(() => TeamCubit(di()));
  di.registerLazySingleton<TeamCoachesRepository>(
    () => ConfigurationTeamCoachesRepository(di(), di(), di(), di()),
  );
  di.registerFactoryParam<TeamCoachesCubit, WorkspaceSession, void>(
    (session, _) => TeamCoachesCubit(di(), session),
  );
  di.registerFactoryParam<OrganizationCubit, WorkspaceSession, void>(
    (session, _) => OrganizationCubit(session, di()),
  );
  di.registerFactoryParam<BusinessesCubit, WorkspaceSession, void>(
    (session, _) => BusinessesCubit(session, di()),
  );
  di.registerFactoryParam<ResourceSetupCubit, WorkspaceSession, String>(
    (session, id) => ResourceSetupCubit(session, di(), id),
  );
  di.registerFactoryParam<
    StaffAssignmentCubit,
    WorkspaceSession,
    Map<String, dynamic>?
  >((session, member) => StaffAssignmentCubit(session, di(), member: member));
  di.registerFactoryParam<InvitationCubit, WorkspaceSession, void>(
    (session, _) => InvitationCubit(session, di()),
  );
  di.registerFactoryParam<ProfileCubit, WorkspaceSession, void>(
    (session, _) => ProfileCubit(session, di()),
  );
  di.registerFactoryParam<BusinessManagementCubit, WorkspaceSession, void>(
    (session, _) => BusinessManagementCubit(session, di()),
  );
  di.registerLazySingleton<CustomerRepository>(
    () => RestCustomerRepository(di()),
  );
  di.registerFactoryParam<CustomerListCubit, WorkspaceSession, void>(
    (s, _) => CustomerListCubit(s, di()),
  );
  di.registerFactoryParam<CustomerDetailCubit, WorkspaceSession, String>(
    (s, id) => CustomerDetailCubit(s, di(), id),
  );
  di.registerFactoryParam<HomeCubit, WorkspaceSession, void>(
    (session, _) => HomeCubit(
      SessionDashboardRepository(session),
      di.isRegistered<RestApiService>() ? di<BookingRepository>() : null,
      di.isRegistered<RestApiService>() ? di<AccountsRepository>() : null,
    ),
  );
}
