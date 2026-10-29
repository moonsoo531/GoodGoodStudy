import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/library/playlist_mode.dart';

void main() {
  test('natural completion resolves sequential, repeat one and repeat all', () {
    expect(PlaylistMode.sequential.nextIndex(0, 3), 1);
    expect(PlaylistMode.sequential.nextIndex(2, 3), isNull);
    expect(PlaylistMode.repeatOne.nextIndex(1, 3), 1);
    expect(PlaylistMode.repeatAll.nextIndex(2, 3), 0);
    expect(PlaylistMode.repeatAll.nextIndex(0, 1), 0);
    expect(PlaylistMode.manual.nextIndex(0, 3), isNull);
    for (final mode in PlaylistMode.values) {
      expect(mode.nextIndex(-1, 3), isNull);
      expect(mode.nextIndex(3, 3), isNull);
      expect(mode.nextIndex(0, 0), isNull);
    }
  });

  test('legacy auto advance maps to compatible modes', () {
    expect(PlaylistMode.fromJson(null), PlaylistMode.sequential);
    expect(
      PlaylistMode.fromJson(null, legacyAutoAdvance: false),
      PlaylistMode.manual,
    );
    expect(PlaylistMode.fromJson('repeatAll'), PlaylistMode.repeatAll);
    expect(
      PlaylistMode.fromJson('unknown', legacyAutoAdvance: false),
      PlaylistMode.manual,
    );
  });
}
