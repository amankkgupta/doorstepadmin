import 'package:admindoorstep/app_routes.dart';
import 'package:admindoorstep/auth/viewmodels/auth_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthViewModel>(
      builder: (context, authViewModel, _) {
        final email = authViewModel.user?.email ?? 'Signed in user';

        return Scaffold(
          appBar: AppBar(
            title: const Text('Home'),
            actions: [
              TextButton(
                onPressed: () async {
                  await authViewModel.signOut();
                  if (!context.mounted) {
                    return;
                  }
                  Navigator.pushReplacementNamed(context, AppRoutes.login);
                },
                child: const Text('Logout'),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth = constraints.maxWidth < 700
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 16) / 2;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          email,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text('Choose a section to manage admin tasks.'),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            _FeatureCard(
                              width: cardWidth,
                              icon: Icons.receipt_long_outlined,
                              title: 'View orders',
                              description:
                                  'Review incoming orders and track their status.',
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  AppRoutes.viewOrders,
                                );
                              },
                            ),
                            _FeatureCard(
                              width: cardWidth,
                              icon: Icons.chat_bubble_outline_rounded,
                              title: 'Chats',
                              description:
                                  'Open support and customer conversations.',
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  AppRoutes.supportInbox,
                                );
                              },
                            ),
                            _FeatureCard(
                              width: cardWidth,
                              icon: Icons.campaign_outlined,
                              title: 'Create updates',
                              description:
                                  'Publish important updates for users and teams.',
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  AppRoutes.createUpdate,
                                );
                              },
                            ),
                            _FeatureCard(
                              width: cardWidth,
                              icon: Icons.add_box_outlined,
                              title: 'Create Product',
                              description:
                                  'Add new products and manage listing details.',
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  AppRoutes.createProduct,
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
  });

  final double width;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: width,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6FFFA),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF0F766E)),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
