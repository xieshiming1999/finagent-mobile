import 'dart:convert';

import '../../agent.dart';
import '../../background_task.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Deletes a team and stops all its running members.
///
/// Reference: claude-code-best TeamDeleteTool (simplified).
class TeamDeleteTool extends Tool {
  final Agent parentAgent;

  TeamDeleteTool({required this.parentAgent});

  @override
  String get name => 'TeamDelete';

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
        'description': 'Name of the team to delete',
      },
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
    if (!context.teamRegistry.hasTeam(teamName)) {
      return 'Team "$teamName" not found.';
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
    final team = context.teamRegistry.getTeam(teamName);
    if (team == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Team "$teamName" not found.',
        isError: true,
      );
    }

    // Stop all running members
    int stopped = 0;
    for (final member in team.memberList) {
      if (member.status == 'running') {
        parentAgent.cancelBackgroundAgent(member.agentId);
        context.taskRegistry.updateStatus(
          member.agentId,
          BackgroundTaskStatus.killed,
          error: 'Team deleted',
        );
        stopped++;
      }
    }

    // Delete team
    context.teamRegistry.deleteTeam(teamName);

    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode({
        'ok': true,
        'team_name': teamName,
        'members_stopped': stopped,
        'message':
            'Team "$teamName" deleted. $stopped running members stopped.',
      }),
    );
  }
}
