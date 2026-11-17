import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/navigation/app_navigation.dart';
import 'package:offline_player/navigation/good_good_study_shell.dart';
import 'package:offline_player/playback/desktop_media_open.dart';

const channel = MethodChannel('goodgoodstudy/open_media');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late DesktopMediaOpenController controller;
  late List<List<String>> inbox;
  late List<MethodCall> calls;

  Future<void> notify() async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('filesAvailable'),
      ),
      (_) {},
    );
  }

  setUp(() {
    inbox = [];
    calls = [];
    controller = DesktopMediaOpenController();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'takePending') {
        final result = inbox;
        inbox = [];
        return result;
      }
      return null;
    });
  });
  tearDown(() {
    controller.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('cold requests keep file order, filter unsupported paths and deduplicate per request', () async {
    inbox = [
      [
        '/media/a.MKV',
        '/media/b.mp3',
        '/media/a.MKV',
        'relative.mp4',
        'https://host/a.mp4',
        '/media/x.srt',
        '/media/n\u0000.mp4',
      ],
    ];
    await controller.initialize();
    expect(controller.takeNext(), ['/media/a.MKV', '/media/b.mp3']);
    expect(controller.hasPending, isFalse);
    expect(calls.map((call) => call.method), ['takePending']);
  });

  test(
    'warm requests and opening the same file again are never lost',
    () async {
      await controller.initialize();
      inbox = [
        ['/media/a.mp4'],
        ['/media/a.mp4', '/media/b.flac'],
      ];
      await notify();
      expect(controller.takeNext(), ['/media/a.mp4']);
      expect(controller.takeNext(), ['/media/a.mp4', '/media/b.flac']);
      expect(controller.takeNext(), isNull);
    },
  );

  test(
    'a notification during a pending pull triggers another native drain',
    () async {
      final gate = Completer<List<List<String>>>();
      var count = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (++count == 1) return gate.future;
        return [
          ['/media/second.mp4'],
        ];
      });
      final initialized = controller.initialize();
      final notification = notify();
      gate.complete([
        ['/media/first.mp4'],
      ]);
      await initialized;
      await notification;
      expect(controller.takeNext(), ['/media/first.mp4']);
      expect(controller.takeNext(), ['/media/second.mp4']);
      expect(count, 2);
    },
  );

  test('folder authorization is requested explicitly with language', () async {
    await controller.initialize();
    expect(await controller.requestFolderAccess('/media', 'ja'), isNull);
    expect(calls.last.method, 'requestFolderAccess');
    expect(calls.last.arguments, {'path': '/media', 'language': 'ja'});
  });

  test(
    'normal launch stays on home, external cold launch selects player',
    () async {
      final normal = AppNavigationController(
        preferences: _Preferences(),
        restoreLastSection: false,
      );
      final external = AppNavigationController(
        preferences: _Preferences(),
        restoreLastSection: false,
      );
      await normal.load();
      await external.load(initialSection: AppSection.player);
      expect(normal.section, AppSection.home);
      expect(external.section, AppSection.player);
      normal.dispose();
      external.dispose();
    },
  );

  test(
    'sibling scan includes only direct nonhidden video files in natural order',
    () async {
      final root = await Directory.systemTemp.createTemp('sibling-videos-');
      try {
        for (final name in [
          'lesson10.mp4',
          'lesson2.MKV',
          'lesson1.mov',
          '.hidden.mp4',
          'audio.mp3',
          'notes.srt',
        ]) {
          await File('${root.path}/$name').writeAsBytes([0]);
        }
        await Directory('${root.path}/nested.mp4').create();
        await File('${root.path}/nested.mp4/child.mp4').writeAsBytes([0]);
        await Link('${root.path}/linked.mp4')
            .create('${root.path}/lesson1.mov');
        expect((await siblingVideoPaths(root)).map((p) => p.split('/').last), [
          'lesson1.mov',
          'lesson2.MKV',
          'lesson10.mp4',
        ]);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  testWidgets('warm Finder event navigates from home to player', (
    tester,
  ) async {
    final navigation = AppNavigationController(
      preferences: _Preferences(),
      restoreLastSection: false,
    );
    await navigation.load();
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopMediaOpenRouter(
          controller: controller,
          navigation: navigation,
          child: GoodGoodStudyShell(
            controller: navigation,
            iconAsset: null,
            builders: {
              AppSection.player: (_) =>
                  const Scaffold(body: Text('External player')),
            },
          ),
        ),
      ),
    );
    inbox = [
      ['/media/selected.mp4'],
    ];
    await notify();
    await tester.pumpAndSettle();
    expect(find.text('External player'), findsOneWidget);
    expect(controller.hasPending, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    navigation.dispose();
  });

  testWidgets(
    'refused leave guard keeps external files queued without repeated prompts',
    (tester) async {
      final navigation = AppNavigationController(
        preferences: _Preferences(),
        restoreLastSection: false,
      );
      await navigation.load(initialSection: AppSection.quiz);
      await controller.initialize();
      var attempts = 0;
      navigation.registerBeforeLeave(() async {
        attempts++;
        return false;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopMediaOpenRouter(
            controller: controller,
            navigation: navigation,
            child: const SizedBox(),
          ),
        ),
      );
      inbox = [
        ['/media/selected.mp4'],
      ];
      await notify();
      await tester.pumpAndSettle();
      expect(navigation.section, AppSection.quiz);
      expect(attempts, 1);
      expect(controller.hasPending, isTrue);
      await tester.pumpAndSettle();
      expect(attempts, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      navigation.dispose();
    },
  );
}

class _Preferences extends NavigationPreferences {
  @override
  Future<AppSection> read() async => AppSection.study;
  @override
  Future<void> write(AppSection section) async {}
}
