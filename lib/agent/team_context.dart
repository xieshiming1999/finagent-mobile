/// Team context and state management for agent swarms.
/// Pure Dart — no Flutter imports.
///
/// Reference: claude-code-best TeamFile + AppState.teamContext
library;

/// A single team member.
class TeamMember {
  final String agentId; // = background task ID
  final String name;
  final String? role;
  final String? prompt;
  final DateTime joinedAt;
  String status; // 'running', 'idle', 'completed', 'failed'
  String? result;

  TeamMember({
    required this.agentId,
    required this.name,
    this.role,
    this.prompt,
    DateTime? joinedAt,
    this.status = 'running',
    this.result,
  }) : joinedAt = joinedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'agentId': agentId,
    'name': name,
    if (role != null) 'role': role,
    'status': status,
    if (result != null) 'result': result,
  };
}

/// Represents an active team.
class TeamContext {
  final String name;
  final String? description;
  final String leadAgentId;
  final String? tileId; // associated team tile
  final DateTime createdAt;
  final Map<String, TeamMember> members = {};

  TeamContext({
    required this.name,
    this.description,
    required this.leadAgentId,
    this.tileId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Add a member to the team.
  void addMember(TeamMember member) {
    members[member.agentId] = member;
  }

  /// Remove a member.
  void removeMember(String agentId) {
    members.remove(agentId);
  }

  /// Update a member's status.
  void updateMemberStatus(String agentId, String status, {String? result}) {
    final member = members[agentId];
    if (member == null) return;
    member.status = status;
    if (result != null) member.result = result;
  }

  /// Get all members as a list for display.
  List<TeamMember> get memberList => members.values.toList();

  /// Count of members by status.
  int get runningCount =>
      members.values.where((m) => m.status == 'running').length;
  int get completedCount =>
      members.values.where((m) => m.status == 'completed').length;
  int get totalCount => members.length;

  /// Summary for tile display.
  Map<String, dynamic> toTileData() => {
    'teamName': name,
    'description': description ?? '',
    'members': members.values.map((m) => m.toJson()).toList(),
    'summary': '$completedCount/$totalCount completed',
  };
}

/// Registry of active teams. Stored in ToolContext.
class TeamRegistry {
  final Map<String, TeamContext> _teams = {};

  TeamContext? getTeam(String name) => _teams[name];

  TeamContext createTeam({
    required String name,
    String? description,
    required String leadAgentId,
    String? tileId,
  }) {
    final team = TeamContext(
      name: name,
      description: description,
      leadAgentId: leadAgentId,
      tileId: tileId,
    );
    _teams[name] = team;
    return team;
  }

  void deleteTeam(String name) {
    _teams.remove(name);
  }

  List<TeamContext> get teams => _teams.values.toList();

  bool hasTeam(String name) => _teams.containsKey(name);
}
