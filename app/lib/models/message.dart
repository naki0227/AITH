class Message {
  final String text; // For user messages or fallback
  final bool isUser;
  final String? imagePath;
  final DateTime timestamp;
  final Map<String, dynamic>? challenge;
  final List<dynamic>? blocks; // For AI messages

  Message({
    required this.text,
    required this.isUser,
    this.imagePath,
    required this.timestamp,
    this.challenge,
    this.blocks,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'imagePath': imagePath,
    'timestamp': timestamp.toIso8601String(),
    'challenge': challenge,
    'blocks': blocks,
  };

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      text: json['text'],
      isUser: json['isUser'],
      imagePath: json['imagePath'],
      timestamp: DateTime.parse(json['timestamp']),
      challenge: json['challenge'],
      blocks: json['blocks'],
    );
  }
}
