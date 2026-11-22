import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/features/shell/presentation/simple_primary_scaffold.dart';

void main() {
  for (final entry in const <(int, String)>[
    (0, 'novel'),
    (1, 'chat'),
    (2, 'settings'),
  ]) {
    testWidgets('${entry.$2} root asks before exiting', (tester) async {
      var exits = 0;
      await _pumpRoot(tester, entry.$1, () => exits++);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('exit-app-dialog')), findsOneWidget);
      expect(exits, 0);
    });
  }

  testWidgets('cancel keeps the app open and confirm invokes exit callback', (
    tester,
  ) async {
    var exits = 0;
    await _pumpRoot(tester, 0, () => exits++);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-exit-app')));
    await tester.pumpAndSettle();
    expect(exits, 0);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-exit-app')));
    await tester.pumpAndSettle();
    expect(exits, 1);
  });

  testWidgets('duplicate back events open only one exit dialog', (
    tester,
  ) async {
    await _pumpRoot(tester, 0, () {});

    final first = tester.binding.handlePopRoute();
    final second = tester.binding.handlePopRoute();
    await Future.wait([first, second]);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('exit-app-dialog')), findsOneWidget);
  });

  testWidgets('visible keyboard is dismissed before exit confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(viewInsets: EdgeInsets.only(bottom: 280)),
          child: SimplePrimaryScaffold(
            selectedIndex: 0,
            title: 'Novel',
            body: const TextField(autofocus: true),
            exitApp: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('exit-app-dialog')), findsNothing);
  });
}

Future<void> _pumpRoot(
  WidgetTester tester,
  int selectedIndex,
  VoidCallback exitApp,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SimplePrimaryScaffold(
        selectedIndex: selectedIndex,
        title: 'Ibuki Home',
        body: const SizedBox.expand(),
        exitApp: exitApp,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
