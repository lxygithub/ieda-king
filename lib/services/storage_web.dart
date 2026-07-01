import 'dart:html' as html;

import 'storage_service.dart';

/// Web implementation using localStorage.
class WebStorageService extends StorageService {
  @override
  Future<void> initialize() async {
    // localStorage is immediately available on web
  }

  @override
  String? decodeString(String key) {
    return html.window.localStorage[key];
  }

  @override
  void encodeString(String key, String value) {
    html.window.localStorage[key] = value;
  }

  @override
  int? decodeInt(String key) {
    final value = html.window.localStorage[key];
    if (value == null) return null;
    return int.tryParse(value);
  }

  @override
  void encodeInt(String key, int value) {
    html.window.localStorage[key] = value.toString();
  }

  @override
  bool? decodeBool(String key) {
    final value = html.window.localStorage[key];
    if (value == null) return null;
    return value == 'true';
  }

  @override
  void encodeBool(String key, bool value) {
    html.window.localStorage[key] = value.toString();
  }

  @override
  void removeValue(String key) {
    html.window.localStorage.remove(key);
  }
}

/// Factory function to create web storage service.
StorageService createStorageService() {
  return WebStorageService();
}
