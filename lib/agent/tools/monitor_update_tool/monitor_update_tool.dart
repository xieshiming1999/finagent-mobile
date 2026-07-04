import '../../message.dart';
import '../../monitor.dart';
import '../../tool.dart';
import '../../tool_context.dart';

class MonitorUpdateTool extends Tool {
  final MonitorStore store;

  MonitorUpdateTool({required this.store});

  @override
  String get name => 'MonitorUpdate';

  @override
  String get description =>
      'Update a monitor: enable/disable, change interval, script, condition, streamUrl, display, or rename.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'id': {'type': 'string', 'description': 'The monitor ID to update'},
      'enabled': {
        'type': 'boolean',
        'description': 'Enable or disable the monitor',
      },
      'interval': {
        'type': 'string',
        'description': 'New polling interval: "1m", "5m", "30m", "1h"',
      },
      'name': {'type': 'string', 'description': 'New display name'},
      'script': {'type': 'string', 'description': 'New JS script to execute'},
      'condition': {
        'type': 'string',
        'description':
            'New JS condition expression for alerts (or empty string to clear)',
      },
      'streamUrl': {
        'type': 'string',
        'description':
            'WebSocket URL for push-based monitoring (or empty string to switch back to polling)',
      },
      'display': {
        'type': 'string',
        'enum': [
          'value_card',
          'status_row',
          'mini_chart',
          'text',
          'carousel',
          'watchlist',
        ],
        'description': 'Display widget type',
      },
    },
    'required': ['id'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) => true;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final id = input['id'] as String;
    final monitor = store.get(id);

    if (monitor == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Monitor "$id" not found.',
        isError: true,
      );
    }

    final changes = <String>[];

    if (input.containsKey('enabled')) {
      final enabled = input['enabled'] as bool;
      store.setEnabled(id, enabled);
      changes.add(enabled ? 'enabled' : 'disabled');
    }

    if (input.containsKey('interval')) {
      final interval = _parseInterval(input['interval'] as String);
      if (interval == null) {
        return ToolResult(
          toolUseId: toolUseId,
          content: 'Invalid interval. Use "1m", "5m", "30m", or "1h".',
          isError: true,
        );
      }
      monitor.interval = interval;
      store.save();
      changes.add('interval → ${interval.inMinutes}m');
    }

    if (input.containsKey('name')) {
      monitor.name = input['name'] as String;
      store.save();
      changes.add('name → "${monitor.name}"');
    }

    if (input.containsKey('script')) {
      monitor.script = input['script'] as String;
      store.save();
      changes.add('script updated (${monitor.script.length} chars)');
    }

    if (input.containsKey('condition')) {
      final cond = input['condition'] as String;
      monitor.condition = cond.isEmpty ? null : cond;
      store.save();
      changes.add(cond.isEmpty ? 'condition cleared' : 'condition → "$cond"');
    }

    if (input.containsKey('streamUrl')) {
      final url = input['streamUrl'] as String;
      monitor.streamUrl = url.isEmpty ? null : url;
      store.save();
      changes.add(
        url.isEmpty ? 'streamUrl cleared (polling mode)' : 'streamUrl → "$url"',
      );
    }

    if (input.containsKey('display')) {
      monitor.displayType = input['display'] as String;
      store.save();
      changes.add('display → "${monitor.displayType}"');
    }

    if (changes.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'No changes specified. Provide enabled, interval, or name.',
        isError: true,
      );
    }

    return ToolResult(
      toolUseId: toolUseId,
      content:
          'Monitor "${monitor.name}" (id: $id) updated: ${changes.join(', ')}.\n'
          'Current state: enabled=${monitor.enabled}, interval=${monitor.interval.inMinutes}m, '
          'display=${monitor.displayType}.',
    );
  }

  Duration? _parseInterval(String s) {
    final match = RegExp(r'^(\d+)(m|h)$').firstMatch(s);
    if (match == null) return null;
    final n = int.parse(match.group(1)!);
    return match.group(2) == 'h' ? Duration(hours: n) : Duration(minutes: n);
  }
}
