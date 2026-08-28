import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  void initState() {
    super.initState();
    _load();
  }

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
  void dispose() {
    _serverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _serverCtrl,
            decoration: const InputDecoration(labelText: '服务器地址', hintText: AppConfig.defaultServerUrl, border: OutlineInputBorder()),
            onSubmitted: (v) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('server_url', v.trim());
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存，重启 App 后生效（或点立即同步）')));
            },
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('server_url', _serverCtrl.text.trim());
              await ref.read(syncEngineProvider).forceSync();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已触发同步')));
            },
            child: const Text('保存并立即同步'),
          ),
          const Divider(height: 32),
          ListTile(title: const Text('设备 ID'), subtitle: Text(_deviceId ?? '加载中…')),
          const ListTile(title: Text('App 版本'), subtitle: Text(AppConfig.appVersion)),
          ListTile(title: const Text('最后同步游标'), subtitle: Text(_lastSync ?? '—')),
          ListTile(title: const Text('待同步队列'), subtitle: Text(_pending ?? '—')),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () async {
              await ref.read(syncEngineProvider).forceSync();
              await _load();
            },
            child: const Text('刷新状态'),
          ),
        ],
      ),
    );
  }
}
