import 'package:equatable/equatable.dart';

enum LocalDraftStatus {
  idle,
  loading,
  loadFailed,
  saving,
  saved,
  failed,
  conflict,
}

class ConfigurationDraft extends Equatable {
  const ConfigurationDraft({
    required this.baseVersion,
    required this.configuration,
    required this.navigation,
  });
  final int baseVersion;
  final Map<String, dynamic> configuration, navigation;
  Map<String, dynamic> toJson() => {
    'schema': 1,
    'base_version': baseVersion,
    'configuration': configuration,
    'navigation': navigation,
  };
  factory ConfigurationDraft.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 1) {
      throw const FormatException('Unsupported local draft');
    }
    return ConfigurationDraft(
      baseVersion: json['base_version'] as int,
      configuration: Map<String, dynamic>.from(json['configuration'] as Map),
      navigation: Map<String, dynamic>.from(json['navigation'] as Map),
    );
  }
  @override
  List<Object?> get props => [baseVersion, configuration, navigation];
}
