import 'dart:async';

import 'package:admindoorstep/chat/models/conversation_summary.dart';
import 'package:admindoorstep/chat/models/chat_user_search_result.dart';
import 'package:admindoorstep/chat/repositories/chat_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupportInboxViewModel extends ChangeNotifier {
  SupportInboxViewModel({required this.categoryId, ChatRepository? repository})
    : _repository = repository ?? ChatRepository();

  static const int pageSize = 10;

  final dynamic categoryId;
  final ChatRepository _repository;
  final SupabaseClient _client = Supabase.instance.client;
  final List<ConversationSummary> _conversations = [];
  RealtimeChannel? _conversationChannel;

  List<ConversationSummary> get conversations =>
      List.unmodifiable(_conversations);

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isSearchingUser = false;
  bool _hasMore = true;
  String? _errorMessage;
  String? _searchErrorMessage;
  final List<ChatUserSearchResult> _searchedUsers = [];

  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get errorMessage => _errorMessage;
  bool get isSearchingUser => _isSearchingUser;
  String? get searchErrorMessage => _searchErrorMessage;
  List<ChatUserSearchResult> get searchedUsers =>
      List.unmodifiable(_searchedUsers);

  Future<void> searchUserByEmail(String email) async {
    final normalizedEmail = email.trim();
    if (_isSearchingUser) {
      return;
    }

    if (normalizedEmail.isEmpty) {
      _searchedUsers.clear();
      _searchErrorMessage = 'Enter user email';
      notifyListeners();
      return;
    }

    _isSearchingUser = true;
    _searchErrorMessage = null;
    _searchedUsers.clear();
    notifyListeners();

    try {
      final users = await _repository.findUsersByEmailPrefix(
        normalizedEmail,
        categoryId,
      );
      if (users.isEmpty) {
        _searchErrorMessage = 'No users found for this email prefix.';
      } else {
        _searchedUsers.addAll(users);
      }
    } on PostgrestException catch (error) {
      _searchErrorMessage = error.message;
    } catch (error) {
      _searchErrorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      _isSearchingUser = false;
      notifyListeners();
    }
  }

  void clearSearchResult() {
    _searchedUsers.clear();
    _searchErrorMessage = null;
    notifyListeners();
  }

  Future<void> loadInitial() async {
    if (_isLoading) {
      return;
    }

    _subscribeToConversationChanges();
    _isLoading = true;
    _errorMessage = null;
    _hasMore = true;
    _conversations.clear();
    notifyListeners();

    try {
      final items = await _repository.fetchInboxPage(
        offset: 0,
        limit: pageSize,
        categoryId: categoryId,
      );
      _conversations.addAll(items);
      _hasMore = items.length == pageSize;
    } on PostgrestException catch (error) {
      _errorMessage = error.message;
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) {
      return;
    }

    _isLoadingMore = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final items = await _repository.fetchInboxPage(
        offset: _conversations.length,
        limit: pageSize,
        categoryId: categoryId,
      );
      _conversations.addAll(items);
      _hasMore = items.length == pageSize;
    } on PostgrestException catch (error) {
      _errorMessage = error.message;
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<bool> markConversationRead(ConversationSummary conversation) async {
    final index = _conversations.indexWhere(
      (item) => item.conversationId == conversation.conversationId,
    );
    if (index == -1) {
      return true;
    }

    final existing = _conversations[index];
    _conversations[index] = existing.copyWith(supportUnread: 0);
    notifyListeners();

    try {
      await _repository.markSupportUnreadAsRead(
        conversation.conversationId,
        categoryId: categoryId,
      );
      return true;
    } catch (error) {
      _conversations[index] = existing;
      _errorMessage = error is PostgrestException
          ? error.message
          : 'Unable to mark conversation as read.';
      notifyListeners();
      return false;
    }
  }

  void _subscribeToConversationChanges() {
    if (_conversationChannel != null || categoryId == null) {
      return;
    }

    _conversationChannel = _client
        .channel('support-inbox-$categoryId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'category_id',
            value: categoryId,
          ),
          callback: _handleConversationChange,
        )
        .subscribe();
  }

  Future<void> _handleConversationChange(PostgresChangePayload payload) async {
    final record = payload.eventType == PostgresChangeEvent.delete
        ? payload.oldRecord
        : payload.newRecord;
    final conversationId = (record['conversation_id'] ?? '').toString().trim();
    if (conversationId.isEmpty) {
      return;
    }

    if (payload.eventType == PostgresChangeEvent.delete) {
      _removeConversation(conversationId);
      return;
    }

    final existingIndex = _conversations.indexWhere(
      (item) => item.conversationId == conversationId,
    );
    final messageId = (record['message_id'] ?? '').toString();
    if (existingIndex != -1 &&
        messageId == _conversations[existingIndex].messageId) {
      _conversations[existingIndex] = _conversations[existingIndex].copyWith(
        supportUnread:
            int.tryParse((record['support_unread'] ?? 0).toString()) ?? 0,
        modifiedAt: DateTime.tryParse((record['modified_at'] ?? '').toString()),
      );
      _sortConversations();
      notifyListeners();
      return;
    }

    try {
      final summary = await _repository.fetchConversationSummary(
        conversationId: conversationId,
        categoryId: categoryId,
      );
      if (summary == null) {
        _removeConversation(conversationId);
        return;
      }
      _upsertConversation(summary);
    } catch (error) {
      debugPrint('Realtime conversation refresh failed: $error');
    }
  }

  void _upsertConversation(ConversationSummary summary) {
    final existingIndex = _conversations.indexWhere(
      (item) => item.conversationId == summary.conversationId,
    );
    if (existingIndex != -1) {
      _conversations[existingIndex] = summary;
    } else {
      _conversations.insert(0, summary);
    }
    _sortConversations();
    notifyListeners();
  }

  void _sortConversations() {
    _conversations.sort((a, b) {
      final aModifiedAt = a.modifiedAt;
      final bModifiedAt = b.modifiedAt;
      if (aModifiedAt == null && bModifiedAt == null) {
        return 0;
      }
      if (aModifiedAt == null) {
        return 1;
      }
      if (bModifiedAt == null) {
        return -1;
      }
      return bModifiedAt.compareTo(aModifiedAt);
    });
  }

  void _removeConversation(String conversationId) {
    final beforeLength = _conversations.length;
    _conversations.removeWhere((item) => item.conversationId == conversationId);
    if (_conversations.length != beforeLength) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    final channel = _conversationChannel;
    if (channel != null) {
      unawaited(_client.removeChannel(channel));
    }
    super.dispose();
  }
}
