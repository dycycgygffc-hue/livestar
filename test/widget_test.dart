import 'package:flutter_test/flutter_test.dart';
import 'package:livestar/main.dart';

void main() {
  testWidgets('LiveStar app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const LiveStarApp());
  });
}
