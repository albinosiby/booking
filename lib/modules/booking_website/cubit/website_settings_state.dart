import 'package:equatable/equatable.dart';
import '../models/website_settings.dart';

class WebsiteSettingsState extends Equatable {
  const WebsiteSettingsState({
    this.saved,
    this.draft,
    this.loading = true,
    this.busy = false,
    this.error,
    this.message,
  });
  final WebsiteSettings? saved, draft;
  final bool loading, busy;
  final String? error, message;
  bool get dirty => saved != draft;
  WebsiteSettingsState copyWith({
    WebsiteSettings? saved,
    WebsiteSettings? draft,
    bool? loading,
    bool? busy,
    String? error,
    String? message,
  }) => WebsiteSettingsState(
    saved: saved ?? this.saved,
    draft: draft ?? this.draft,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    error: error,
    message: message,
  );
  @override
  List<Object?> get props => [saved, draft, loading, busy, error, message];
}
