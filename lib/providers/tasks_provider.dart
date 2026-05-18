import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api.dart';
import '../models/task.dart';

class TasksNotifier extends StateNotifier<AsyncValue<List<Task>>> {
  Timer? _timer;

  TasksNotifier() : super(const AsyncValue.loading()) {
    fetchTasks();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _silentRefresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _silentRefresh() async {
    try {
      final resp = await ApiClient.dio.get('/api/tasks', queryParameters: {'limit': 50});
      final data = resp.data as Map<String, dynamic>;
      final tasks = (data['tasks'] as List<dynamic>)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) state = AsyncValue.data(tasks);
    } catch (_) {}
  }

  Future<void> fetchTasks({String? status}) async {
    state = const AsyncValue.loading();
    try {
      final resp = await ApiClient.dio.get('/api/tasks', queryParameters: {
        if (status != null) 'status': status,
        'limit': 50,
      });
      final data = resp.data as Map<String, dynamic>;
      final tasks = (data['tasks'] as List<dynamic>)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(tasks);
    } on Exception catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<Map<String, dynamic>> createTask(String message) async {
    final resp = await ApiClient.dio.post('/api/tasks', data: {'message': message});
    await fetchTasks();
    return resp.data as Map<String, dynamic>;
  }

  Future<Task> getTask(String taskId) async {
    final resp = await ApiClient.dio.get('/api/tasks/$taskId');
    return Task.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> markReady(String taskId) async {
    await ApiClient.dio.patch('/api/tasks/$taskId/status', data: {'status': 'Ready'});
    await fetchTasks();
  }
}

final tasksProvider = StateNotifierProvider<TasksNotifier, AsyncValue<List<Task>>>(
  (_) => TasksNotifier(),
);

final taskDetailProvider = FutureProvider.family<Task, String>((ref, taskId) async {
  final resp = await ApiClient.dio.get('/api/tasks/$taskId');
  return Task.fromJson(resp.data as Map<String, dynamic>);
});
