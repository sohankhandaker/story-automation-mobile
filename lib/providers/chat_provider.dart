import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api.dart';
import '../models/chat_message.dart';

class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  final String taskId;
  ChatNotifier(this.taskId) : super([]) {
    fetchMessages();
  }

  Future<void> fetchMessages() async {
    try {
      final resp = await ApiClient.dio.get('/api/tasks/$taskId/chat');
      final data = resp.data as Map<String, dynamic>;
      final msgs = (data['messages'] as List<dynamic>)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      state = msgs;
    } catch (_) {}
  }

  Future<void> sendMessage(String message) async {
    // Optimistically add user message
    final optimistic = ChatMessage(
      id: 'optimistic-${DateTime.now().millisecondsSinceEpoch}',
      taskId: taskId,
      senderType: 'User',
      content: message,
      createdAt: DateTime.now(),
    );
    state = [...state, optimistic];

    try {
      await ApiClient.dio.post('/api/tasks/$taskId/chat', data: {'message': message});
      // Replace optimistic with real data
      await fetchMessages();
    } on Exception catch (_) {
      // Remove optimistic on failure
      state = state.where((m) => m.id != optimistic.id).toList();
      rethrow;
    }
  }
}

final chatProvider = StateNotifierProvider.family<ChatNotifier, List<ChatMessage>, String>(
  (_, taskId) => ChatNotifier(taskId),
);
