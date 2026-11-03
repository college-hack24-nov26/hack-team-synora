/// A single chat message in the medical-assistant conversation.
class ChatMessage {
  final String id;
  String text;
  final bool isUser;
  final DateTime timestamp;
  bool streaming;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.streaming = false,
  }) : timestamp = timestamp ?? DateTime.now();
}
