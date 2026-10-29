final class RubyTextSegment {
  const RubyTextSegment({required this.text, this.reading});

  final String text;
  final String? reading;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RubyTextSegment &&
          text == other.text &&
          reading == other.reading;

  @override
  int get hashCode => Object.hash(text, reading);
}

final _markupTag = RegExp(r'<([^<>\r\n]*)>');
final _tagName = RegExp(r'^\s*(/?)\s*([A-Za-z][A-Za-z0-9]*)(?:[.\s/]|$)');
final _entity = RegExp(r'&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[A-Za-z]+);');

/// Readings come only from existing rt text; malformed groups become plain text.
List<RubyTextSegment> parseRubyText(String raw) {
  final segments = <RubyTextSegment>[];
  _RubyGroup? ruby;
  var cursor = 0;

  void appendText(String text) {
    final decoded = _decodeEntities(text);
    if (ruby != null) {
      ruby.appendText(decoded);
    } else {
      _appendSegment(segments, RubyTextSegment(text: decoded));
    }
  }

  for (final tag in _markupTag.allMatches(raw)) {
    appendText(raw.substring(cursor, tag.start));
    cursor = tag.end;
    final parsed = _tagName.firstMatch(tag.group(1)!);
    if (parsed == null) {
      appendText(tag.group(0)!);
      continue;
    }
    final name = parsed.group(2)!.toLowerCase();
    final closing = parsed.group(1)!.isNotEmpty;
    if (name == 'ruby') {
      if (!closing) {
        if (ruby == null) {
          ruby = _RubyGroup();
        } else {
          ruby.openNestedRuby();
        }
      } else if (ruby != null && ruby.closeRuby()) {
        for (final segment in ruby.finish()) {
          _appendSegment(segments, segment);
        }
        ruby = null;
      }
    } else if (name == 'rt' && ruby != null) {
      closing ? ruby.closeReading() : ruby.openReading();
    } else if (name == 'rp' && ruby != null) {
      closing ? ruby.closeFallback() : ruby.openFallback();
    } else if (name == 'br' && !closing) {
      appendText('\n');
    }
  }
  appendText(raw.substring(cursor));
  if (ruby != null) {
    _appendSegment(segments, RubyTextSegment(text: ruby.fallbackText));
  }
  return List.unmodifiable(segments);
}

/// Removes valid reading annotations while preserving base text and newlines.
String plainSubtitleText(String raw) =>
    parseRubyText(raw).map((segment) => segment.text).join();

final class _RubyGroup {
  final _segments = <RubyTextSegment>[];
  final _base = StringBuffer();
  final _reading = StringBuffer();
  final _allText = StringBuffer();
  var _depth = 1;
  var _fallbackDepth = 0;
  var _readingOpen = false;
  var _hasReading = false;
  var _valid = true;

  String get fallbackText => _allText.toString();

  void appendText(String text) {
    _allText.write(text);
    if (_fallbackDepth > 0) return;
    (_readingOpen ? _reading : _base).write(text);
  }

  void openNestedRuby() {
    _valid = false;
    _depth++;
  }

  bool closeRuby() => --_depth == 0;

  void openReading() {
    if (_readingOpen || _fallbackDepth > 0 || _base.isEmpty) _valid = false;
    _readingOpen = true;
  }

  void closeReading() {
    if (!_readingOpen || _reading.toString().trim().isEmpty) _valid = false;
    if (_base.isNotEmpty && _reading.isNotEmpty) {
      _segments.add(
        RubyTextSegment(
          text: _base.toString(),
          reading: _reading.toString().trim(),
        ),
      );
      _hasReading = true;
    }
    _base.clear();
    _reading.clear();
    _readingOpen = false;
  }

  void openFallback() {
    if (_readingOpen) _valid = false;
    _fallbackDepth++;
  }

  void closeFallback() {
    if (_fallbackDepth == 0) {
      _valid = false;
    } else {
      _fallbackDepth--;
    }
  }

  List<RubyTextSegment> finish() {
    if (!_valid || !_hasReading || _readingOpen || _fallbackDepth > 0) {
      return [RubyTextSegment(text: fallbackText)];
    }
    if (_base.isNotEmpty) {
      _segments.add(RubyTextSegment(text: _base.toString()));
    }
    return _segments;
  }
}

void _appendSegment(List<RubyTextSegment> segments, RubyTextSegment segment) {
  if (segment.text.isEmpty) return;
  if (segment.reading == null &&
      segments.isNotEmpty &&
      segments.last.reading == null) {
    segments[segments.length - 1] = RubyTextSegment(
      text: segments.last.text + segment.text,
    );
  } else {
    segments.add(segment);
  }
}

String _decodeEntities(String text) => text.replaceAllMapped(_entity, (match) {
  final name = match.group(1)!;
  const named = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': '\u00a0',
    'lrm': '\u200e',
    'rlm': '\u200f',
  };
  if (named.containsKey(name)) return named[name]!;
  if (!name.startsWith('#')) return match.group(0)!;
  final hex = name.length > 2 && name[1].toLowerCase() == 'x';
  final code = int.tryParse(name.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
  if (code == null ||
      code <= 0 ||
      code > 0x10ffff ||
      (code >= 0xd800 && code <= 0xdfff)) {
    return match.group(0)!;
  }
  return String.fromCharCode(code);
});
