import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/theme.dart';
import '../../core/config/app_config.dart';
import '../../core/storage/device_id.dart';
import '../../sync/sync_engine.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _serverCtrl = TextEditingController();
  String? _deviceId;
  String? _lastSync;
  String? _pending;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _serverCtrl.text = prefs.getString('server_url') ?? AppConfig.defaultServerUrl;
    _deviceId = await DeviceIdStore.getOrCreate();
    final db = ref.read(appDatabaseProvider);
    _lastSync = await db.getMeta('sync_cursor');
    final pendings = await db.pendingQueue(limit: 100);
    _pending = pendings.length.toString();
    if (mounted) setState(() {});
  }

  @override
  void dispose() { _serverCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6))),
      ),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text('连接', style: text.titleMedium),
            const SizedBox(height: 10),
            TextField(
              controller: _serverCtrl,
              decoration: const InputDecoration(labelText: '服务器地址', hintText: AppConfig.defaultServerUrl, prefixIcon: Icon(Icons.link_rounded)),
              onSubmitted: (v) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('server_url', v.trim());
                if (!mounted) return;
                // ignore: use_build_context_synchronously
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存，点“保存并同步”立即生效')));
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('server_url', _serverCtrl.text.trim());
                await ref.read(syncEngineProvider).forceSync();
                if (!mounted) return;
                // ignore: use_build_context_synchronously
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已触发同步')));
              },
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: const Text('保存并立即同步'),
            ),
            const SizedBox(height: 20),
            Divider(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text('设备与同步', style: text.titleMedium),
            const SizedBox(height: 10),
            _InfoCard(children: [
              _InfoRow(icon: Icons.phone_android_rounded, label: '设备 ID', value: _deviceId ?? '加载中…'),
              Divider(height: 18, color: scheme.outlineVariant.withValues(alpha: 0.5)),
              _InfoRow(icon: Icons.info_outline_rounded, label: 'App 版本', value: AppConfig.appVersion),
              Divider(height: 18, color: scheme.outlineVariant.withValues(alpha: 0.5)),
              _InfoRow(icon: Icons.sync_rounded, label: '同步游标', value: _lastSync == null ? '—' : _lastSync!.length > 48 ? '${_lastSync!.substring(0, 48)}…' : _lastSync!),
              Divider(height: 18, color: scheme.outlineVariant.withValues(alpha: 0.5)),
              _InfoRow(icon: Icons.hourglass_top_rounded, label: '待同步队列', value: _pending ?? '—'),
            ]),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () async { await ref.read(syncEngineProvider).forceSync(); await _load(); },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('刷新状态'),
            ),
          ],
        ),
      )),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(children: [
      Container(width: 30, height: 30, decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(9)), child: Icon(icon, size: 16, color: scheme.onSurfaceVariant)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: text.labelSmall?.copyWith(color: scheme.outline)),
        const SizedBox(height: 2),
        Text(value, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
      ])),
    ]);
  }
}
