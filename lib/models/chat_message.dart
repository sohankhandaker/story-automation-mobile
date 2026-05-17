class ChatMessage {
  final String id;
  final String? taskId;
  final String senderType; // User / Agent / System
  final String content;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    this.taskId,
    required this.senderType,
    required this.content,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        taskId: j['task_id'] as String?,
        senderType: j['sender_type'] as String,
        content: j['content'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  bool get isUser => senderType == 'User';
  bool get isAgent => senderType == 'Agent';
  bool get isSystem => senderType == 'System';
}
