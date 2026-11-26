import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nlpa2/pages/stk_recovery_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.github.forcemind/stk_recovery');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  const first = 'com.android.stk/com.android.stk.StkMain';
  const second = 'com.android.stk2/com.android.stk2.StkMain';

  void mock({bool empty = false, bool denied = false}) {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'list') {
        return empty ? [] : [
          {'id': first, 'label': 'SIM Toolkit 1', 'packageName': 'com.android.stk'},
          {'id': second, 'label': 'SIM Toolkit 2', 'packageName': 'com.android.stk2'},
        ];
      }
      if (call.method == 'open') {
        if (denied) throw PlatformException(code: 'DENIED');
        return 'launch_requested';
      }
      if (call.method == 'settings') return 'settings_requested';
      throw MissingPluginException();
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('lists both entries; only explicit user choice opens one', (tester) async {
    mock();
    await tester.pumpWidget(const MaterialApp(home: StkRecoveryPage()));
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.method), ['list']);
    expect(find.text('SIM Toolkit 1'), findsOneWidget);
    await tester.ensureVisible(find.text('SIM Toolkit 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SIM Toolkit 2'));
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.method), ['list', 'open']);
    expect(calls.last.arguments, {'id': second});
    expect(find.textContaining('switching are not confirmed'), findsOneWidget);
  });

  testWidgets('empty list offers a distinct settings fallback', (tester) async {
    mock(empty: true);
    await tester.pumpWidget(const MaterialApp(home: StkRecoveryPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('No known launchable'), findsOneWidget);
    final button = find.text('Open system network settings');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.method), ['list', 'settings']);
    expect(find.textContaining('Network settings requested'), findsOneWidget);
  });

  testWidgets('system denial is reported without retry or claiming switch', (tester) async {
    mock(denied: true);
    await tester.pumpWidget(const MaterialApp(home: StkRecoveryPage()));
    await tester.pumpAndSettle();
    final tile = find.text('SIM Toolkit 1');
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.method), ['list', 'open']);
    expect(find.text('Android refused to launch this entry.'), findsOneWidget);
  });
}
