import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api.dart';
import '../core/storage.dart';
import '../models/user.dart';

class AuthState {
  final User? user;
  final bool loading;
  final bool initializing;
  final String? error;

  AuthState({
    this.user,
    this.loading = false,
    this.initializing = false,
    this.error,
  });

  AuthState copyWith({
    User? user,
    bool? loading,
    bool? initializing,
    String? error,
  }) =>
      AuthState(
        user: user ?? this.user,
        loading: loading ?? this.loading,
        initializing: initializing ?? this.initializing,
        error: error,
      );

  bool get isAuthenticated => user != null;
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState(initializing: true)) {
    ApiClient.onUnauthorized = () => state = AuthState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final userJson = await AppStorage.getUser();
    if (userJson != null) {
      try {
        final user = User.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
        state = AuthState(user: user, initializing: false);
        return;
      } catch (_) {}
    }
    state = state.copyWith(initializing: false);
  }

  Future<void> register(String name, String email, String password) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final resp = await ApiClient.dio.post('/api/auth/register', data: {
        'name': name,
        'email': email,
        'password': password,
      });
      await _handleAuthResponse(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: e.userMessage);
    } on Exception catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final resp = await ApiClient.dio.post('/api/auth/login', data: {
        'email': email,
        'password': password,
      });
      await _handleAuthResponse(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: e.userMessage);
    } on Exception catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> _handleAuthResponse(Map<String, dynamic> data) async {
    final token = data['access_token'] as String;
    final user = User.fromJson(data['user'] as Map<String, dynamic>);
    await AppStorage.saveToken(token);
    await AppStorage.saveUser(jsonEncode(data['user']));
    state = AuthState(user: user);
  }

  Future<void> updateSettings(
    String? githubUsername,
    List<Map<String, dynamic>> reviewerList, {
    String? ghToken,
    String? ghOwner,
    String? ghRepo,
    int? ghProjectNumber,
  }) async {
    try {
      final resp = await ApiClient.dio.patch('/api/auth/settings', data: {
        if (githubUsername != null) 'github_username': githubUsername,
        'reviewer_list': reviewerList,
        if (ghToken != null && ghToken.isNotEmpty) 'gh_token': ghToken,
        if (ghOwner != null && ghOwner.isNotEmpty) 'gh_owner': ghOwner,
        if (ghRepo != null && ghRepo.isNotEmpty) 'gh_repo': ghRepo,
        if (ghProjectNumber != null) 'gh_project_number': ghProjectNumber,
      });
      final user = User.fromJson(resp.data as Map<String, dynamic>);
      await AppStorage.saveUser(jsonEncode(resp.data));
      state = AuthState(user: user);
    } catch (_) {}
  }

  Future<void> logout() async {
    await AppStorage.clear();
    state = AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (_) => AuthNotifier(),
);
