import 'package:flutter_test/flutter_test.dart';
import 'package:spin_the_bottle/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Собираем приложение и запускаем первый кадр
    await tester.pumpWidget(const SpinTheBottleApp());

    // Проверяем, что заголовок отображается
    expect(find.text('Spin the Bottle'), findsOneWidget);
  });
}