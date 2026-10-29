import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Recovers Android's layout when an IME inset survives an app switch.
///
/// Keep the route and its form alive. Only discard the previous keyboard session;
/// fresh editable focus immediately restores normal keyboard resizing.
class AppResumeLayout extends StatefulWidget {
  const AppResumeLayout({super.key, required this.child});
  final Widget child;

  @override
  State<AppResumeLayout> createState() => _AppResumeLayoutState();
}

class _AppResumeLayoutState extends State<AppResumeLayout>
    with WidgetsBindingObserver {
  bool _awaitingFreshKeyboardFocus = false;
  bool get _enabled =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!_awaitingFreshKeyboardFocus) return;
    final context = FocusManager.instance.primaryFocus?.context;
    if (context != null &&
        (context.widget is EditableText ||
            context.findAncestorWidgetOfExactType<EditableText>() != null)) {
      setState(() => _awaitingFreshKeyboardFocus = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled) return;
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _awaitingFreshKeyboardFocus = true;
      FocusManager.instance.primaryFocus?.unfocus();
      // Some Android keyboards do not send the closing metrics while hidden.
      // Do not let a platform-channel failure interfere with form retention.
      unawaited(
        SystemChannels.textInput
            .invokeMethod<void>('TextInput.hide')
            .catchError((Object _) {}),
      );
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    final discardInsets =
        _enabled &&
        _awaitingFreshKeyboardFocus &&
        data.viewInsets != EdgeInsets.zero;
    return MediaQuery(
      data: discardInsets
          ? data.copyWith(
              viewInsets: EdgeInsets.zero,
              padding: data.viewPadding,
            )
          : data,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_focusChanged);
    super.dispose();
  }
}
