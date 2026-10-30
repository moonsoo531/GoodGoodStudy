import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

void registerProjectLicense() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(
      'assets/licenses/GoodGoodStudy-MIT.txt',
    );
    yield LicenseEntryWithLineBreaks(const ['GoodGoodStudy'], text);
  });
}
