import 'package:flutter_test/flutter_test.dart';

import 'package:admindoorstep/main.dart';

void main() {
  testWidgets('renders web-first admin dashboard shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AdminDoorstepApp());
    await tester.pump();

    expect(find.text('admindoorstep'), findsWidgets);
    expect(
      find.text(
        'Run your admin workflow from a single browser-first workspace.',
      ),
      findsOneWidget,
    );
    expect(find.text('Quick actions'), findsOneWidget);
  });
}
