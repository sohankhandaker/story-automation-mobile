import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api.dart';
import '../core/storage.dart';
import '../models/user.dart';

class AuthState {
  final User? user;
  final bool loading;
  final String? error;

  AuthState({this.user, this.loading = false, this.error});

  AuthState copyWith({User? user, bool? loading, String? error}) =>
      AuthState(user: user ?? this.user, loading: loading ?? this.loading, error: error);

  bool get isAuthenticated => user != null;
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState()) {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final userJson = await AppStorage.getUser();
    if (userJson != null) {
      try {
        final user = User.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
        state = AuthState(user: user);
      } catch (_) {}
    }
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
        'gh_token': ghToken ?? '',
        'gh_owner': ghOwner ?? '',
        'gh_repo': ghRepo ?? '',
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
