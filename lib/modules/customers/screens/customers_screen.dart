import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/customer_cubits.dart';
import '../models/customer_models.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  late final cubit = getIt<CustomerListCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  final search = TextEditingController();
  @override
  void initState() {
    super.initState();
    cubit.load();
  }

  @override
  void dispose() {
    search.dispose();
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<CustomerListCubit, CustomerListModel>(
    bloc: cubit,
    listener: (context, state) {
      if (search.text != state.query) search.text = state.query;
    },
    builder: (context, s) => AppPage(
      back: true,
      title: 'Customers',
      eyebrow: 'CUSTOMER DIRECTORY',
      subtitle: 'Find a phone number and view its booking history.',
      scrollId: 'customers',
      maxWidth: 800,
      children: [
        TextField(
          controller: search,
          keyboardType: TextInputType.phone,
          maxLength: 50,
          onChanged: cubit.search,
          decoration: InputDecoration(
            labelText: 'Search phone number',
            hintText: 'Enter the first digits',
            prefixIcon: const Icon(Icons.search),
            counterText: '',
            suffixIcon: IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                search.clear();
                cubit.search('');
              },
              icon: const Icon(Icons.close),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Search by the beginning of a phone number, including its country code when saved.',
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: cubit.refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ),
        if (s.loading) AppLoadingState(initial: s.items.isEmpty),
        if (s.error != null)
          AppErrorWidget(message: s.error!, onRetry: cubit.refresh),
        if (!s.loading && s.error == null && s.items.isEmpty)
          AppEmptyState(
            showCard: false,
            title: s.query.isEmpty
                ? 'No customers yet'
                : 'No matching phone numbers',
            message: s.query.isEmpty
                ? 'Customers appear here when bookings are created.'
                : 'Check the number or clear your search.',
            icon: Icons.people_outline,
          ),
        for (final customer in s.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              onTap: () => context.push('/customers/${customer.id}'),
              child: Row(
                children: [
                  const Icon(Icons.person_outline),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.phone,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(customer.name),
                        if (customer.recordCount > 1) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${customer.recordCount} linked customer records',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        if (s.next != null)
          AppButton(
            label: 'Load more customers',
            busy: s.loadingMore,
            onPressed: s.loading || s.loadingMore
                ? null
                : () => cubit.load(more: true),
          ),
      ],
    ),
  );
}
