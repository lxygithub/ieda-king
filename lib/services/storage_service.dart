import 'storage_stub.dart'
    if (dart.library.io) 'storage_mmkv.dart'
    if (dart.library.js) 'storage_web.dart';

/// Abstract storage service for cross-platform compatibility.
/// Uses MMKV on native platforms and localStorage on web.
abstract class StorageService {
  static StorageService? _instance;

  static StorageService get instance {
    _instance ??= createStorageService();
    return _instance!;
  }

  /// Initialize the storage service.
  Future<void> initialize();

  /// Decode a string value by key.
  String? decodeString(String key);

  /// Encode a string value by key.
  void encodeString(String key, String value);

  /// Decode an integer value by key.
  int? decodeInt(String key);

  /// Encode an integer value by key.
  void encodeInt(String key, int value);

  /// Decode a boolean value by key.
  bool? decodeBool(String key);

  /// Encode a boolean value by key.
  void encodeBool(String key, bool value);

  /// Remove a value by key.
  void removeValue(String key);
}
