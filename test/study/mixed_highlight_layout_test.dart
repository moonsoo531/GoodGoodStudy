import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/l10n/app_localizations.dart';
import 'package:offline_player/study/study_models.dart';
import 'package:offline_player/study/study_passage_text.dart';
import 'package:offline_player/theme/app_theme.dart';

const _terms = ['偏り', '食べる', '手に入れ'];
const _readings = [
  [StudyRuby(start: 0, end: 1, reading: 'かたよ')],
  [StudyRuby(start: 0, end: 1, reading: 'た')],
  [
    StudyRuby(start: 0, end: 1, reading: 'て'),
    StudyRuby(start: 2, end: 3, reading: 'い'),
  ],
];

void main() {
  final screenshotDirectory =
      Platform.environment['MIXED_HIGHLIGHT_SCREENSHOTS'];
  var realFontLoaded = false;
  for (final language in ['zh', 'ja', 'en']) {
    for (final scale in [1.0, 1.3, 1.6]) {
      testWidgets(
        '$language mixed highlights share size and baseline at $scale',
        (tester) async {
          tester.view.physicalSize = const Size(393, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          if (!realFontLoaded &&
              Directory('/System/Library/Fonts').existsSync()) {
            await tester.runAsync(() async {
              final font = Directory('/System/Library/Fonts')
                  .listSync()
                  .whereType<File>()
                  .firstWhere((file) => file.path.endsWith('W3.ttc'));
              final data = await font.readAsBytes();
              await (FontLoader(
                'MixedHighlightJapanese',
              )..addFont(Future.value(ByteData.sublistView(data)))).load();
            });
            realFontLoaded = true;
          }
          final boundaryKey = GlobalKey();
          final taps = <String>[];
          final theme = buildAppTheme(Brightness.light);
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: appLocalizationDelegates,
              theme: theme.copyWith(
                platform: TargetPlatform.iOS,
                textTheme: realFontLoaded
                    ? theme.textTheme.apply(
                        fontFamily: 'MixedHighlightJapanese',
                      )
                    : theme.textTheme,
              ),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: RepaintBoundary(
                    key: boundaryKey,
                    child: Container(
                      color: const Color(0xfff6f8f7),
                      width: 350,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < _terms.length; i++)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: StudyPassageText(
                                segment: StudySegment(
                                  id: 'mixed-$i',
                                  text: '${_terms[i]}を覚える。',
                                  translationZh: '',
                                  highlights: [
                                    StudyHighlight(
                                      start: 0,
                                      end: _terms[i].length,
                                      entryId: 'term-$i',
                                    ),
                                  ],
                                  ruby: _readings[i],
                                ),
                                entries: {
                                  'term-$i': StudyEntry(
                                    id: 'term-$i',
                                    surface: _terms[i],
                                    reading: '',
                                    meaningZh: '',
                                    kind: 'vocabulary',
                                    attributes: const {},
                                    tags: const [],
                                    relations: const [],
                                  ),
                                },
                                showReadings: true,
                                onEntryTap: (entry) => taps.add(entry.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final raster = await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 3);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final result = (bytes!, image.width, image.height);
            image.dispose();
            return result;
          });
          for (var i = 0; i < _terms.length; i++) {
            final first = _fragment(tester, 'term-mixed-$i-0');
            final kana = _fragment(tester, 'term-mixed-$i-0-part-1');
            final kanjiRect = _glyphRect(first.$1, 0);
            final kanaRect = _glyphRect(kana.$1, 0);
            expect(
              kanjiRect.height,
              closeTo(kanaRect.height, 1),
              reason:
                  '${_terms[i]} rendered kanji and kana must have the same size',
            );
            expect(
              first.$2,
              closeTo(kana.$2, 1),
              reason:
                  '${_terms[i]} baseline must continue through the ruby split',
            );
            final firstLine = _underlineCenter(
              raster!.$1,
              raster.$2,
              raster.$3,
              boundary: boundary,
              paragraph: first.$1,
              baseline: first.$2,
              scale: scale,
            );
            final kanaLine = _underlineCenter(
              raster.$1,
              raster.$2,
              raster.$3,
              boundary: boundary,
              paragraph: kana.$1,
              baseline: kana.$2,
              scale: scale,
            );
            expect(
              firstLine,
              closeTo(kanaLine, 0.75),
              reason:
                  '${_terms[i]} visible underline must continue at one height',
            );
            await tester.tap(find.byKey(ValueKey('term-mixed-$i-0')));
            await tester.tap(find.byKey(ValueKey('term-mixed-$i-0-part-1')));
          }
          expect(taps, [
            'term-0',
            'term-0',
            'term-1',
            'term-1',
            'term-2',
            'term-2',
          ]);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (screenshotDirectory != null && language == 'zh') {
            await tester.runAsync(() async {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '$screenshotDirectory/mixed-highlights-$scale.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        },
      );
    }
  }
  testWidgets(
    'long highlighted text paints an underline on every wrapped line',
    (tester) async {
      const text = '手に入れにくい品物を探しながら新しい店で買い物を続けている。';
      const entry = StudyEntry(
        id: 'long',
        surface: text,
        reading: '',
        meaningZh: '',
        kind: 'vocabulary',
        attributes: {},
        tags: [],
        relations: [],
      );
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: RepaintBoundary(
                key: boundaryKey,
                child: Container(
                  color: const Color(0xfff6f8f7),
                  width: 160,
                  child: StudyPassageText(
                    segment: const StudySegment(
                      id: 'wrapped',
                      text: text,
                      translationZh: '',
                      ruby: [],
                      highlights: [
                        StudyHighlight(
                          start: 0,
                          end: text.length,
                          entryId: 'long',
                        ),
                      ],
                    ),
                    entries: const {'long': entry},
                    showReadings: false,
                    onEntryTap: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fragment = _fragment(tester, 'term-wrapped-0');
      final paragraph = fragment.$1;
      final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: text.length),
      );
      expect(boxes.length, greaterThanOrEqualTo(3));
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final raster = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final result = (bytes!, image.width, image.height);
        image.dispose();
        return result;
      });
      final first = MatrixUtils.transformRect(
        paragraph.getTransformTo(null),
        boxes.first.toRect(),
      );
      for (final box in boxes) {
        final ink = MatrixUtils.transformRect(
          paragraph.getTransformTo(null),
          box.toRect(),
        );
        _underlineCenter(
          raster!.$1,
          raster.$2,
          raster.$3,
          boundary: boundary,
          paragraph: paragraph,
          baseline: fragment.$2 + ink.bottom - first.bottom,
          scale: 1.3,
          inkRange: ink,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
}

(RenderParagraph, double) _fragment(WidgetTester tester, String key) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(RichText),
    ),
  );
  final baseline = paragraph.localToGlobal(
    Offset(
      0,
      paragraph.getDryBaseline(paragraph.constraints, TextBaseline.alphabetic)!,
    ),
  );
  return (paragraph, baseline.dy);
}

Rect _glyphRect(RenderParagraph paragraph, int offset) {
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + 1),
      )
      .single;
  return MatrixUtils.transformRect(
    paragraph.getTransformTo(null),
    box.toRect(),
  );
}

// Inspect the actual painted stroke, rather than the decoration/painter fields.
double _underlineCenter(
  ByteData bytes,
  int width,
  int height, {
  required RenderRepaintBoundary boundary,
  required RenderParagraph paragraph,
  required double baseline,
  required double scale,
  Rect? inkRange,
}) {
  const ratio = 3.0;
  final boundaryOrigin = boundary.localToGlobal(Offset.zero);
  final rect =
      inkRange ??
      MatrixUtils.transformRect(
        paragraph.getTransformTo(null),
        Offset.zero & paragraph.size,
      );
  final left = ((rect.left + rect.width * .2 - boundaryOrigin.dx) * ratio)
      .ceil();
  final right = ((rect.right - rect.width * .2 - boundaryOrigin.dx) * ratio)
      .floor();
  final top = ((baseline + .5 * scale - boundaryOrigin.dy) * ratio).floor();
  final bottom = ((baseline + 7 * scale - boundaryOrigin.dy) * ratio).ceil();
  final rows = <int>[];
  for (var y = top; y <= bottom && y < height; y++) {
    if (y < 0) continue;
    var colored = 0;
    for (var x = left; x <= right && x < width; x++) {
      if (x < 0) continue;
      final offset = (y * width + x) * 4;
      final r = bytes.getUint8(offset),
          g = bytes.getUint8(offset + 1),
          b = bytes.getUint8(offset + 2);
      if (g > r + 20 && g > b + 5) colored++;
    }
    if (colored >= (right - left + 1) * .8) rows.add(y);
  }
  expect(
    rows,
    isNotEmpty,
    reason: 'A visible underline must be painted below the glyph baseline',
  );
  return (rows.first + rows.last) / (2 * ratio) + boundaryOrigin.dy;
}
