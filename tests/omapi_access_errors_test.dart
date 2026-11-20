import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nlpa2/adapter/euicc_adapter.dart';
import 'package:nlpa2/adapter/omapi/omapi_access_errors.dart';
import 'package:nlpa2/adapter/omapi/omapi_adapter.dart';
import 'package:nlpa2/utils/error_codes.dart';
import 'package:nlpa2/utils/hex_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('ee.nekoko.omapi_plugin');
  const aid = 'A0000005591010FFFFFFFF8900000100';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Matcher permissionError(AppErrorCode code) => isA<AppException>().having(
    (error) => error.code,
    'error code',
    code,
  );

  group('OMAPI access classification', () {
    for (final code in [
      'SECURITY_EXCEPTION',
      'SecurityException',
      'AccessControlException',
    ]) {
      test('recognizes native/legacy code $code without message heuristics', () {
        expect(isOmapiAccessDeniedError(PlatformException(code: code)), isTrue);
      });
    }
    test('recognizes old bridge APDU denial text', () {
      expect(
        isOmapiAccessDeniedError(
          PlatformException(
            code: 'CHANNEL_FAILED',
            message: 'AccessControlException: no APDU access allowed!',
          ),
        ),
        isTrue,
      );
    });
    test('recognizes old connection ARA-M denial text', () {
      expect(
        isOmapiAccessDeniedError(
          PlatformException(
            code: 'CONNECTION_FAILED',
            message: 'Access denied by ARA-M: not permitted',
          ),
        ),
        isTrue,
      );
    });
    test('mixed native outcomes override a candidate denial message', () {
      for (final message in [
        'no APDU access allowed',
        'AccessControlException: no APDU access allowed!',
        'Access denied by ARA-M: not permitted',
      ]) {
        expect(
          isOmapiAccessDeniedError(
            PlatformException(
              code: 'CHANNEL_FAILED',
              message: message,
              details: const {
                'operation': 'openChannel',
                'permissionDenied': false,
              },
            ),
          ),
          isFalse,
        );
      }
    });
    test('legacy metadata still permits explicit legacy denial text', () {
      expect(
        isOmapiAccessDeniedError(
          PlatformException(
            code: 'CHANNEL_FAILED',
            message: 'no APDU access allowed',
            details: const {'operation': 'openChannel'},
          ),
        ),
        isTrue,
      );
    });
    test('does not invent permissions from generic channel failure', () {
      expect(
        isOmapiAccessDeniedError(
          PlatformException(code: 'CHANNEL_FAILED', message: 'No AID opened'),
        ),
        isFalse,
      );
    });
    test('does not override safety latch or BUSY with a message match', () {
      for (final code in ['OMAPI_SESSION_CORRUPTED', 'BUSY']) {
        expect(
          isOmapiAccessDeniedError(
            PlatformException(code: code, message: 'no APDU access allowed'),
          ),
          isFalse,
        );
      }
    });
    test('recognizes already-mapped app errors', () {
      for (final code in [
        AppErrorCode.ERROR_OMAPI_PERMISSION_DENIED,
        AppErrorCode.ERROR_OMAPI_SECURITYEXCEPTION,
      ]) {
        expect(isOmapiAccessDeniedError(AppException(code)), isTrue);
      }
      expect(isOmapiAccessDeniedError(StateError('not a permission error')), isFalse);
    });
  });

  group('adapter propagation and retry', () {
    late OmapiAdapter adapter;
    late int opens;
    late int cleanups;
    PlatformException? openError;
    PlatformException? connectError;
    late bool openErrorOnce;

    setUp(() {
      opens = 0;
      cleanups = 0;
      openError = null;
      connectError = null;
      openErrorOnce = false;
      messenger.setMockMethodCallHandler(native, (call) async {
        switch (call.method) {
          case 'connect':
            if (connectError != null) throw connectError!;
            return {'success': true, 'atr': ''};
          case 'openChannel':
            opens++;
            if (openError != null && (!openErrorOnce || opens == 1)) {
              throw openError!;
            }
            final args = call.arguments as Map;
            return {
              'success': true,
              'aid': args['aid'] ?? (args['aids'] as List).first,
              'selectResponse': '9000',
            };
          case 'closeChannels':
            cleanups++;
            return true;
          case 'transmitOnChannel':
            return '9000';
          default:
            return true;
        }
      });
      adapter = OmapiAdapter();
    });
    tearDown(() async {
      connectError = null;
      openError = null;
      await adapter.disconnect();
      messenger.setMockMethodCallHandler(native, null);
    });
    Future<void> connect() => adapter.connect(
      Reader(id: 'omapi:SIM1', name: 'SIM 1', source: adapter),
    );

    test('connect recognizes SECURITY_EXCEPTION emitted by Kotlin', () async {
      connectError = PlatformException(code: 'SECURITY_EXCEPTION');
      await expectLater(
        connect(),
        throwsA(permissionError(AppErrorCode.ERROR_OMAPI_SECURITYEXCEPTION)),
      );
    });
    test('eager open surfaces access denied rather than channel failed', () async {
      await connect();
      openError = PlatformException(code: 'SECURITY_EXCEPTION');
      await expectLater(
        adapter.openChannel(aids: [aid]),
        throwsA(permissionError(AppErrorCode.ERROR_OMAPI_PERMISSION_DENIED)),
      );
      expect(opens, 1);
    });
    test('eager mixed failure is not relabeled as a permission failure', () async {
      await connect();
      openError = PlatformException(
        code: 'CHANNEL_FAILED',
        message: 'no APDU access allowed',
        details: const {'operation': 'openChannel', 'permissionDenied': false},
      );
      await expectLater(
        adapter.openChannel(aids: [aid]),
        throwsA(permissionError(AppErrorCode.ERROR_OMAPI_CHANNEL_OPEN_FAILED)),
      );
      expect(opens, 1);
    });
    test('ambiguous deferred failure preserves one cleanup and recovery', () async {
      await connect();
      final channel = await adapter.openChannel();
      final initialCleanups = cleanups;
      openError = PlatformException(
        code: 'CHANNEL_FAILED',
        message: 'no APDU access allowed',
        details: const {'operation': 'openChannel', 'permissionDenied': false},
      );
      openErrorOnce = true;
      expect(
        await channel.transmit(0, 0xA4, 0x04, 0, HexUtils.hexToBytes(aid)),
        orderedEquals([0x90, 0x00]),
      );
      expect(opens, 2);
      expect(cleanups, initialCleanups + 1);
      await channel.transmit(0, 0xCA, 0, 0);
      await channel.close();
    });
    test('ambiguous deferred failure retries only once', () async {
      await connect();
      final channel = await adapter.openChannel();
      final initialCleanups = cleanups;
      openError = PlatformException(
        code: 'CHANNEL_FAILED',
        message: 'no APDU access allowed',
        details: const {'operation': 'openChannel', 'permissionDenied': false},
      );
      await expectLater(
        channel.transmit(0, 0xA4, 0x04, 0, HexUtils.hexToBytes(aid)),
        throwsA(permissionError(AppErrorCode.ERROR_OMAPI_CHANNEL_OPEN_FAILED)),
      );
      expect(opens, 2);
      expect(cleanups, initialCleanups + 1);
      await channel.close();
    });
    test('deferred SELECT denial does not clean or retry', () async {
      await connect();
      final channel = await adapter.openChannel();
      final initialCleanups = cleanups;
      openError = PlatformException(code: 'SECURITY_EXCEPTION');
      await expectLater(
        channel.transmit(0, 0xA4, 0x04, 0, HexUtils.hexToBytes(aid)),
        throwsA(permissionError(AppErrorCode.ERROR_OMAPI_PERMISSION_DENIED)),
      );
      expect(opens, 1);
      expect(cleanups, initialCleanups);
      await channel.close();
    });
    test('a denied deferred handle does not invalidate another live handle', () async {
      await connect();
      final live = await adapter.openChannel(aids: [aid]);
      final deferred = await adapter.openChannel();
      final initialCleanups = cleanups;
      openError = PlatformException(code: 'SECURITY_EXCEPTION');
      await expectLater(
        deferred.transmit(0, 0xA4, 0x04, 0, HexUtils.hexToBytes('A0000005591010')),
        throwsA(permissionError(AppErrorCode.ERROR_OMAPI_PERMISSION_DENIED)),
      );
      expect(cleanups, initialCleanups);
      openError = null;
      await live.transmit(0, 0xCA, 0, 0);
      await deferred.close();
      await live.close();
    });
  });
}
