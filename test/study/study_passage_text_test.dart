import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/study/study_models.dart';
import 'package:offline_player/study/study_passage_text.dart';

const _entry = StudyEntry(
  id: 'create',
  surface: '創作',
  reading: 'そうさく',
  meaningZh: '创作',
  kind: 'vocabulary',
  attributes: {},
  tags: [],
  relations: [],
);
const _eat = StudyEntry(
  id: 'eat',
  surface: '食べる',
  reading: 'たべる',
  meaningZh: '吃',
  kind: 'vocabulary',
  attributes: {},
  tags: [],
  relations: [],
);
const _segment = StudySegment(
  id: 'sample',
  text: '創作料理を食べる。',
  translationZh: '吃创意料理。',
  highlights: [
    StudyHighlight(start: 0, end: 2, entryId: 'create'),
    StudyHighlight(start: 5, end: 8, entryId: 'eat'),
  ],
  ruby: [
    StudyRuby(start: 0, end: 4, reading: 'そうさくりょうり'),
    StudyRuby(start: 5, end: 6, reading: 'た'),
  ],
);

void main() {
  testWidgets('ruby above the base retains taps across highlight boundaries', (
    tester,
  ) async {
    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: StudyPassageText(
              segment: _segment,
              entries: const {'create': _entry, 'eat': _eat},
              showReadings: true,
              onEntryTap: (entry) => taps.add(entry.id),
            ),
          ),
        ),
      ),
    );
    expect(find.text('そうさくりょうり'), findsOneWidget);
    expect(find.text('た'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('そうさくりょうり')).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('term-sample-0'))).dy,
      ),
    );
    // Ruby must not move its kanji below neighboring unannotated text.
    final outer = find
        .descendant(
          of: find.byType(StudyPassageText),
          matching: find.byType(RichText),
        )
        .first;
    final base = find.descendant(
      of: find.byKey(const ValueKey('term-sample-0')),
      matching: find.byType(RichText),
    );
    double glyphBottom(Finder finder, int offset) {
      final box = tester.renderObject<RenderParagraph>(finder);
      return box.localToGlobal(Offset.zero).dy +
          box
              .getBoxesForSelection(
                TextSelection(baseOffset: offset, extentOffset: offset + 1),
              )
              .first
              .bottom;
    }

    expect(glyphBottom(base, 0), closeTo(glyphBottom(outer, 1), 1.0));
    await tester.tap(find.byKey(const ValueKey('term-sample-0')));
    await tester.tap(find.byKey(const ValueKey('term-sample-5')));
    await tester.tap(find.byKey(const ValueKey('term-sample-5-part-6')));
    expect(taps, ['create', 'eat', 'eat']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden ruby leaves intact base text and clickable terms', (
    tester,
  ) async {
    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyPassageText(
            segment: _segment,
            entries: const {'create': _entry, 'eat': _eat},
            showReadings: false,
            onEntryTap: (entry) => taps.add(entry.id),
          ),
        ),
      ),
    );
    expect(find.text('そうさくりょうり'), findsNothing);
    expect(find.text('食べる'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('term-sample-0')));
    expect(taps, ['create']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long source readings fit a narrow view at large text scaling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 220,
                child: StudyPassageText(
                  segment: const StudySegment(
                    id: 'long',
                    text: '情報通信技術研究開発機関です。',
                    translationZh: '研究机构。',
                    highlights: [],
                    ruby: [
                      StudyRuby(
                        start: 0,
                        end: 12,
                        reading: 'じょうほうつうしんぎじゅつけんきゅうかいはつきかん',
                      ),
                    ],
                  ),
                  entries: const {},
                  showReadings: true,
                  onEntryTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
