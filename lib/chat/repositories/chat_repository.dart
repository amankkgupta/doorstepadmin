import 'dart:async';

import 'package:admindoorstep/chat/models/chat_message_item.dart';
import 'package:admindoorstep/chat/models/chat_user_search_result.dart';
import 'package:admindoorstep/chat/models/conversation_summary.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatRepository {
  ChatRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<ConversationSummary>> fetchInboxPage({
    required int offset,
    required int limit,
    required dynamic categoryId,
  }) async {
    if (categoryId == null) {
      return const [];
    }

    final rows = await _fetchConversationRows(
      offset: offset,
      limit: limit,
      categoryId: categoryId,
    );
    debugPrint('Fetched conversation rows: $rows');

    final conversations = List<Map<String, dynamic>>.from(rows);
    final userIds = conversations
        .map((row) => (row['user_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final messageIds = conversations
        .map((row) => (row['message_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final userMap = await _fetchUsers(userIds);
    final messageMap = await _fetchMessagesByIds(messageIds);

    return conversations
        .map((row) => _summaryFromRow(row, userMap, messageMap))
        .toList();
  }

  Future<ConversationSummary?> fetchConversationSummary({
    required String conversationId,
    required dynamic categoryId,
  }) async {
    final normalizedConversationId = conversationId.trim();
    if (normalizedConversationId.isEmpty || categoryId == null) {
      return null;
    }

    try {
      final row = await _client
          .from('conversations')
          .select(
            'conversation_id, user_id, message_id, support_unread, modified_at',
          )
          .eq('conversation_id', normalizedConversationId)
          .eq('category_id', categoryId)
          .maybeSingle();

      if (row == null) {
        return null;
      }

      final userId = (row['user_id'] ?? '').toString();
      final messageId = (row['message_id'] ?? '').toString();
      final userMap = await _fetchUsers(userId.isEmpty ? [] : [userId]);
      final messageMap = await _fetchMessagesByIds(
        messageId.isEmpty ? [] : [messageId],
      );
      return _summaryFromRow(row, userMap, messageMap);
    } on PostgrestException {
      rethrow;
    } catch (error) {
      debugPrint('Fetch conversation summary failed: $error');
      throw Exception('Unable to fetch conversation.');
    }
  }

  Future<List<dynamic>> _fetchConversationRows({
    required int offset,
    required int limit,
    required dynamic categoryId,
  }) async {
    try {
      debugPrint(
        'Fetching conversations for category_id=$categoryId, '
        'offset=$offset, limit=$limit',
      );

      final response = await _client
          .from('conversations')
          .select(
            'conversation_id, user_id, message_id, support_unread, modified_at',
          )
          .eq('category_id', categoryId)
          .order('modified_at', ascending: false)
          .range(offset, offset + limit - 1);

      debugPrint('Conversations response: $response');
      return response;
    } on PostgrestException {
      rethrow;
    } catch (error) {
      debugPrint('Fetch conversations failed: $error');
      throw Exception('Unable to fetch conversations.');
    }
  }

  ConversationSummary _summaryFromRow(
    Map<String, dynamic> row,
    Map<String, Map<String, dynamic>> userMap,
    Map<String, Map<String, dynamic>> messageMap,
  ) {
    final userId = (row['user_id'] ?? '').toString();
    final messageId = (row['message_id'] ?? '').toString();
    final user = userMap[userId] ?? const <String, dynamic>{};
    final message = messageMap[messageId] ?? const <String, dynamic>{};

    return ConversationSummary(
      conversationId: (row['conversation_id'] ?? '').toString(),
      userId: userId,
      messageId: messageId,
      supportUnread: int.tryParse((row['support_unread'] ?? 0).toString()) ?? 0,
      modifiedAt: DateTime.tryParse((row['modified_at'] ?? '').toString()),
      userName: _pickUserName(user, userId),
      userEmail: (user['email'] ?? '').toString(),
      latestMessagePreview: (message['message'] ?? '').toString(),
    );
  }

  Future<void> markSupportUnreadAsRead(
    String conversationId, {
    required dynamic categoryId,
  }) async {
    if (conversationId.isEmpty || categoryId == null) {
      return;
    }

    try {
      await _client
          .from('conversations')
          .update({'support_unread': 0})
          .eq('conversation_id', conversationId)
          .eq('category_id', categoryId);
    } on PostgrestException {
      rethrow;
    } catch (_) {
      throw Exception('Unable to update support unread count.');
    }
  }

  Future<List<ChatMessageItem>> fetchMessagesPage({
    required String userId,
    required String conversationId,
    required int offset,
    required int limit,
    required dynamic categoryId,
  }) async {
    final canReadConversation = await _isConversationInCategory(
      conversationId: conversationId,
      categoryId: categoryId,
    );
    if (!canReadConversation) {
      return const [];
    }

    final baseQuery = _client
        .from('chats')
        .select('message_id, message, sender_id, conversation_id, created_at');

    final filteredQuery = baseQuery.eq('conversation_id', conversationId);

    final response = await filteredQuery
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return List<Map<String, dynamic>>.from(
      response,
    ).map(ChatMessageItem.fromMap).toList();
  }

  Future<ChatMessageItem> sendSupportMessage({
    String? conversationId,
    required String userId,
    required String supportUserId,
    required String message,
    required dynamic categoryId,
  }) async {
    try {
      final resolvedConversationId = await _resolveConversationId(
        userId: userId,
        conversationId: conversationId,
        categoryId: categoryId,
      );

      final inserted = await _client
          .from('chats')
          .insert({
            'conversation_id': resolvedConversationId,
            'sender_id': supportUserId,
            'message': message,
          })
          .select('message_id, message, sender_id, conversation_id, created_at')
          .single();

      final insertedMessage = ChatMessageItem.fromMap(inserted);

      try {
        final conversation = await _client
            .from('conversations')
            .select('user_unread')
            .eq('conversation_id', resolvedConversationId)
            .eq('category_id', categoryId)
            .maybeSingle();

        final currentUserUnread =
            int.tryParse((conversation?['user_unread'] ?? 0).toString()) ?? 0;

        await _client
            .from('conversations')
            .update({
              'message_id': insertedMessage.messageId,
              'modified_at': DateTime.now().toIso8601String(),
              'user_unread': currentUserUnread + 1,
              'support_unread': 0,
            })
            .eq('conversation_id', resolvedConversationId)
            .eq('category_id', categoryId);
      } on PostgrestException {
        rethrow;
      } catch (_) {
        throw Exception('Unable to update conversation after sending message.');
      }

      unawaited(
        _sendSupportMessageNotification(userId: userId, title: message),
      );

      return insertedMessage;
    } on PostgrestException {
      rethrow;
    } catch (_) {
      throw Exception('Unable to send support message.');
    }
  }

  Future<List<ChatUserSearchResult>> findUsersByEmailPrefix(
    String emailPrefix,
    dynamic categoryId,
  ) async {
    final normalizedEmail = emailPrefix.trim().toLowerCase();
    if (normalizedEmail.isEmpty || categoryId == null) {
      return const [];
    }

    try {
      final rows = await _client
          .from('users')
          .select('user_id, name, email')
          .ilike('email', '$normalizedEmail%')
          .order('email', ascending: true)
          .limit(20);

      final users = List<Map<String, dynamic>>.from(rows)
          .where((row) => (row['user_id'] ?? '').toString().trim().isNotEmpty)
          .toList();

      if (users.isEmpty) {
        return const [];
      }

      final userIds = users
          .map((row) => (row['user_id'] ?? '').toString().trim())
          .where((value) => value.isNotEmpty)
          .toList();
      final conversationIdByUserId = await _fetchConversationIdsByUserIds(
        userIds,
        categoryId: categoryId,
      );

      return users.map((user) {
        final userId = (user['user_id'] ?? '').toString().trim();
        return ChatUserSearchResult(
          userId: userId,
          userName: _pickUserName(user, userId),
          userEmail: (user['email'] ?? '').toString(),
          conversationId: conversationIdByUserId[userId],
        );
      }).toList();
    } on PostgrestException {
      rethrow;
    } catch (_) {
      throw Exception('Unable to search user by email.');
    }
  }

  Future<Map<String, String>> _fetchConversationIdsByUserIds(
    List<String> userIds, {
    required dynamic categoryId,
  }) async {
    if (userIds.isEmpty || categoryId == null) {
      return const {};
    }

    try {
      final rows = await _client
          .from('conversations')
          .select('user_id, conversation_id, modified_at')
          .inFilter('user_id', userIds)
          .eq('category_id', categoryId)
          .order('modified_at', ascending: false);

      final map = <String, String>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final userId = (row['user_id'] ?? '').toString().trim();
        final conversationId = (row['conversation_id'] ?? '').toString().trim();
        if (userId.isEmpty ||
            conversationId.isEmpty ||
            map.containsKey(userId)) {
          continue;
        }
        map[userId] = conversationId;
      }
      return map;
    } catch (_) {
      return const {};
    }
  }

  Future<String?> findConversationIdByUserId(
    String userId, {
    required dynamic categoryId,
  }) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty || categoryId == null) {
      return null;
    }

    try {
      final row = await _client
          .from('conversations')
          .select('conversation_id')
          .eq('user_id', normalizedUserId)
          .eq('category_id', categoryId)
          .order('modified_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final conversationId = (row?['conversation_id'] ?? '').toString().trim();
      return conversationId.isEmpty ? null : conversationId;
    } on PostgrestException {
      rethrow;
    } catch (_) {
      throw Exception('Unable to find conversation for user.');
    }
  }

  Future<String> _resolveConversationId({
    required String userId,
    required dynamic categoryId,
    String? conversationId,
  }) async {
    final existingConversationId = (conversationId ?? '').trim();
    if (existingConversationId.isNotEmpty) {
      final canUseConversation = await _isConversationInCategory(
        conversationId: existingConversationId,
        categoryId: categoryId,
      );
      if (!canUseConversation) {
        throw Exception('Unable to find conversation for this category.');
      }
      return existingConversationId;
    }

    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty || categoryId == null) {
      throw Exception('User id is required to send message.');
    }

    final foundConversationId = await findConversationIdByUserId(
      normalizedUserId,
      categoryId: categoryId,
    );
    if (foundConversationId != null && foundConversationId.isNotEmpty) {
      return foundConversationId;
    }

    try {
      final nowIso = DateTime.now().toIso8601String();
      final insertedConversation = await _client
          .from('conversations')
          .insert({
            'user_id': normalizedUserId,
            'category_id': categoryId,
            'user_unread': 0,
            'support_unread': 0,
            'created_at': nowIso,
            'modified_at': nowIso,
          })
          .select('conversation_id')
          .single();

      final createdConversationId =
          (insertedConversation['conversation_id'] ?? '').toString().trim();
      if (createdConversationId.isEmpty) {
        throw Exception('Unable to create conversation.');
      }

      return createdConversationId;
    } on PostgrestException {
      rethrow;
    } catch (_) {
      throw Exception('Unable to create conversation.');
    }
  }

  Future<bool> _isConversationInCategory({
    required String conversationId,
    required dynamic categoryId,
  }) async {
    final normalizedConversationId = conversationId.trim();
    if (normalizedConversationId.isEmpty || categoryId == null) {
      return false;
    }

    try {
      final row = await _client
          .from('conversations')
          .select('conversation_id')
          .eq('conversation_id', normalizedConversationId)
          .eq('category_id', categoryId)
          .maybeSingle();

      return row != null;
    } on PostgrestException {
      rethrow;
    } catch (_) {
      throw Exception('Unable to find conversation for this category.');
    }
  }

  Future<Map<String, Map<String, dynamic>>> _fetchUsers(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) {
      return const {};
    }

    try {
      final rows = await _client
          .from('users')
          .select('user_id, name, email')
          .inFilter('user_id', userIds);

      return {
        for (final row in List<Map<String, dynamic>>.from(rows))
          (row['user_id'] ?? '').toString(): row,
      };
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, Map<String, dynamic>>> _fetchMessagesByIds(
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) {
      return const {};
    }

    try {
      final rows = await _client
          .from('chats')
          .select('message_id, message')
          .inFilter('message_id', messageIds);

      return {
        for (final row in List<Map<String, dynamic>>.from(rows))
          (row['message_id'] ?? '').toString(): row,
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> _sendSupportMessageNotification({
    required String userId,
    required String title,
  }) async {
    try {
      final normalizedUserId = userId.trim();
      final notificationTitle = title.trim();
      if (normalizedUserId.isEmpty || notificationTitle.isEmpty) {
        return;
      }

      final fcmData = await _client
          .from('fcmtokens')
          .select('fcmtoken, is_active')
          .eq('user_id', normalizedUserId)
          .maybeSingle();

      if (fcmData == null || !_isFalse(fcmData['is_active'])) {
        return;
      }

      final token = (fcmData['fcmtoken'] ?? '').toString().trim();
      if (token.isEmpty) {
        return;
      }

      await _client.functions.invoke(
        'send-notification',
        body: {'token': token, 'title': notificationTitle},
      );
    } catch (error) {
      debugPrint('Chat FCM notification failed: $error');
    }
  }

  bool _isFalse(Object? value) {
    if (value is bool) {
      return !value;
    }

    return value?.toString().trim().toLowerCase() == 'false';
  }

  String _pickUserName(Map<String, dynamic> user, String fallbackUserId) {
    final candidates = [user['name'], user['email'], fallbackUserId];

    for (final value in candidates) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }

    return 'Unknown User';
  }
}
