import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/database_service.dart';

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

  /// Load persisted token from SharedPreferences and verify it.
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('jwt_token');
      _userId = prefs.getInt('user_id');
      _username = prefs.getString('username');
      _isAdmin = prefs.getBool('is_admin') ?? false;
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
      // Verify token is still valid by making a lightweight API call
      if (_token != null) {
        try {
          await ApiService.instance.getFiles();
        } on TokenExpiredException {
          _token = null;
          _userId = null;
          _username = null;
          _isAdmin = false;
          ApiService.instance.token = null;
          await _persist();
        } catch (_) {
          // Network error — keep cached token, user may be offline
        }
      }
    } finally {
      _isLoading = false;
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) {
      await prefs.setString('jwt_token', _token!);
      await prefs.setInt('user_id', _userId!);
      await prefs.setString('username', _username!);
      await prefs.setBool('is_admin', _isAdmin);
    } else {
      await prefs.remove('jwt_token');
      await prefs.remove('user_id');
      await prefs.remove('username');
      await prefs.remove('is_admin');
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
    // Clear local DB so next user doesn't see old data
    await DatabaseService.clearAll();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
