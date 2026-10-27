import 'package:flutter_test/flutter_test.dart';
import 'package:filtros_panasa/main.dart';

void main() {
  testWidgets('FiltrosPanasa3DApp loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const FiltrosPanasa3DApp());
    expect(find.textContaining('Filtros Panasa'), findsWidgets);
  });
}
