import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/timeline_provider.dart';

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
              title: const Text('重置上传状态'),
              subtitle: const Text('清除所有文件的 s3Key, 触发重新上传'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _confirmReset(context),
            ),
          ),
          const SizedBox(height: 24),

          // ===== Data =====
          Text('数据管理', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('清空所有记录'),
              subtitle: const Text('删除时间线全部记录, 保留本地文件'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _confirmClearAll(context),
            ),
          ),
        ],
      ),
    );
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

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置上传状态'),
        content: const Text(
            '将清除所有文件的上传标记, 触发重新上传到 S3。\n\n已有 s3Key 的文件不会被删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<TimelineProvider>().resetUploadStatus();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('上传状态已重置, 正在重新上传...')),
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
}
