import 'package:flutter/services.dart';

class AppBuildInfo {
  const AppBuildInfo({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;
}

class AppSupportLinks {
  static const repository = 'https://github.com/moonsoo531/GoodGoodStudy';
  static final source = Uri.parse(repository);
  static final license = Uri.parse('$repository/blob/main/LICENSE');
  static final notices = Uri.parse(
    '$repository/blob/main/THIRD_PARTY_NOTICES.md',
  );
  static final privacy = Uri.parse(
    '$repository/blob/main/docs/privacy-policy.md',
  );
  static final studyFormat = Uri.parse(
    '$repository/blob/main/docs/study-package-v1.md',
  );
  static final quizFormat = Uri.parse(
    '$repository/blob/main/docs/quiz-package-v1.md',
  );
  static final _allowed = Set<Uri>.unmodifiable([
    source,
    license,
    notices,
    privacy,
    studyFormat,
    quizFormat,
  ]);

  static bool allows(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == 'github.com' &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      _allowed.contains(uri);
}

/// Reads the installed build, and opens only this project's public links.
class AppInfoGateway {
  const AppInfoGateway();

  static const channel = MethodChannel('goodgoodstudy/app_info');

  Future<AppBuildInfo?> getInfo() async {
    try {
      final value = await channel.invokeMapMethod<String, dynamic>('getInfo');
      final version = value?['version'];
      final buildNumber = value?['buildNumber'];
      if (version is String &&
          version.trim().isNotEmpty &&
          buildNumber is String &&
          buildNumber.trim().isNotEmpty) {
        return AppBuildInfo(version: version, buildNumber: buildNumber);
      }
    } on Object {
      // Keep help and links available when installed build metadata is absent.
    }
    return null;
  }

  Future<bool> openLink(Uri uri) async {
    if (!AppSupportLinks.allows(uri)) return false;
    try {
      return await channel.invokeMethod<bool>('openLink', {
            'url': uri.toString(),
          }) ==
          true;
    } on Object {
      return false;
    }
  }
}
