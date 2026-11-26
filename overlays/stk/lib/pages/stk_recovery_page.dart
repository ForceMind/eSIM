import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Uses public system UI only; a successful launch request is not a profile switch.
class StkRecoveryPage extends StatefulWidget {
  const StkRecoveryPage({super.key});

  @override
  State<StkRecoveryPage> createState() => _StkRecoveryPageState();
}

class _StkRecoveryPageState extends State<StkRecoveryPage> {
  static const _channel = MethodChannel('io.github.forcemind/stk_recovery');
  List<Map<String, String>> _entries = [];
  bool _busy = true;
  String? _notice;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  String _t(String zh, String en) => _zh ? zh : en;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final data = await _channel.invokeListMethod<dynamic>('list');
      final entries = <Map<String, String>>[];
      for (final entry in data ?? []) {
        if (entry is Map &&
            entry['id'] is String &&
            entry['label'] is String &&
            entry['packageName'] is String) {
          entries.add({
            'id': entry['id'] as String,
            'label': entry['label'] as String,
            'packageName': entry['packageName'] as String,
          });
        }
      }
      if (mounted) setState(() => _entries = entries);
    } catch (_) {
      if (mounted) {
        setState(() {
          _entries = [];
          _notice = _t('无法查询系统入口。', 'Unable to query system launchers.');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request(String method, [String? id]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final outcome = await _channel.invokeMethod<String>(
        method,
        id == null ? null : {'id': id},
      );
      if (!mounted) return;
      setState(() {
        _notice = switch (outcome) {
          'launch_requested' => _t(
            '已请求打开系统 STK。请在系统菜单中手动选择配置；此处无法确认菜单已显示或切卡成功。',
            'STK launch requested. Choose the profile in the system menu. Menu display and switching are not confirmed.',
          ),
          'settings_requested' => _t(
            '已请求打开网络设置；请查找 SIM 卡工具包，而非系统默认数据卡切换。',
            'Network settings requested. Look for SIM Toolkit, not the default data SIM selector.',
          ),
          _ => _t('系统未确认启动请求。', 'Launch request not confirmed.'),
        };
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _notice = error.code == 'DENIED'
            ? _t('系统拒绝启动该入口。', 'Android refused to launch this entry.')
            : _t('该系统入口无法打开。', 'This system entry could not be opened.');
      });
    } catch (_) {
      if (mounted) {
        setState(() => _notice = _t('无法启动系统入口。', 'Unable to launch system entry.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_t('SIM 卡工具包（STK）', 'SIM Toolkit (STK)'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(_t(
            '备用切卡入口：通过手机系统提供的 SIM Toolkit 手动切换 9eSIM 卡内配置。不需要先成功连接 OMAPI。请选择对应实体卡，切换后返回主界面手动刷新。',
            'Recovery route: switch the 9eSIM profile manually in the phone’s SIM Toolkit. No working OMAPI connection is required. Select the physical card, then return and refresh manually.',
          )),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          if (!_busy && _entries.isEmpty)
            Text(_t(
              '未找到可启动的已知系统 STK 入口。系统可能隐藏、禁用或使用其他厂商实现；这不代表卡不支持 STK。',
              'No known launchable system STK entry found. It may be hidden, disabled or vendor-specific; this does not prove STK is unsupported.',
            )),
          for (final entry in _entries)
            Card(
              child: ListTile(
                leading: const Icon(Icons.sim_card_outlined),
                title: Text(entry['label']!),
                subtitle: Text(entry['id']!),
                trailing: const Icon(Icons.open_in_new),
                enabled: !_busy,
                onTap: _busy ? null : () => _request('open', entry['id']),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : _refresh,
            child: Text(_t('重新检测 STK 入口', 'Refresh STK entries')),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _request('settings'),
            child: Text(_t('打开系统网络设置', 'Open system network settings')),
          ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SelectableText(_notice!),
            ),
          const SizedBox(height: 12),
          Text(_t(
            '若三星系统 STK 本身无响应，本入口也可能失败。此功能不模拟 STK、不修改访问规则、不自动切卡。可继续使用已验证的小米 STK 恢复方式。',
            'If Samsung’s system STK itself is unresponsive, this route may also fail. This feature does not emulate STK, change access rules or switch profiles automatically. Use the known working Xiaomi STK recovery route if needed.',
          )),
        ],
      ),
    );
  }
}
