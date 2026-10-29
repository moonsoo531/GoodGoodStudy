enum PlaylistMode {
  manual,
  sequential,
  repeatOne,
  repeatAll;

  String get label => switch (this) {
    manual => '播完暂停',
    sequential => '顺序播放',
    repeatOne => '单项循环',
    repeatAll => '列表循环',
  };

  bool get autoAdvance => this != manual;

  int? nextIndex(int current, int length) {
    if (length <= 0 || current < 0 || current >= length) return null;
    return switch (this) {
      manual => null,
      sequential => current + 1 < length ? current + 1 : null,
      repeatOne => current,
      repeatAll => (current + 1) % length,
    };
  }

  static PlaylistMode fromJson(Object? value, {bool legacyAutoAdvance = true}) {
    for (final mode in values) {
      if (mode.name == value) return mode;
    }
    return legacyAutoAdvance ? sequential : manual;
  }
}
