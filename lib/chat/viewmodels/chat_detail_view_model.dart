import 'dart:async';

import 'package:admindoorstep/chat/models/chat_message_item.dart';
import 'package:admindoorstep/chat/repositories/chat_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatDetailViewModel extends ChangeNotifier {
  ChatDetailViewModel({
    String? conversationId,
    required this.userId,
    required this.supportUserId,
    required this.categoryId,
    ChatRepository? repository,
  }) : _conversationId = (conversationId ?? '').trim().isEmpty
           ? null
           : conversationId!.trim(),
       _repository = repository ?? ChatRepository();

  static const int pageSize = 10;

  String? _conversationId;
  final String userId;
  final String supportUserId;
  final dynamic categoryId;
  final ChatRepository _repository;
  final SupabaseClient _client = Supabase.instance.client;
  final List<ChatMessageItem> _messages = [];
  RealtimeChannel? _chatChannel;

  List<ChatMessageItem> get messages => List.unmodifiable(_messages);

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isSending = false;
  bool _hasMore = true;
  bool _bootstrapped = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isSending => _isSending;
  bool get hasMore => _hasMore;
  String? get errorMessage => _errorMessage;
  String? get conversationId => _conversationId;

  Future<void> bootstrap() async {
    if (_bootstrapped) {
      return;
    }

    _bootstrapped = true;
    final activeConversationId = _conversationId;
    if (activeConversationId != null && activeConversationId.isNotEmpty) {
      try {
        await _repository.markSupportUnreadAsRead(
          activeConversationId,
          categoryId: categoryId,
        );
      } on PostgrestException catch (error) {
        _errorMessage = error.message;
      } catch (error) {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      }
      _subscribeToChatChanges(activeConversationId);
    }
    await loadInitial();
  }

  Future<void> loadInitial() async {
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    _hasMore = true;
    _messages.clear();
    notifyListeners();

    final activeConversationId = _conversationId;
    if (activeConversationId == null || activeConversationId.isEmpty) {
      _hasMore = false;
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final items = await _repository.fetchMessagesPage(
        userId: userId,
        conversationId: activeConversationId,
        offset: 0,
        limit: pageSize,
        categoryId: categoryId,
      );
      _messages.addAll(items.reversed);
      _hasMore = items.length == pageSize;
    } catch (_) {
      _errorMessage = 'Unable to load messages right now.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) {
      return;
    }

    final activeConversationId = _conversationId;
    if (activeConversationId == null || activeConversationId.isEmpty) {
      return;
    }

    _isLoadingMore = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final items = await _repository.fetchMessagesPage(
        userId: userId,
        conversationId: activeConversationId,
        offset: _messages.length,
        limit: pageSize,
        categoryId: categoryId,
      );
      _messages.insertAll(0, items.reversed);
      _hasMore = items.length == pageSize;
    } catch (_) {
      _errorMessage = 'Unable to load older messages.';
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<bool> sendMessage(String text) async {
    if (_isSending) {
      return false;
    }

    final message = text.trim();
    if (message.isEmpty) {
      return false;
    }

    _isSending = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final inserted = await _repository.sendSupportMessage(
        conversationId: _conversationId,
        userId: userId,
        supportUserId: supportUserId,
        message: message,
        categoryId: categoryId,
      );
      final insertedConversationId = inserted.conversationId.trim();
      if (insertedConversationId.isNotEmpty) {
        _conversationId = insertedConversationId;
        _subscribeToChatChanges(insertedConversationId);
      }
      _addMessageIfMissing(inserted);
      _hasMore = false;
      return true;
    } on PostgrestException catch (error) {
      _errorMessage = error.message;
      return false;
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  void _subscribeToChatChanges(String conversationId) {
    final normalizedConversationId = conversationId.trim();
    if (normalizedConversationId.isEmpty || _chatChannel != null) {
      return;
    }

    _chatChannel = _client
        .channel('chat-detail-$normalizedConversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chats',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: normalizedConversationId,
          ),
          callback: _handleChatInsert,
        )
        .subscribe();
  }

  void _handleChatInsert(PostgresChangePayload payload) {
    final message = ChatMessageItem.fromMap(payload.newRecord);
    final didAdd = _addMessageIfMissing(message);
    final isUserMessage =
        message.senderId.isNotEmpty && message.senderId == userId;
    if (isUserMessage) {
      unawaited(
        _repository.markSupportUnreadAsRead(
          message.conversationId,
          categoryId: categoryId,
        ),
      );
    }
    if (didAdd) {
      notifyListeners();
    }
  }

  bool _addMessageIfMissing(ChatMessageItem message) {
    final messageId = message.messageId.trim();
    final exists = _messages.any((item) {
      if (messageId.isNotEmpty && item.messageId == messageId) {
        return true;
      }
      return item.conversationId == message.conversationId &&
          item.senderId == message.senderId &&
          item.message == message.message &&
          item.createdAt == message.createdAt;
    });
    if (exists) {
      return false;
    }

    _messages.add(message);
    _messages.sort((a, b) {
      final aCreatedAt = a.createdAt;
      final bCreatedAt = b.createdAt;
      if (aCreatedAt == null && bCreatedAt == null) {
        return 0;
      }
      if (aCreatedAt == null) {
        return 1;
      }
      if (bCreatedAt == null) {
        return -1;
      }
      return aCreatedAt.compareTo(bCreatedAt);
    });
    return true;
  }

  @override
  void dispose() {
    final channel = _chatChannel;
    if (channel != null) {
      unawaited(_client.removeChannel(channel));
    }
    super.dispose();
  }
}
