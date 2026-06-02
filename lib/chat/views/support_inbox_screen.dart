import 'package:admindoorstep/auth/viewmodels/auth_view_model.dart';
import 'package:admindoorstep/chat/models/conversation_summary.dart';
import 'package:admindoorstep/chat/viewmodels/chat_detail_view_model.dart';
import 'package:admindoorstep/chat/viewmodels/support_inbox_view_model.dart';
import 'package:admindoorstep/chat/views/chat_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SupportInboxScreen extends StatelessWidget {
  const SupportInboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categoryId = context.watch<AuthViewModel>().user?.categoryId;
    debugPrint('Support inbox admin category_id: $categoryId');

    return ChangeNotifierProvider(
      key: ValueKey(categoryId ?? 'all-categories'),
      create: (_) =>
          SupportInboxViewModel(categoryId: categoryId)..loadInitial(),
      child: const _SupportInboxView(),
    );
  }
}

class _SupportInboxView extends StatefulWidget {
  const _SupportInboxView();

  @override
  State<_SupportInboxView> createState() => _SupportInboxViewState();
}

class _SupportInboxViewState extends State<_SupportInboxView> {
  final TextEditingController _searchEmailController = TextEditingController();

  @override
  void dispose() {
    _searchEmailController.dispose();
    super.dispose();
  }

  Future<void> _openChat({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String userId,
    required String supportUserId,
    required dynamic categoryId,
    String? conversationId,
    ConversationSummary? conversationToMark,
  }) async {
    final viewModel = context.read<SupportInboxViewModel>();

    if (conversationToMark != null) {
      final didMarkRead = await viewModel.markConversationRead(
        conversationToMark,
      );
      if (!didMarkRead || !context.mounted) {
        return;
      }
    }

    if (!context.mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => ChatDetailViewModel(
            conversationId: conversationId,
            userId: userId,
            supportUserId: supportUserId,
            categoryId: categoryId,
          )..bootstrap(),
          child: ChatDetailScreen(title: title, subtitle: subtitle),
        ),
      ),
    );

    if (!context.mounted) {
      return;
    }

    await viewModel.loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<SupportInboxViewModel>();
    final authViewModel = context.watch<AuthViewModel>();
    final supportUserId = authViewModel.user?.id ?? '';
    final categoryId = authViewModel.user?.categoryId;

    return Scaffold(
      appBar: AppBar(title: const Text('Support Inbox')),
      body: RefreshIndicator(
        onRefresh: viewModel.loadInitial,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _searchEmailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) =>
                  viewModel.searchUserByEmail(_searchEmailController.text),
              decoration: InputDecoration(
                labelText: 'Search user by email',
                hintText: 'user@example.com',
                suffixIcon: viewModel.isSearchingUser
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        onPressed: () => viewModel.searchUserByEmail(
                          _searchEmailController.text,
                        ),
                        icon: const Icon(Icons.search),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            if (viewModel.searchErrorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  viewModel.searchErrorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            if (viewModel.searchedUsers.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Matched users (${viewModel.searchedUsers.length})',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _searchEmailController.clear();
                        viewModel.clearSearchResult();
                      },
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: viewModel.searchedUsers
                      .map(
                        (user) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _SearchedUserCard(
                            userName: user.userName,
                            userEmail: user.userEmail,
                            onMessage: () => _openChat(
                              context: context,
                              title: user.userName,
                              subtitle: user.userEmail,
                              userId: user.userId,
                              supportUserId: supportUserId,
                              categoryId: categoryId,
                              conversationId: user.conversationId,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
            if (viewModel.isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (viewModel.errorMessage != null &&
                viewModel.conversations.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(child: Text(viewModel.errorMessage!)),
              )
            else if (viewModel.conversations.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: Text('No unread support conversations.')),
              )
            else ...[
              ...viewModel.conversations.map(
                (conversation) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ConversationTile(
                    conversation: conversation,
                    onTap: () => _openChat(
                      context: context,
                      title: conversation.userName,
                      subtitle: conversation.userEmail,
                      userId: conversation.userId,
                      supportUserId: supportUserId,
                      categoryId: categoryId,
                      conversationId: conversation.conversationId,
                      conversationToMark: conversation,
                    ),
                  ),
                ),
              ),
              _InboxFooter(viewModel: viewModel),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchedUserCard extends StatelessWidget {
  const _SearchedUserCard({
    required this.userName,
    required this.userEmail,
    required this.onMessage,
  });

  final String userName;
  final String userEmail;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              userName,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (userEmail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(userEmail),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  onPressed: onMessage,
                  child: const Text('Message user'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final ConversationSummary conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFE6FFFA),
                foregroundColor: const Color(0xFF0F766E),
                child: Text(
                  conversation.userName.isEmpty
                      ? '?'
                      : conversation.userName.characters.first.toUpperCase(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.userName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (conversation.userEmail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        conversation.userEmail,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      conversation.latestMessagePreview.isEmpty
                          ? 'No preview available'
                          : conversation.latestMessagePreview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatModifiedAt(conversation.modifiedAt),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${conversation.supportUnread}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatModifiedAt(DateTime? value) {
    if (value == null) {
      return '--';
    }

    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.day}/${local.month} $hour:$minute $period';
  }
}

class _InboxFooter extends StatelessWidget {
  const _InboxFooter({required this.viewModel});

  final SupportInboxViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    if (viewModel.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (viewModel.hasMore) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        child: Center(
          child: OutlinedButton(
            onPressed: viewModel.loadMore,
            child: const Text('Load more'),
          ),
        ),
      );
    }

    return const SizedBox(height: 12);
  }
}
