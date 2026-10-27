import 'package:flutter_test/flutter_test.dart';
import 'package:filtros_panasa/main.dart';

void main() {
  testWidgets('FiltrosPanasaApp loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const FiltrosPanasaApp());
    expect(find.text('Filtros Panasa'), findsWidgets);
  });
}
