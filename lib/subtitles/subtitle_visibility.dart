/// The two subtitle regions have independent preferences. Older releases stored
/// one flag for both; preserve that choice when first loading the split settings.
class SubtitleVisibility {
  const SubtitleVisibility({this.video = true, this.list = true});

  final bool video;
  final bool list;

  factory SubtitleVisibility.fromJson(Map<String, dynamic> json) {
    final legacy = json['showSubtitles'] is bool
        ? json['showSubtitles'] as bool
        : true;
    return SubtitleVisibility(
      video: json['showVideoSubtitles'] is bool
          ? json['showVideoSubtitles'] as bool
          : legacy,
      list: json['showListSubtitles'] is bool
          ? json['showListSubtitles'] as bool
          : legacy,
    );
  }

  SubtitleVisibility copyWith({bool? video, bool? list}) =>
      SubtitleVisibility(video: video ?? this.video, list: list ?? this.list);

  Map<String, dynamic> toJson() => {
    'showVideoSubtitles': video,
    'showListSubtitles': list,
  };
}
