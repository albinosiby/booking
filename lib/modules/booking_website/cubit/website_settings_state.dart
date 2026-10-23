import 'package:equatable/equatable.dart';
import '../models/website_settings.dart';

class WebsiteSettingsState extends Equatable {
  const WebsiteSettingsState({
    this.saved,
    this.draft,
    this.loading = true,
    this.busy = false,
    this.savingAddress = false,
    this.addressError,
    this.error,
    this.message,
    this.revision = 0,
  });
  final WebsiteSettings? saved, draft;
  final bool loading, busy, savingAddress;
  final String? error, message, addressError;

  /// Bumped when an action rewrites several fields at once so their inputs refresh.
  final int revision;
  bool get dirty => saved != draft;
  bool get settingsDirty =>
      saved != null &&
      draft != null &&
      saved != draft!.copyWith(images: saved!.images);
  bool get addressDirty =>
      saved != null && draft != null && draft!.slug != saved!.slug;
  WebsiteSettingsState copyWith({
    WebsiteSettings? saved,
    WebsiteSettings? draft,
    bool? loading,
    bool? busy,
    bool? savingAddress,
    String? addressError,
    String? error,
    String? message,
    int? revision,
  }) => WebsiteSettingsState(
    saved: saved ?? this.saved,
    draft: draft ?? this.draft,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    savingAddress: savingAddress ?? this.savingAddress,
    addressError: addressError,
    error: error,
    message: message,
    revision: revision ?? this.revision,
  );
  @override
  List<Object?> get props => [
    saved,
    draft,
    loading,
    busy,
    savingAddress,
    addressError,
    error,
    message,
    revision,
  ];
}
