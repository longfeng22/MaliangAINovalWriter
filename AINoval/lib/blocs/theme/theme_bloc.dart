import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_event.dart';
import 'theme_state.dart';

class ThemeBloc extends Bloc<ThemeEvent, ThemeState> {
  static const String themeKey = 'theme_mode';
  
  ThemeBloc() : super(const ThemeState(themeMode: ThemeMode.system)) {
    on<ThemeInitialize>(_onThemeInitialize);
    on<ThemeChanged>(_onThemeChanged);
    on<ThemeToggled>(_onThemeToggled);
  }

  Future<void> _onThemeInitialize(
    ThemeInitialize event,
    Emitter<ThemeState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeModeString = prefs.getString(themeKey);
      
      ThemeMode themeMode = ThemeMode.system;
      if (themeModeString != null) {
        switch (themeModeString) {
          case 'light':
            themeMode = ThemeMode.light;
            break;
          case 'dark':
            themeMode = ThemeMode.dark;
            break;
          case 'system':
            themeMode = ThemeMode.system;
            break;
        }
      }
      
      emit(state.copyWith(
        themeMode: themeMode,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        themeMode: ThemeMode.system,
        isLoading: false,
      ));
    }
  }

  Future<void> _onThemeChanged(
    ThemeChanged event,
    Emitter<ThemeState> emit,
  ) async {
    emit(state.copyWith(themeMode: event.themeMode));
    
    try {
      final prefs = await SharedPreferences.getInstance();
      String themeModeString;
      switch (event.themeMode) {
        case ThemeMode.light:
          themeModeString = 'light';
          break;
        case ThemeMode.dark:
          themeModeString = 'dark';
          break;
        case ThemeMode.system:
          themeModeString = 'system';
          break;
      }
      await prefs.setString(themeKey, themeModeString);
    } catch (e) {
      // 静默处理存储错误
    }
  }

  Future<void> _onThemeToggled(
    ThemeToggled event,
    Emitter<ThemeState> emit,
  ) async {
    // 简化为“黑/白”二态切换：浅色 <-> 深色
    final ThemeMode newThemeMode =
        (state.themeMode == ThemeMode.dark) ? ThemeMode.light : ThemeMode.dark;
    add(ThemeChanged(newThemeMode));
  }
}