import 'package:mmkv/mmkv.dart';

import 'storage_service.dart';

/// MMKV implementation for native platforms (Android, iOS, Windows, macOS, Linux).
class MmkvStorageService extends StorageService {
  MMKV? _mmkv;

  @override
  Future<void> initialize() async {
    await MMKV.initialize();
    _mmkv = MMKV.defaultMMKV();
  }

  @override
  String? decodeString(String key) {
    return _mmkv?.decodeString(key);
  }

  @override
  void encodeString(String key, String value) {
    _mmkv?.encodeString(key, value);
  }

  @override
  int? decodeInt(String key) {
    return _mmkv?.decodeInt(key);
  }

  @override
  void encodeInt(String key, int value) {
    _mmkv?.encodeInt(key, value);
  }

  @override
  bool? decodeBool(String key) {
    return _mmkv?.decodeBool(key);
  }

  @override
  void encodeBool(String key, bool value) {
    _mmkv?.encodeBool(key, value);
  }

  @override
  void removeValue(String key) {
    _mmkv?.removeValue(key);
  }
}

/// Factory function to create MMKV storage service.
StorageService createStorageService() {
  return MmkvStorageService();
}
