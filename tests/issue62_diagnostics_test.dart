import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nlpa2/pages/issue62_diagnostics_page.dart';
import 'package:nlpa2/services/issue62_diagnostics.dart';

class MemorySnapshotStore implements Issue62SnapshotStore {
  String? saved;
  bool failWrite = false;
  bool failClear = false;

  @override
  Future<String?> read() async => saved;

  @override
  Future<void> write(String value) async {
    if (failWrite) throw StateError('Storage unavailable');
    saved = value;
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('Storage removal unavailable');
    saved = null;
  }
}

const aid = 'A0000005591010FFFFFFFF8900000100';
const signer = 'D1C0F48B370E74D4EA4770ED4C3CD70A3198D31F';
const otherSigner =
    '8E486CABAA452FA339240EFDEE849AAA41AC27B9FD5F894649DD3023629313AD';

Map<String, dynamic> nativeSnapshot({
  String time = '2026-11-23T01:00:00Z',
  bool poisoned = false,
}) => {
  'schemaVersion': 1,
  'generatedAtUtc': time,
  'app': {
    'packageName': 'io.github.forcemind.nekokolpa.issue62.v4',
    'versionName': '2.5.0-issue62.4',
    'versionCode': 4,
    'currentSignerSha1': [signer],
    'currentSignerSha256': [otherSigner],
  },
  'device': {
    'manufacturer': 'Samsung',
    'model': 'S25',
    'sdkInt': 36,
    'androidRelease': '16',
  },
  'service': {
    'initialized': true,
    'poisoned': poisoned,
    'readers': [
      {'reader': 'SIM1', 'hasSession': true, 'openChannelCount': 0},
    ],
  },
  'telephony': {
    'status': 'available',
    'logicalSlots': [
      {
        'logicalSlotIndex': 0,
        'subscriptionMappingStatus': 'mapped',
        'subscriptionId': 7,
        'hasCarrierPrivileges': false,
        'carrierPrivilegeStatus': 'not_confirmed',
      },
    ],
  },
  'events': [
    {
      'timestampUtc': time,
      'stage': 'openChannel',
      'outcome': 'exception',
      'reader': 'SIM1',
      'aid': aid,
      'retry': 0,
      'errorClass': 'java.lang.SecurityException',
      'message': 'No APDU access allowed',
      'causeChain': [
        {
          'errorClass': 'java.lang.SecurityException',
          'message': 'Access denied',
        },
      ],
    },
  ],
  'droppedEventCount': 0,
  'recording': {'mode': 'passive_existing_operations', 'eventLimit': 512},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ee.nekoko.omapi_plugin');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MemorySnapshotStore store;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) handler;

  setUp(() {
    store = MemorySnapshotStore();
    calls = [];
    handler = (call) async =>
        call.method == 'clearDiagnostics' ? true : nativeSnapshot();
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test(
    'captures only through the read-only diagnostic method with explicit marker',
    () async {
      final diagnostics = Issue62Diagnostics(store: store);
      expect(await diagnostics.capture(marker: 'before_switch'), isTrue);
      expect(calls.map((call) => call.method), ['getDiagnostics']);
      expect(calls.single.arguments, {'marker': 'before_switch'});
      expect(
        diagnostics.beforeSwitch?['generatedAtUtc'],
        '2026-11-23T01:00:00Z',
      );
      expect(diagnostics.exportReport(), contains(signer));
      expect(diagnostics.exportReport(), contains(otherSigner));
      expect(diagnostics.exportReport(), contains(aid));
    },
  );

  test('before and after snapshots survive a new service instance', () async {
    final diagnostics = Issue62Diagnostics(store: store);
    await diagnostics.capture(marker: 'before_switch');
    handler = (_) async => nativeSnapshot(time: '2026-11-23T02:00:00Z');
    await diagnostics.capture(marker: 'after_switch');
    final restored = Issue62Diagnostics(store: store);
    await restored.restore();
    expect(restored.beforeSwitch?['generatedAtUtc'], '2026-11-23T01:00:00Z');
    expect(restored.afterSwitch?['generatedAtUtc'], '2026-11-23T02:00:00Z');
    expect(restored.current?['generatedAtUtc'], '2026-11-23T02:00:00Z');
    expect(
      calls.length,
      2,
      reason: 'Restoring never asks the card or native service',
    );
  });

  test(
    'native error preserves snapshots and omits raw exception details',
    () async {
      final diagnostics = Issue62Diagnostics(store: store);
      await diagnostics.capture(marker: 'before_switch');
      handler = (_) async => throw PlatformException(
        code: 'NOT_CONNECTED',
        message:
            'ICCID=89012345678901234567; EID 89012345678901234567890123456789',
        details: {
          'apdu': '80E28800112233445566778899',
          'activationCode': 'SECRET-DETAILS',
        },
      );
      expect(await diagnostics.capture(marker: 'after_switch'), isFalse);
      expect(diagnostics.beforeSwitch, isNotNull);
      expect(diagnostics.afterSwitch, isNull);
      final report = diagnostics.exportReport();
      expect(report, contains('NOT_CONNECTED'));
      expect(report, isNot(contains('89012345678901234567')));
      expect(report, isNot(contains('80E28800112233445566778899')));
      expect(report, isNot(contains('SECRET-DETAILS')));
      final restored = Issue62Diagnostics(store: store);
      await restored.restore();
      expect(restored.beforeSwitch, isNotNull);
      expect(restored.captureError, contains('NOT_CONNECTED'));
    },
  );

  test('poisoned state does not prevent passive snapshots or export', () async {
    handler = (_) async => nativeSnapshot(poisoned: true);
    final diagnostics = Issue62Diagnostics(store: store);
    expect(await diagnostics.capture(marker: 'after_switch'), isTrue);
    expect((diagnostics.current?['service'] as Map)['poisoned'], isTrue);
    expect(calls.map((call) => call.method), ['getDiagnostics']);
  });

  test(
    'preserves false versus unavailable without inventing ARA-M denial',
    () async {
      final snapshot = nativeSnapshot();
      (snapshot['telephony'] as Map)['logicalSlots'] = [
        {
          'logicalSlotIndex': 0,
          'hasCarrierPrivileges': false,
          'carrierPrivilegeStatus': 'not_confirmed',
        },
        {
          'logicalSlotIndex': 1,
          'hasCarrierPrivileges': null,
          'carrierPrivilegeStatus': 'unavailable',
        },
      ];
      handler = (_) async => snapshot;
      final diagnostics = Issue62Diagnostics(store: store);
      await diagnostics.capture();
      final slots =
          ((diagnostics.current?['telephony'] as Map)['logicalSlots'] as List);
      expect((slots[0] as Map)['hasCarrierPrivileges'], isFalse);
      expect((slots[1] as Map)['hasCarrierPrivileges'], isNull);
      expect(
        diagnostics.exportReport(),
        contains('No card ARA-M rules were read'),
      );
    },
  );

  test(
    'whitelist excludes subscriber data, raw bytes and unknown nested fields',
    () async {
      final snapshot = nativeSnapshot();
      snapshot['iccid'] = 'PRIVATE-ICCID';
      snapshot['rawApplicationLog'] = 'PRIVATE-RAW-LOG';
      (snapshot['app'] as Map)['privateKey'] = 'PRIVATE-KEY';
      (snapshot['service'] as Map)['atr'] = 'PRIVATE-ATR';
      final event = (snapshot['events'] as List).single as Map;
      event['apdu'] = 'PRIVATE-APDU';
      event['message'] =
          'Rejected LPA:1\$secret.example\$ACTIVATION-SECRET user@example.com https://secret.example/token IMSI=310123456789012';
      handler = (_) async => snapshot;
      final diagnostics = Issue62Diagnostics(store: store);
      await diagnostics.capture();
      for (final secret in [
        'PRIVATE-',
        'ACTIVATION-SECRET',
        'user@example.com',
        'secret.example',
        '310123456789012',
      ]) {
        expect(diagnostics.exportReport(), isNot(contains(secret)));
        expect(store.saved, isNot(contains(secret)));
      }
      expect(diagnostics.exportReport(), contains(aid));
    },
  );

  test('redacts quoted, formatted phone numbers and card-body aliases', () {
    for (final text in [
      'Contact +1 (415) 555-2671 for help',
      'phoneNumber="+1 (415) 555-2671"; reason=denied',
      "'phoneNumber': '+1 (415) 555-2671'; reason=denied",
      'Call 415.555.2671',
    ]) {
      final safe = redactIssue62Text(text);
      expect(safe, isNot(contains('415')));
      expect(safe, isNot(contains('2671')));
    }
    for (final name in [
      'response',
      'commandData',
      'responseData',
      'PIN',
      'PUK',
      'password',
    ]) {
      final safe = redactIssue62Text(
        '$name="sensitive data 1234"; reason=denied',
      );
      expect(safe, isNot(contains('sensitive')));
      expect(safe, isNot(contains('1234')));
      expect(safe, contains('reason=denied'));
    }
    expect(
      redactIssue62Text('failed with 0xAABBCCDDEEFFAABBCCDDEEFF'),
      isNot(contains('AABBCC')),
    );
    expect(
      redactIssue62Text('failed 80 E2 88 00 A1 B2 C3 D4 E5 F6'),
      isNot(contains('A1 B2')),
    );
  });

  test('restoring re-sanitizes old cached data before export', () async {
    final snapshot = nativeSnapshot();
    (snapshot['events'] as List).first['message'] = 'IMEI=123456789012345';
    store.saved = jsonEncode({'schemaVersion': 1, 'beforeSwitch': snapshot});
    final diagnostics = Issue62Diagnostics(store: store);
    await diagnostics.restore();
    expect(diagnostics.exportReport(), isNot(contains('123456789012345')));
    expect(diagnostics.beforeSwitch, isNotNull);
    expect(calls, isEmpty);
  });

  test('timeout leaves previous successful data available', () async {
    final diagnostics = Issue62Diagnostics(
      store: store,
      timeout: const Duration(milliseconds: 5),
    );
    await diagnostics.capture(marker: 'before_switch');
    final completer = Completer<Object?>();
    handler = (_) => completer.future;
    expect(await diagnostics.capture(marker: 'after_switch'), isFalse);
    completer.complete(nativeSnapshot());
    expect(diagnostics.beforeSwitch, isNotNull);
    expect(diagnostics.captureError, contains('timed out'));
  });

  test(
    'invalid schema cannot replace a previously recorded snapshot',
    () async {
      final diagnostics = Issue62Diagnostics(store: store);
      await diagnostics.capture(marker: 'before_switch');
      handler = (_) async => {'schemaVersion': 999, 'events': []};
      expect(await diagnostics.capture(marker: 'before_switch'), isFalse);
      expect(diagnostics.beforeSwitch?['schemaVersion'], 1);
    },
  );

  test('unsupported marker never reaches native code', () async {
    final diagnostics = Issue62Diagnostics(store: store);
    await expectLater(
      diagnostics.capture(marker: 'reset'),
      throwsArgumentError,
    );
    expect(calls, isEmpty);
  });

  test('bounded event history reports client-side truncation', () {
    final snapshot = nativeSnapshot();
    snapshot['events'] = List.generate(
      600,
      (index) => {'stage': 'event_$index', 'outcome': 'ok'},
    );
    final safe = sanitizeIssue62Snapshot(snapshot);
    expect((safe['events'] as List).length, 512);
    expect(safe['exportDroppedEventCount'], 88);
    expect((safe['events'] as List).first['stage'], 'event_88');
    expect(
      utf8.encode(jsonEncode(safe)).length,
      lessThanOrEqualTo(Issue62Diagnostics.maxSnapshotBytes),
    );
  });

  test(
    'storage failure is explicit while an in-memory report remains usable',
    () async {
      store.failWrite = true;
      final diagnostics = Issue62Diagnostics(store: store);
      expect(await diagnostics.capture(), isTrue);
      expect(diagnostics.storageError, contains('Storage unavailable'));
      expect(diagnostics.current, isNotNull);
      expect(store.saved, isNull);
    },
  );

  test('native clear failure preserves saved snapshots', () async {
    final diagnostics = Issue62Diagnostics(store: store);
    await diagnostics.capture(marker: 'before_switch');
    final saved = store.saved;
    handler = (_) async => throw PlatformException(code: 'UNAVAILABLE');
    expect(await diagnostics.clear(), isFalse);
    expect(diagnostics.beforeSwitch, isNotNull);
    expect(store.saved, saved);
  });

  test(
    'partial clear accurately reports native cleared but local data remains',
    () async {
      final diagnostics = Issue62Diagnostics(store: store);
      await diagnostics.capture(marker: 'before_switch');
      store.failClear = true;
      expect(await diagnostics.clear(), isFalse);
      expect(
        diagnostics.storageError,
        contains('Native log cleared; local snapshots remain'),
      );
      expect(diagnostics.beforeSwitch, isNotNull);
      expect(store.saved, isNotNull);
    },
  );

  test(
    'confirmed clear removes both sources using no card-operation method',
    () async {
      final diagnostics = Issue62Diagnostics(store: store);
      await diagnostics.capture(marker: 'before_switch');
      expect(await diagnostics.clear(), isTrue);
      expect(diagnostics.beforeSwitch, isNull);
      expect(diagnostics.current, isNull);
      expect(store.saved, isNull);
      expect(calls.map((call) => call.method), [
        'getDiagnostics',
        'clearDiagnostics',
      ]);
    },
  );

  testWidgets(
    'phone-width page captures and copies without any card commands',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? copied;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Issue62DiagnosticsPage(
            diagnostics: Issue62Diagnostics(store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = find.widgetWithText(FilledButton, 'Capture before');
      await tester.ensureVisible(before);
      await tester.pumpAndSettle();
      expect(before.hitTestable(), findsOneWidget);
      await tester.tap(before);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      final copy = find.widgetWithText(OutlinedButton, 'Copy report');
      await tester.ensureVisible(copy);
      await tester.pumpAndSettle();
      expect(copy.hitTestable(), findsOneWidget);
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Redacted diagnostic report copied'), findsOneWidget);
      expect(copied, isNotNull);
      expect(jsonDecode(copied!)['beforeSwitch'], isNotNull);
      expect(calls.every((call) => call.method == 'getDiagnostics'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
