import 'dart:convert';

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Creates a team (agent swarm) for collaborative multi-agent tasks.
///
/// Reference: claude-code-best TeamCreateTool (simplified — in-memory only,
/// no file-based team config, no tmux/iTerm2 panes).
class TeamCreateTool extends Tool {
  @override
  String get name => 'TeamCreate';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'team_name': {
        'type': 'string',
        'description': 'Unique name for the team (e.g., "icbc_analysis")',
      },
      'description': {'type': 'string', 'description': 'Purpose of the team'},
    },
    'required': ['team_name'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<String?> validateInput(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final teamName = input['team_name'] as String?;
    if (teamName == null || teamName.trim().isEmpty) {
      return 'team_name is required.';
    }
    if (context.teamRegistry.hasTeam(teamName)) {
      return 'Team "$teamName" already exists. Use a different name or delete it first.';
    }
    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final teamName = (input['team_name'] as String).trim();
    final description = input['description'] as String?;

    final team = context.teamRegistry.createTeam(
      name: teamName,
      description: description,
      leadAgentId: 'main',
    );

    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode({
        'ok': true,
        'team_name': team.name,
        'description': team.description,
        'lead': team.leadAgentId,
        'message':
            'Team "$teamName" created. '
            'Now spawn members using Agent tool with team_name: "$teamName". '
            'Members can communicate via SendMessage.',
      }),
    );
  }
}
