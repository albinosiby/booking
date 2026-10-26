import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../cubit/booking_website_link_cubit.dart';
import '../models/booking_website_link.dart';
import '../repositories/booking_website_link_repository.dart';

Future<void> showBookingWebsiteLink(
  BuildContext context,
  WorkspaceSession session,
  BookingWebsiteLinkRepository repository,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 640),
  builder: (sheet) => BlocProvider(
    create: (_) => BookingWebsiteLinkCubit(session, repository)..load(),
    child: BookingWebsiteLinkSheet(
      onConfigure: () {
        Navigator.of(sheet).pop();
        context.push('/profile/booking-website');
      },
    ),
  ),
);

class BookingWebsiteLinkSheet extends StatelessWidget {
  const BookingWebsiteLinkSheet({super.key, required this.onConfigure});
  final VoidCallback onConfigure;
  String status(BookingWebsiteLink link) => switch (link.status) {
    'published' =>
      link.available
          ? 'Your public booking website is ready.'
          : 'The website address is unavailable. Check website settings.',
    'paused' =>
      link.available
          ? 'Online bookings are paused. Customers can still view the website.'
          : 'Online bookings are paused. The website address is unavailable.',
    'unpublished' => 'Your booking website is unpublished.',
    'draft' => 'Your booking website is a draft. Publish it before sharing.',
    _ => 'Create and publish your booking website to get a link.',
  };
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<BookingWebsiteLinkCubit, BookingWebsiteLinkState>(
        builder: (context, state) {
          final cubit = context.read<BookingWebsiteLinkCubit>(),
              link = state.link;
          final enabled =
              !state.loading && !state.working && link?.available == true;
          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Booking website',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    if (state.loading || state.working)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: LinearProgressIndicator(),
                      ),
                    if (link != null) ...[
                      Text(status(link)),
                      if (link.url != null) ...[
                        const SizedBox(height: 16),
                        SelectableText(
                          link.url!,
                          key: const ValueKey('home-booking-website-url'),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: enabled ? cubit.open : null,
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Open website'),
                          ),
                          OutlinedButton.icon(
                            onPressed: enabled ? cubit.copy : null,
                            icon: const Icon(Icons.copy_outlined),
                            label: const Text('Copy link'),
                          ),
                          if (link.canManage)
                            TextButton.icon(
                              onPressed: state.working ? null : onConfigure,
                              icon: const Icon(Icons.design_services_outlined),
                              label: const Text('Design website'),
                            ),
                        ],
                      ),
                    ],
                    if (state.message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(state.message!),
                        ),
                      ),
                    if (state.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: AppErrorWidget(
                          message: state.error!,
                          onRetry: cubit.authorized && !state.working
                              ? cubit.load
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
