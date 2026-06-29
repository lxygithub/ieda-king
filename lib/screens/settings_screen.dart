import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/timeline_provider.dart';
import '../services/api_service.dart';
import '../utils/file_handler.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== Account =====
          Text('账号', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(auth.username ?? '未登录'),
                  subtitle: Text(auth.isAdmin ? '管理员' : '普通用户'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                if (!auth.isAdmin)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('修改用户名'),
                    onTap: () => _showChangeUsername(context),
                  ),
                if (!auth.isAdmin)
                  const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('修改密码'),
                  onTap: () => _showChangePassword(context),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('退出登录', style: TextStyle(color: Colors.red)),
                  subtitle: const Text('切换其他账号'),
                  onTap: () => _confirmLogout(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ===== Upload =====
          Text('上传管理', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('重传失败文件'),
              subtitle: const Text('重新上传所有上传失败的文件'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _confirmRetryAll(context),
            ),
          ),
          const SizedBox(height: 24),

          // ===== Data =====
          Text('数据管理', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('清理本地缓存'),
                  subtitle: const Text('删除 received/ 目录下的本地文件副本'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _confirmClearCache(context),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('清空所有记录'),
                  subtitle: const Text('删除时间线全部记录, 保留本地文件'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _confirmClearAll(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePassword(BuildContext context) async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
                title: const Text('修改密码'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: oldCtrl, obscureText: true,
                        decoration: const InputDecoration(labelText: '当前密码', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    TextField(controller: newCtrl, obscureText: true,
                        decoration: const InputDecoration(labelText: '新密码(至少6位)', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    TextField(controller: confirmCtrl, obscureText: true,
                        decoration: const InputDecoration(labelText: '确认新密码', border: OutlineInputBorder())),
                    if (error != null)
                      Padding(padding: const EdgeInsets.only(top: 8),
                          child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                  TextButton(onPressed: () async {
                    if (newCtrl.text.length < 6) {
                      setDialogState(() => error = '密码至少6位');
                      return;
                    }
                    if (newCtrl.text != confirmCtrl.text) {
                      setDialogState(() => error = '两次密码不一致');
                      return;
                    }
                    try {
                      await ApiService.instance.changePassword(oldCtrl.text, newCtrl.text);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } on ApiException catch (e) {
                      setDialogState(() => error = e.message);
                    } catch (e) {
                      final s = e.toString();
                      final msg = s.contains('TimeoutException') || s.contains('SocketException') || s.contains('Connection refused')
                          ? '网络连接失败，请检查网络后重试'
                          : '请求失败: $e';
                      setDialogState(() => error = msg);
                    }
                  }, child: const Text('确认')),
                ],
              )),
    );
    if (ok == true && context.mounted) {
      // Force logout so user re-logs in with new password
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密码已修改，请重新登录')));
      Navigator.of(context).popUntil((r) => r.isFirst);
      await context.read<AuthProvider>().logout();
    }
  }

  Future<void> _showChangeUsername(BuildContext context) async {
    final ctrl = TextEditingController();
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
                title: const Text('修改用户名'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: ctrl,
                        decoration: const InputDecoration(
                            labelText: '新用户名(至少3位)', border: OutlineInputBorder())),
                    if (error != null)
                      Padding(padding: const EdgeInsets.only(top: 8),
                          child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                  TextButton(onPressed: () async {
                    if (ctrl.text.trim().length < 3) {
                      setDialogState(() => error = '用户名至少3位');
                      return;
                    }
                    try {
                      await ApiService.instance.changeUsername(ctrl.text.trim());
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } on ApiException catch (e) {
                      setDialogState(() => error = e.message);
                    } catch (e) {
                      final s = e.toString();
                      final msg = s.contains('TimeoutException') || s.contains('SocketException') || s.contains('Connection refused')
                          ? '网络连接失败，请检查网络后重试'
                          : '请求失败: $e';
                      setDialogState(() => error = msg);
                    }
                  }, child: const Text('确认')),
                ],
              )),
    );
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('用户名已修改，请重新登录')));
      Navigator.of(context).popUntil((r) => r.isFirst);
      await context.read<AuthProvider>().logout();
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定退出当前账号？下次需要重新登录。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      // Pop back to timeline first, then logout triggers navigation to login
      Navigator.of(context).popUntil((r) => r.isFirst);
      await context.read<AuthProvider>().logout();
    }
  }

  Future<void> _confirmRetryAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重传失败文件'),
        content: const Text('重新尝试上传所有上传失败的文件？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('重试'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      context.read<TimelineProvider>().retryAllFailed();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在重试失败的上传...')),
        );
      }
    }
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空所有记录'),
        content: const Text('删除所有文件记录, 本地文件和 S3 文件不受影响。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<TimelineProvider>().clearAll();
      if (context.mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _confirmClearCache(BuildContext context) async {
    final size = await FileHandler.getCacheSize();
    if (!context.mounted) return;

    final sizeStr = FileHandler.formatSize(size);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理本地缓存'),
        content: Text('当前缓存大小: $sizeStr\n\n'
            '将删除 received/ 目录下的所有本地文件副本。\n'
            '已上传到 S3 的文件不受影响，仍可在时间线中查看。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final count = await FileHandler.clearCache();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清理 $count 个文件, 释放 $sizeStr')),
        );
      }
    }
  }
}
