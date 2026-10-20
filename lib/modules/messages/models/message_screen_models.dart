import 'package:equatable/equatable.dart';
import 'message_template.dart';

class TemplatesState extends Equatable {
  TemplatesState({
    MessageTemplateCatalog? catalog,
    this.loading = true,
    this.busy = false,
    this.error,
  }) : catalog = catalog ?? MessageTemplateCatalog();
  final MessageTemplateCatalog catalog;
  final bool loading, busy;
  final String? error;
  TemplatesState copyWith({
    MessageTemplateCatalog? catalog,
    bool? loading,
    bool? busy,
    String? error,
  }) => TemplatesState(
    catalog: catalog ?? this.catalog,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    error: error,
  );
  @override
  List<Object?> get props => [catalog, loading, busy, error];
}

enum TemplateEditorTab { write, preview }

class TemplateEditorState extends Equatable {
  const TemplateEditorState({
    this.name = '',
    this.tab = TemplateEditorTab.write,
    this.body = '',
    this.website = '',
    this.busy = false,
    this.saved = false,
    this.error,
  });
  final String name, body, website;
  final TemplateEditorTab tab;
  final bool busy, saved;
  final String? error;
  TemplateEditorState copyWith({
    TemplateEditorTab? tab,
    String? name,
    String? body,
    String? website,
    bool? busy,
    bool? saved,
    String? error,
  }) => TemplateEditorState(
    tab: tab ?? this.tab,
    name: name ?? this.name,
    body: body ?? this.body,
    website: website ?? this.website,
    busy: busy ?? this.busy,
    saved: saved ?? this.saved,
    error: error,
  );
  String get preview => MessageTemplate(
    id: 'preview',
    name: name,
    body: body,
  ).render({...sampleMessageFields, 'website': website});
  @override
  List<Object?> get props => [name, body, website, busy, saved, error, tab];
}

class MessagePreviewState extends Equatable {
  const MessagePreviewState({
    this.message = '',
    this.templateName = '',
    this.loading = true,
    this.busy = false,
    this.error,
    this.notice,
  });
  final String message, templateName;
  final bool loading, busy;
  final String? error, notice;
  MessagePreviewState copyWith({
    String? message,
    String? templateName,
    bool? loading,
    bool? busy,
    String? error,
    String? notice,
  }) => MessagePreviewState(
    message: message ?? this.message,
    templateName: templateName ?? this.templateName,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    error: error,
    notice: notice,
  );
  @override
  List<Object?> get props => [
    message,
    templateName,
    loading,
    busy,
    error,
    notice,
  ];
}
