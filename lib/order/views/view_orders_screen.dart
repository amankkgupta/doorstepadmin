import 'package:admindoorstep/auth/viewmodels/auth_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:admindoorstep/order/views/order_details_screen.dart';

class ViewOrdersScreen extends StatefulWidget {
  const ViewOrdersScreen({super.key});

  @override
  State<ViewOrdersScreen> createState() => _ViewOrdersScreenState();
}

class _ViewOrdersScreenState extends State<ViewOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('View Orders'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'In Progress'),
            Tab(text: 'Applied'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _OrdersTab(status: 'in_progress'),
          _OrdersTab(status: 'applied'),
        ],
      ),
    );
  }
}

class _OrdersTab extends StatefulWidget {
  const _OrdersTab({required this.status});

  final String status;

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  static const int _pageSize = 10;

  final List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;
  dynamic _loadedCategoryId;
  List<dynamic>? _categoryProductIds;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _orders.clear();
      _hasMore = true;
    });

    await _fetchNextPage();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchNextPage() async {
    if (_isLoadingMore || !_hasMore) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
      _errorMessage = null;
    });

    try {
      final from = _orders.length;
      final to = from + _pageSize - 1;
      final categoryId = context.read<AuthViewModel>().user?.categoryId;

      if (categoryId == null) {
        setState(() {
          _errorMessage = 'Unable to find admin category.';
          _hasMore = false;
        });
        return;
      }

      final productIds = await _fetchProductIdsForCategory(categoryId);

      if (productIds.isEmpty) {
        setState(() {
          _hasMore = false;
        });
        return;
      }

      final response = await Supabase.instance.client
          .from('orders')
          .select('order_id, product_name, applicant_name, created_at')
          .eq('status', widget.status)
          .inFilter('product_id', productIds)
          .order('created_at', ascending: false)
          .range(from, to);

      final nextPage = (response as List<dynamic>).cast<Map<String, dynamic>>();

      setState(() {
        _orders.addAll(nextPage);
        _hasMore = nextPage.length == _pageSize;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Unable to load orders right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<List<dynamic>> _fetchProductIdsForCategory(dynamic categoryId) async {
    if (_loadedCategoryId == categoryId && _categoryProductIds != null) {
      return _categoryProductIds!;
    }

    final response = await Supabase.instance.client
        .from('products')
        .select('product_id')
        .eq('category_id', categoryId);

    final productIds = (response as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((product) => product['product_id'])
        .where((productId) => productId != null)
        .toList();

    _loadedCategoryId = categoryId;
    _categoryProductIds = productIds;
    return productIds;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _errorMessage!,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    if (_orders.isEmpty) {
      return const Center(child: Text('No orders found.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: _orders.length + 1,
      separatorBuilder: (_, index) => index == _orders.length - 1
          ? const SizedBox.shrink()
          : const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == _orders.length) {
          return _OrdersFooter(
            hasMore: _hasMore,
            isLoadingMore: _isLoadingMore,
            onLoadMore: _fetchNextPage,
            errorMessage: _errorMessage,
          );
        }

        final order = _orders[index];

        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      OrderDetailsScreen(orderId: order['order_id']),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${order['product_name'] ?? '-'}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Order ID: ${order['order_id'] ?? '-'}'),
                  const SizedBox(height: 4),
                  Text('Applicant: ${order['applicant_name'] ?? '-'}'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OrdersFooter extends StatelessWidget {
  const _OrdersFooter({
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
    required this.errorMessage,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final Future<void> Function() onLoadMore;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (hasMore) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 24),
        child: Center(
          child: OutlinedButton(
            onPressed: onLoadMore,
            child: const Text('Load more'),
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 24),
        child: Center(
          child: Text(errorMessage!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    return const Padding(
      padding: EdgeInsets.only(top: 16, bottom: 24),
      child: Center(child: Text('No more orders.')),
    );
  }
}
