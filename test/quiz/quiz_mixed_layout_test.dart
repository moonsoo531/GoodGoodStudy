import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/l10n/app_localizations.dart';
import 'package:offline_player/quiz/quiz_models.dart';
import 'package:offline_player/quiz/quiz_ruby_text.dart';
import 'package:offline_player/theme/app_theme.dart';

const _ink = Color(0xff006b50);
const _background = Color(0xfff6f8f7);
const _ratio = 3.0;
const _specs = <(String, TextStyle?)>[
  ('prompt', TextStyle(fontSize: 22, height: 1.8, color: _ink)),
  ('option', TextStyle(fontSize: 19, height: 1.5, color: _ink)),
  ('inherited', null),
];

void main() {
  var realFontLoaded = false;
  Future<void> loadFont(WidgetTester tester) async {
    if (realFontLoaded || !Directory('/System/Library/Fonts').existsSync()) {
      return;
    }
    await tester.runAsync(() async {
      final font = Directory('/System/Library/Fonts')
          .listSync()
          .whereType<File>()
          .firstWhere((file) => file.path.endsWith('W3.ttc'));
      final data = await font.readAsBytes();
      await (FontLoader(
        'QuizMixedJapanese',
      )..addFont(Future.value(ByteData.sublistView(data)))).load();
    });
    realFontLoaded = true;
  }

  for (final language in ['zh', 'ja', 'en']) {
    for (final scale in [1.0, 1.3, 1.6]) {
      testWidgets('$language quiz mixed ruby size and underline at $scale', (
        tester,
      ) async {
        await loadFont(tester);
        tester.view.physicalSize = const Size(393, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          _host(
            language: language,
            scale: scale,
            realFont: realFontLoaded,
            child: RepaintBoundary(
              key: boundaryKey,
              child: Container(
                color: _background,
                width: 360,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final spec in _specs)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: QuizRubyText(
                          key: ValueKey(spec.$1),
                          text: '偏りを覚える。',
                          ruby: const [
                            QuizRuby(start: 0, end: 1, reading: 'かたよ'),
                          ],
                          underlines: const [QuizUnderline(start: 0, end: 2)],
                          prefix: '1. ',
                          showReadings: true,
                          style: spec.$2,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final raster = await _raster(tester, boundary);
        for (final spec in _specs) {
          final root = find.byKey(ValueKey(spec.$1));
          final paragraphs = _paragraphs(tester, root);
          final outer = paragraphs.first;
          final base = paragraphs.singleWhere(
            (paragraph) => paragraph.text.toPlainText() == '偏',
          );
          final kanaOffset = outer.text.toPlainText().indexOf('り');
          final kanji = _glyph(base, 0);
          final kana = _glyph(outer, kanaOffset);
          expect(
            kanji.height,
            closeTo(kana.height, .5),
            reason: '${spec.$1} rendered kanji and kana sizes',
          );
          final kanjiBaseline = _baseline(base);
          final kanaBaseline = _baseline(outer);
          expect(
            kanjiBaseline,
            closeTo(kanaBaseline, .5),
            reason: '${spec.$1} body baseline',
          );
          final kanjiLine = _line(
            raster,
            boundary,
            kanji,
            kanjiBaseline,
            scale,
          )!;
          final kanaLine = _line(raster, boundary, kana, kanaBaseline, scale)!;
          expect(
            kanjiLine.$1,
            closeTo(kanaLine.$1, .35),
            reason:
                '${spec.$1} actual painted underline height; baselines $kanjiBaseline / $kanaBaseline; glyph bottoms ${kanji.bottom} / ${kana.bottom}',
          );
          expect(
            kanjiLine.$2,
            closeTo(kanaLine.$2, .4),
            reason: '${spec.$1} actual painted underline thickness',
          );
          expect(
            _line(
              raster,
              boundary,
              _glyph(outer, 0),
              kanaBaseline,
              scale,
              required: false,
            ),
            isNull,
            reason: 'question/option prefix must not be underlined',
          );
        }
        expect(tester.takeException(), isNull);
        final directory = Platform.environment['QUIZ_LAYOUT_SCREENSHOTS'];
        if (directory != null && language == 'zh') {
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('$directory/quiz-mixed-$scale.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
  testWidgets(
    'quiz partial underline keeps only imported characters with readings on or off',
    (tester) async {
      await loadFont(tester);
      tester.view.physicalSize = const Size(393, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final showReadings in [true, false]) {
        final key = GlobalKey();
        await tester.pumpWidget(
          _host(
            language: 'zh',
            scale: 1.3,
            realFont: realFontLoaded,
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: _background,
                width: 350,
                child: QuizRubyText(
                  key: const ValueKey('partial'),
                  text: '学校へ行く。',
                  prefix: '2. ',
                  ruby: const [
                    QuizRuby(start: 0, end: 2, reading: 'がっこう'),
                    QuizRuby(start: 3, end: 4, reading: 'い'),
                  ],
                  underlines: const [QuizUnderline(start: 1, end: 4)],
                  showReadings: showReadings,
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.8,
                    color: _ink,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final raster = await _raster(tester, boundary);
        final paragraphs = _paragraphs(
          tester,
          find.byKey(const ValueKey('partial')),
        );
        final outer = paragraphs.first;
        for (final expected in [
          ('学', false),
          ('校', true),
          ('へ', true),
          ('行', true),
          ('く', false),
          ('2', false),
        ]) {
          final paragraph = paragraphs.firstWhere(
            (p) => p.text.toPlainText().contains(expected.$1),
          );
          final offset = paragraph.text.toPlainText().indexOf(expected.$1);
          final line = _line(
            raster,
            boundary,
            _glyph(paragraph, offset),
            _baseline(paragraph),
            1.3,
            required: expected.$2,
          );
          expect(
            line != null,
            expected.$2,
            reason:
                'only imported range must underline ${expected.$1}, ruby=$showReadings',
          );
        }
        if (!showReadings) {
          expect(outer.text.toPlainText(), '2. 学校へ行く。');
          expect(find.text('がっこう'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'quiz wrapped ranges underline every body line without underlining the prefix',
    (tester) async {
      await loadFont(tester);
      const text = '学校へ行く前に野菜を食べながら日本語の文章を繰り返して練習します。';
      final key = GlobalKey();
      await tester.pumpWidget(
        _host(
          language: 'en',
          scale: 1.3,
          realFont: realFontLoaded,
          child: RepaintBoundary(
            key: key,
            child: Container(
              color: _background,
              width: 160,
              child: const QuizRubyText(
                key: ValueKey('wrapped'),
                text: text,
                prefix: '3. ',
                ruby: [QuizRuby(start: 0, end: 2, reading: 'がっこう')],
                underlines: [QuizUnderline(start: 0, end: text.length)],
                showReadings: true,
                style: TextStyle(fontSize: 22, height: 1.8, color: _ink),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final raster = await _raster(tester, boundary);
      final outer = _paragraphs(
        tester,
        find.byKey(const ValueKey('wrapped')),
      ).first;
      final plain = outer.text.toPlainText();
      final firstOffset = plain.indexOf('へ');
      final first = _glyph(outer, firstOffset);
      final bottoms = <double>[];
      for (var offset = firstOffset; offset < plain.length; offset++) {
        if (plain.codeUnitAt(offset) == 0xfffc) continue;
        final glyph = _glyph(outer, offset);
        if (bottoms.any((bottom) => (bottom - glyph.bottom).abs() < .1)) {
          continue;
        }
        bottoms.add(glyph.bottom);
        _line(
          raster,
          boundary,
          glyph,
          _baseline(outer) + glyph.bottom - first.bottom,
          1.3,
        );
        expect(
          glyph.right,
          lessThanOrEqualTo(boundary.localToGlobal(Offset.zero).dx + 160.5),
        );
      }
      expect(bottoms.length, greaterThanOrEqualTo(4));
      expect(
        _line(
          raster,
          boundary,
          _glyph(outer, 0),
          _baseline(outer),
          1.3,
          required: false,
        ),
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'quiz long ruby base keeps separate underlines on every internal line',
    (tester) async {
      await loadFont(tester);
      const base = '情報通信技術研究開発機関';
      final key = GlobalKey();
      await tester.pumpWidget(
        _host(
          language: 'ja',
          scale: 1.3,
          realFont: realFontLoaded,
          child: RepaintBoundary(
            key: key,
            child: Container(
              color: _background,
              width: 160,
              child: const QuizRubyText(
                key: ValueKey('long-ruby'),
                text: '$baseです。',
                prefix: '4. ',
                ruby: [
                  QuizRuby(
                    start: 0,
                    end: base.length,
                    reading: 'じょうほうつうしんぎじゅつけんきゅうかいはつきかん',
                  ),
                ],
                underlines: [QuizUnderline(start: 0, end: base.length)],
                showReadings: true,
                style: TextStyle(fontSize: 22, height: 1.8, color: _ink),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final raster = await _raster(tester, boundary);
      final paragraphs = _paragraphs(
        tester,
        find.byKey(const ValueKey('long-ruby')),
      );
      final paragraph = paragraphs.singleWhere(
        (p) => p.text.toPlainText() == base,
      );
      final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: base.length),
      );
      expect(boxes.length, greaterThanOrEqualTo(3));
      final first = MatrixUtils.transformRect(
        paragraph.getTransformTo(null),
        boxes.first.toRect(),
      );
      final centers = <double>[];
      for (final box in boxes) {
        final glyphs = MatrixUtils.transformRect(
          paragraph.getTransformTo(null),
          box.toRect(),
        );
        centers.add(
          _line(
            raster,
            boundary,
            glyphs,
            _baseline(paragraph) + glyphs.bottom - first.bottom,
            1.3,
          )!.$1,
        );
      }
      for (var i = 1; i < centers.length; i++) {
        expect(
          centers[i] - centers[i - 1],
          greaterThan(20),
          reason: 'internal ruby lines must not collapse into one underline',
        );
      }
      final outer = paragraphs.first;
      expect(
        _line(
          raster,
          boundary,
          _glyph(outer, 0),
          _baseline(outer),
          1.3,
          required: false,
        ),
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _host({
  required String language,
  required double scale,
  required bool realFont,
  required Widget child,
}) {
  final theme = buildAppTheme(Brightness.light);
  return MaterialApp(
    locale: Locale(language),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: appLocalizationDelegates,
    theme: theme.copyWith(
      platform: TargetPlatform.iOS,
      textTheme: realFont
          ? theme.textTheme.apply(fontFamily: 'QuizMixedJapanese')
          : theme.textTheme,
    ),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: DefaultTextStyle(
          style: TextStyle(
            fontSize: 20,
            height: 1.6,
            color: _ink,
            fontFamily: realFont ? 'QuizMixedJapanese' : null,
          ),
          child: child,
        ),
      ),
    ),
  );
}

List<RenderParagraph> _paragraphs(WidgetTester tester, Finder root) => [
  for (final element
      in find.descendant(of: root, matching: find.byType(RichText)).evaluate())
    element.renderObject! as RenderParagraph,
];

Rect _glyph(RenderParagraph paragraph, int offset) => MatrixUtils.transformRect(
  paragraph.getTransformTo(null),
  paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + 1),
      )
      .single
      .toRect(),
);

double _baseline(RenderParagraph paragraph) => paragraph
    .localToGlobal(
      Offset(
        0,
        paragraph.getDryBaseline(
          paragraph.constraints,
          TextBaseline.alphabetic,
        )!,
      ),
    )
    .dy;

Future<(ByteData, int, int)> _raster(
  WidgetTester tester,
  RenderRepaintBoundary boundary,
) async => (await tester.runAsync(() async {
  final image = await boundary.toImage(pixelRatio: _ratio);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = (data!, image.width, image.height);
  image.dispose();
  return result;
}))!;

(double, double)? _line(
  (ByteData, int, int) raster,
  RenderRepaintBoundary boundary,
  Rect glyph,
  double baseline,
  double scale, {
  bool required = true,
}) {
  final origin = boundary.localToGlobal(Offset.zero);
  final left = ((glyph.left + glyph.width * .25 - origin.dx) * _ratio).ceil();
  final right = ((glyph.right - glyph.width * .25 - origin.dx) * _ratio)
      .floor();
  final top = ((baseline + .4 * scale - origin.dy) * _ratio).floor();
  final bottom = ((baseline + 7 * scale - origin.dy) * _ratio).ceil();
  final rows = <int>[];
  for (var y = top; y <= bottom && y < raster.$3; y++) {
    if (y < 0) continue;
    var colored = 0;
    for (var x = left; x <= right && x < raster.$2; x++) {
      if (x < 0) continue;
      final i = (y * raster.$2 + x) * 4;
      final r = raster.$1.getUint8(i),
          g = raster.$1.getUint8(i + 1),
          b = raster.$1.getUint8(i + 2);
      if (g > r + 20 && g > b + 5) colored++;
    }
    if (colored >= (right - left + 1) * .8) rows.add(y);
  }
  if (required) {
    expect(rows, isNotEmpty, reason: 'actual underline below glyph baseline');
  }
  if (rows.isEmpty) return null;
  return (
    (rows.first + rows.last) / (2 * _ratio) + origin.dy,
    rows.length / _ratio,
  );
}
