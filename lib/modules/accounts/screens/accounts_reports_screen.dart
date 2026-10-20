import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../../bookings/models/booking_models.dart';
import '../cubit/accounts_cubits.dart';
import '../models/accounts_models.dart';
import '../models/accounts_screen_models.dart';
import '../widgets/accounts_widgets.dart';

class AccountsReportsScreen extends StatefulWidget {
  const AccountsReportsScreen({super.key, required this.filter});
  final FinanceFilter filter;
  @override
  State<AccountsReportsScreen> createState() => _AccountsReportsScreenState();
}

class _AccountsReportsScreenState extends State<AccountsReportsScreen> {
  late final cubit = getIt<ReportsCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.filter,
  );
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<ReportsCubit, ReportsModel>(
    bloc: cubit,
    builder: (c, s) => AppPage(
      title: 'Reports & downloads',
      back: true,
      showAppBar: true,
      compactHeader: true,
      children: [
        const Text(
          'Download complete reports for the selected business and space. Amounts follow receipt dates; booking tariffs are shown separately.',
        ),
        const SizedBox(height: 20),
        AppPicker(
          label: 'Report',
          value: s.type,
          enabled: !s.busy,
          items: const [
            PickerItem('monthly', 'Monthly report'),
            PickerItem('yearly', 'Yearly report'),
            PickerItem('bookings', 'Booking collections'),
            PickerItem('cash_flow', 'Cash flow'),
          ],
          onChanged: cubit.selectType,
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${s.filter.from} → ${s.filter.until}',
                style: Theme.of(c).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: s.busy
                        ? null
                        : () async {
                            final d = await showDatePicker(
                              context: c,
                              initialDate: DateTime.parse(s.filter.from),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100, 12, 31),
                            );
                            if (d != null) {
                              cubit.configure(
                                s.filter.dates(
                                  bookingDate(DateTime(d.year, d.month)),
                                  bookingDate(DateTime(d.year, d.month + 1, 0)),
                                ),
                                'monthly',
                              );
                            }
                          },
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('Choose month'),
                  ),
                  TextButton.icon(
                    onPressed: s.busy
                        ? null
                        : () async {
                            final year = await showDialog<int>(
                              context: c,
                              builder: (d) => SimpleDialog(
                                title: const Text('Choose year'),
                                children: [
                                  for (
                                    var y = DateTime.now().year;
                                    y >= 2000;
                                    y--
                                  )
                                    SimpleDialogOption(
                                      onPressed: () => Navigator.pop(d, y),
                                      child: Text('$y'),
                                    ),
                                ],
                              ),
                            );
                            if (year != null) {
                              cubit.configure(
                                s.filter.dates('$year-01-01', '$year-12-31'),
                                'yearly',
                              );
                            }
                          },
                    icon: const Icon(Icons.date_range),
                    label: const Text('Choose year'),
                  ),
                  TextButton(
                    onPressed: s.busy
                        ? null
                        : () async {
                            final f = await chooseFinanceDates(c, s.filter);
                            if (f != null) cubit.configure(f, s.type);
                          },
                    child: const Text('Custom dates'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'PDF: summary, payment-method totals, booking breakdowns, transactions and account balances.\n\nExcel: separate sheets for summaries, bookings, account movements, income/expenses and monthly totals.',
        ),
        const SizedBox(height: 24),
        if (s.error != null) AppErrorWidget(message: s.error!),
        if (s.message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(s.message!),
          ),
        AppButton(
          label: 'Download PDF',
          icon: Icons.picture_as_pdf_outlined,
          busy: s.busy,
          onPressed: () => cubit.download('pdf'),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: 'Download Excel',
          icon: Icons.table_chart_outlined,
          secondary: true,
          onPressed: s.busy ? null : () => cubit.download('xlsx'),
        ),
      ],
    ),
  );
}
