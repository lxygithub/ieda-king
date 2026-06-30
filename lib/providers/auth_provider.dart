import 'package:flutter/material.dart';
import 'package:mmkv/mmkv.dart';

import '../services/api_service.dart';

/// Manages authentication state: token, current user, login/logout/register.
class AuthProvider extends ChangeNotifier {
  String? _token;
  int? _userId;
  String? _username;
  bool _isAdmin = false;
  bool _isLoading = false;
  bool _initialized = false;

  String? get token => _token;
  int? get userId => _userId;
  String? get username => _username;
  bool get isAdmin => _isAdmin;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _token != null;
  bool get initialized => _initialized;
  String? get error => _error;
  String? _error;

  /// Load persisted token from MMKV. Returns immediately after local load.
  /// Token verification happens in background via [verifyToken].
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();
    try {
      final mmkv = MMKV.defaultMMKV();
      _token = mmkv.decodeString('jwt_token');
      _userId = mmkv.decodeInt('user_id');
      _username = mmkv.decodeString('username');
      _isAdmin = mmkv.decodeBool('is_admin') ?? false;
      ApiService.instance.token = _token;
      // Register token expiry callback
      ApiService.instance.onTokenExpired = () {
        _token = null;
        _userId = null;
        _username = null;
        _isAdmin = false;
        ApiService.instance.token = null;
        notifyListeners();
      };
    } finally {
      _isLoading = false;
      _initialized = true;
      notifyListeners();
    }
    // Verify token in background (non-blocking, after UI is shown)
    if (_token != null) {
      verifyToken();
    }
  }

  /// Verify token validity in background. Called after init() completes.
  Future<void> verifyToken() async {
    if (_token == null) return;
    try {
      await ApiService.instance.getFiles();
    } on TokenExpiredException {
      _token = null;
      _userId = null;
      _username = null;
      _isAdmin = false;
      ApiService.instance.token = null;
      await _persist();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persist() async {
    final mmkv = MMKV.defaultMMKV();
    if (_token != null) {
      mmkv.encodeString('jwt_token', _token!);
      mmkv.encodeInt('user_id', _userId!);
      mmkv.encodeString('username', _username!);
      mmkv.encodeBool('is_admin', _isAdmin);
    } else {
      mmkv.removeValue('jwt_token');
      mmkv.removeValue('user_id');
      mmkv.removeValue('username');
      mmkv.removeValue('is_admin');
    }
  }

  /// Register a new account, then auto-login.
  Future<void> register(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await ApiService.instance.register(username, password);
      // Auto-login after registration
      await login(username, password);
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Login with username/password, store JWT.
  Future<void> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await ApiService.instance.login(username, password);
      _token = result['access_token'] as String?;
      _userId = result['user_id'] as int?;
      _username = result['username'] as String?;
      _isAdmin = result['is_admin'] as bool? ?? false;
      ApiService.instance.token = _token;
      await _persist();
    } catch (e) {
      _token = null;
      ApiService.instance.token = null;
      _error = e.toString();
      await _persist();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear token and persisted state.
  Future<void> logout() async {
    _token = null;
    _userId = null;
    _username = null;
    _isAdmin = false;
    _error = null;
    ApiService.instance.token = null;
    ApiService.instance.onTokenExpired = null;
    await _persist();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
