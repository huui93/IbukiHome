import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/features/backup/presentation/backup_restore_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('shows formal backup, restore, and security information', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: BackupRestorePage())),
      ),
    );

    expect(find.byKey(const Key('create-full-backup')), findsOneWidget);
    expect(find.byKey(const Key('restore-full-backup')), findsOneWidget);
    expect(find.byKey(const Key('about-full-backup')), findsOneWidget);
    expect(find.text('关于完整备份'), findsOneWidget);
    expect(find.textContaining('不包含 API Key'), findsOneWidget);
    expect(find.textContaining('卸载 App 后继续保留'), findsOneWidget);
  });
}
