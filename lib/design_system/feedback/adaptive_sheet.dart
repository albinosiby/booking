import 'package:flutter/material.dart';

/// Window width from which sheets open as centered dialogs instead.
const adaptiveSheetDialogWidth = 600.0;

bool _dialogLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= adaptiveSheetDialogWidth;

class _InDialog extends InheritedWidget {
  const _InDialog({required super.child});
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_InDialog>() != null;
  @override
  bool updateShouldNotify(_InDialog old) => false;
}

/// Shows [builder] as a bottom sheet on phones and a centered dialog on wide
/// windows, where a sheet stretched across the screen is awkward with a mouse.
///
/// [showDragHandle] defaults to on for dismissible sheets; pass false for
/// content that draws its own header. [showClose] is the dialog's close
/// button and defaults to [isDismissible].
///
/// Content calls `Navigator.pop(context, value)` in both layouts. Content that
/// scrolls itself should use [AdaptiveSheetBody] and pass `scrollable: false`.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool scrollable = true,
  bool? showClose,
  bool? showDragHandle,
  double maxWidth = 520,
}) {
  if (!_dialogLayout(context)) {
    return showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: showDragHandle ?? isDismissible,
      isDismissible: isDismissible,
      enableDrag: isDismissible,
      builder: builder,
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    builder: (dialog) {
      final height = MediaQuery.sizeOf(dialog).height;
      final content = Builder(builder: builder);
      return _InDialog(
        child: Dialog(
          key: const ValueKey('adaptive-sheet-dialog'),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 32,
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: height * .86,
            ),
            child: Stack(
              children: [
                if (scrollable)
                  SingleChildScrollView(child: content)
                else
                  content,
                if (showClose ?? isDismissible)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: IconButton(
                      key: const ValueKey('adaptive-sheet-close'),
                      tooltip: 'Close',
                      onPressed: () => Navigator.maybePop(dialog),
                      icon: const Icon(Icons.close),
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

/// Scrolling body for [showAdaptiveSheet] content.
///
/// Phones get a draggable sheet that opens at [initialChildSize]. In a dialog
/// the builder receives `shrink: true`; the list it returns should set
/// `shrinkWrap: shrink` so the dialog fits its content.
class AdaptiveSheetBody extends StatelessWidget {
  const AdaptiveSheetBody({
    super.key,
    required this.builder,
    this.initialChildSize = .65,
    this.maxChildSize = 1,
  });
  final Widget Function(
    BuildContext context,
    ScrollController controller,
    bool shrink,
  )
  builder;
  final double initialChildSize, maxChildSize;
  @override
  Widget build(BuildContext context) => _InDialog.of(context)
      ? _DialogScroll(builder: builder)
      : DraggableScrollableSheet(
          expand: false,
          initialChildSize: initialChildSize,
          maxChildSize: maxChildSize,
          builder: (context, controller) => builder(context, controller, false),
        );
}

class _DialogScroll extends StatefulWidget {
  const _DialogScroll({required this.builder});
  final Widget Function(BuildContext, ScrollController, bool) builder;
  @override
  State<_DialogScroll> createState() => _DialogScrollState();
}

class _DialogScrollState extends State<_DialogScroll> {
  final controller = ScrollController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, controller, true);
}
