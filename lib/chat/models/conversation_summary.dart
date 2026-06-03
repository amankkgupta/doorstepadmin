class ConversationSummary {
  const ConversationSummary({
    required this.conversationId,
    required this.userId,
    required this.categoryId,
    required this.messageId,
    required this.supportUnread,
    required this.modifiedAt,
    required this.userName,
    required this.userEmail,
    required this.latestMessagePreview,
  });

  final String conversationId;
  final String userId;
  final String categoryId;
  final String messageId;
  final int supportUnread;
  final DateTime? modifiedAt;
  final String userName;
  final String userEmail;
  final String latestMessagePreview;

  ConversationSummary copyWith({
    int? supportUnread,
    String? latestMessagePreview,
    DateTime? modifiedAt,
  }) {
    return ConversationSummary(
      conversationId: conversationId,
      userId: userId,
      categoryId: categoryId,
      messageId: messageId,
      supportUnread: supportUnread ?? this.supportUnread,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      userName: userName,
      userEmail: userEmail,
      latestMessagePreview: latestMessagePreview ?? this.latestMessagePreview,
    );
  }
}
