import 'package:flutter/services.dart';

/// The native side alone coordinates iCloud files and placeholder downloads.
class ICloudTransport {
  static const _channel = MethodChannel('goodgoodstudy/icloud');
  void Function(String event)? onChanged;

  ICloudTransport() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed' || call.method == 'accountChanged') {
        onChanged?.call(call.method);
      }
    });
  }

  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        method,
        arguments,
      );
      return value ?? <String, dynamic>{};
    } on MissingPluginException {
      return {
        'supported': false,
        'configured': false,
        'available': false,
        'reason': 'unsupported',
      };
    }
  }

  Future<void> stop() async {
    await call('stop');
  }

  void dispose() {
    onChanged = null;
    _channel.setMethodCallHandler(null);
  }
}
