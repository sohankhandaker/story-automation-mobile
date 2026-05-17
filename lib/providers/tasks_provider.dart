import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api.dart';
import '../models/task.dart';

class TasksNotifier extends StateNotifier<AsyncValue<List<Task>>> {
  TasksNotifier() : super(const AsyncValue.loading()) {
    fetchTasks();
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

// Single task poller — used in chat screen to refresh task status
final taskDetailProvider = FutureProvider.family<Task, String>((ref, taskId) async {
  final resp = await ApiClient.dio.get('/api/tasks/$taskId');
  return Task.fromJson(resp.data as Map<String, dynamic>);
});
