import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsCubit extends Cubit<ThemeMode> {
  SettingsCubit(this.preferences)
    : super(
        preferences.getBool('light_theme') == true
            ? ThemeMode.light
            : ThemeMode.dark,
      );
  final SharedPreferences preferences;
  Future<void> toggle() async {
    final mode = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await preferences.setBool('light_theme', mode == ThemeMode.light);
    emit(mode);
  }
}
