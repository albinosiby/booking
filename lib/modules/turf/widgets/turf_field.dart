import '../../../design_system/components/configuration_field.dart';

typedef TurfField = ConfigurationField;

String? turfName(String? value) =>
    value == null || value.trim().length < 2 || value.trim().length > 100
    ? 'Use 2–100 characters'
    : null;
