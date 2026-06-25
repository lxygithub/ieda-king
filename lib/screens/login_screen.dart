import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLastUsername();
  }

  Future<void> _loadLastUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('last_username');
    if (saved != null && saved.isNotEmpty && mounted) {
      _usernameCtrl.text = saved;
      _passwordFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _saveLastUsername(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_username', name);
  }

  Future<void> _login() async {
    final name = _usernameCtrl.text.trim();
    final pass = _passwordCtrl.text;
    if (name.isEmpty || pass.isEmpty) {
      setState(() => _error = '请输入用户名和密码');
      return;
    }
    setState(() => _error = null);
    try {
      await context.read<AuthProvider>().login(name, pass);
      await _saveLastUsername(name);
    } on ApiException catch (e) {
      final msg = e.message.contains('Invalid')
          ? '用户名或密码错误'
          : e.message;
      if (mounted) setState(() => _error = msg);
    } catch (e) {
      final s = e.toString();
      final msg = s.contains('TimeoutException') || s.contains('SocketException')
          ? '连接服务器失败，请检查网络'
          : '登录失败: $e';
      if (mounted) setState(() => _error = msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lightbulb_outline,
                  size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text('点子王',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 32),
              TextField(
                controller: _usernameCtrl,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                autocorrect: false,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordCtrl,
                focusNode: _passwordFocus,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _login(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: auth.isLoading ? null : _login,
                  child: auth.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('登录'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/register'),
                child: const Text('注册新账号'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
