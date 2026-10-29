import 'package:flutter_test/flutter_test.dart';
import 'package:offline_player/playback/player_time.dart';

void main() {
  test('time entry accepts seconds, minute and hour forms', () {
    final samples = <String, Duration>{
      '0': Duration.zero,
      '90': const Duration(seconds: 90),
      '00:05': const Duration(seconds: 5),
      '12:34': const Duration(minutes: 12, seconds: 34),
      '126:30': const Duration(hours: 2, minutes: 6, seconds: 30),
      '1:02:03': const Duration(hours: 1, minutes: 2, seconds: 3),
      '25:00:00': const Duration(hours: 25),
      '  01:02  ': const Duration(minutes: 1, seconds: 2),
      '001:02': const Duration(minutes: 1, seconds: 2),
    };
    for (final entry in samples.entries) {
      expect(parsePlaybackTime(entry.key), entry.value, reason: entry.key);
    }
  });

  test(
    'malformed times, out of range components and negatives are rejected',
    () {
      for (final sample in [
        '',
        ' ',
        ':',
        '1:',
        ':30',
        '1::02',
        '1:2:3:4',
        '-1',
        '-01:30',
        '1:-30',
        '+30',
        '1.5',
        '00:60',
        '1:60:00',
        '1:02:60',
        '1 :02',
        '1: 02',
        'NaN',
        'Infinity',
        '１:３０',
        '99999999999999999999999999',
        '99999999:59:59',
        '100000000',
      ]) {
        expect(parsePlaybackTime(sample), isNull, reason: sample);
      }
    },
  );

  test('time formatting preserves hours, seconds and zero boundaries', () {
    expect(formatPlaybackTime(Duration.zero), '00:00');
    expect(formatPlaybackTime(const Duration(seconds: 5)), '00:05');
    expect(formatPlaybackTime(const Duration(seconds: 3599)), '59:59');
    expect(formatPlaybackTime(const Duration(hours: 1)), '1:00:00');
    expect(
      formatPlaybackTime(const Duration(hours: 2, minutes: 6, seconds: 30)),
      '2:06:30',
    );
    expect(
      formatPlaybackTime(const Duration(hours: 125, minutes: 7, seconds: 8)),
      '125:07:08',
    );
    expect(formatPlaybackTime(const Duration(seconds: -1)), '00:00');
    expect(formatPlaybackTime(const Duration(milliseconds: 1999)), '00:01');
    expect(
      parsePlaybackTime(
        formatPlaybackTime(const Duration(hours: 125, minutes: 7, seconds: 8)),
      ),
      const Duration(hours: 125, minutes: 7, seconds: 8),
    );
  });

  test('supported maximum is bounded consistently for parsing and display', () {
    const maximum = Duration(seconds: 99999999);
    expect(parsePlaybackTime('99999999'), maximum);
    expect(parsePlaybackTime(formatPlaybackTime(maximum)), maximum);
    expect(
      formatPlaybackTime(const Duration(seconds: 100000000)),
      formatPlaybackTime(maximum),
    );
  });
}
