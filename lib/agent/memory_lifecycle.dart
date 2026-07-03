enum MemoryLifecycleKind { working, session, durable, procedural }

class MemoryLifecycleSpec {
  final MemoryLifecycleKind kind;
  final String label;
  final String purpose;
  final String retention;
  final String writeTarget;
  final String promotionRule;

  const MemoryLifecycleSpec({
    required this.kind,
    required this.label,
    required this.purpose,
    required this.retention,
    required this.writeTarget,
    required this.promotionRule,
  });
}

const memoryLifecycleSpecs = <MemoryLifecycleKind, MemoryLifecycleSpec>{
  MemoryLifecycleKind.working: MemoryLifecycleSpec(
    kind: MemoryLifecycleKind.working,
    label: 'working',
    purpose: 'Current task state, assumptions, blockers, and next actions.',
    retention: 'Current turn or active work packet.',
    writeTarget:
        'Goal/work-packet artifacts, task state, or current session notes.',
    promotionRule:
        'Promote only if the state remains useful after task completion.',
  ),
  MemoryLifecycleKind.session: MemoryLifecycleSpec(
    kind: MemoryLifecycleKind.session,
    label: 'session',
    purpose: 'Session-level summary and recovery state used by compaction.',
    retention: 'Current working session.',
    writeTarget: 'sessions/<session-id>/session-memory.md',
    promotionRule:
        'Review before promoting stable decisions to durable memory or repeated workflow to a skill.',
  ),
  MemoryLifecycleKind.durable: MemoryLifecycleSpec(
    kind: MemoryLifecycleKind.durable,
    label: 'durable',
    purpose:
        'Stable user preferences, project facts, decisions, and references.',
    retention: 'Cross-session until explicitly revised or removed.',
    writeTarget: 'memory/*.md plus memory/MEMORY.md index pointer.',
    promotionRule:
        'Save only when evidence is stable and useful beyond the current task.',
  ),
  MemoryLifecycleKind.procedural: MemoryLifecycleSpec(
    kind: MemoryLifecycleKind.procedural,
    label: 'procedural',
    purpose:
        'Reusable process knowledge that tells the agent how to do a task.',
    retention: 'Cross-session after review.',
    writeTarget: 'memory/skills/<skill>/skill.md with governance.json.',
    promotionRule:
        'Prefer a skill over durable memory when the content is a repeatable workflow.',
  ),
};

MemoryLifecycleSpec memoryLifecycleSpec(MemoryLifecycleKind kind) =>
    memoryLifecycleSpecs[kind]!;

String memoryLifecycleFrontmatter(MemoryLifecycleKind kind) {
  final spec = memoryLifecycleSpec(kind);
  return '''---
lifecycle: ${spec.label}
purpose: ${spec.purpose}
retention: ${spec.retention}
write_target: ${spec.writeTarget}
promotion_rule: ${spec.promotionRule}
---
''';
}

const memoryLifecyclePromptGuidance = '''# Memory Lifecycle
Classify memory before writing it:
- working: current task state, assumptions, blockers, and next actions. Keep it in the active session, goal work packet, or task artifact.
- session: session-level summary and recovery state for compaction. Keep it under sessions/<session-id>/session-memory.md.
- durable: stable user preferences, project facts, decisions, and references. Save under memory/*.md and index it from memory/MEMORY.md.
- procedural: repeatable workflow knowledge. Promote it to memory/skills/<skill>/skill.md with governance instead of storing it as ordinary memory.

Do not promote current market observations, one-off debugging state, or incomplete hypotheses into durable memory or skills without explicit evidence. When writing durable memory files, include frontmatter with lifecycle: durable. When creating procedural memory, use a skill and preserve rollback/provenance governance.''';
