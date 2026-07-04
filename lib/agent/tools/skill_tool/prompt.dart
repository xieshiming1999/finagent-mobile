const description =
    'Load, create, update, or delete skills. Skills are reusable instruction files.';

const prompt = '''Load, create, update, or delete named skills.

## Loading a skill

Use the skill name to load it:
  Skill(skill: "trading")
  Skill(skill: "analysis", args: "AAPL")

- Skills are .md files in memory/skills/ (priority) and bundle/skills/.
- Optional args are substituted for \$ARGUMENTS in skill content.
- When a skill matches the user's request, invoke it BEFORE generating any other response.
- Available skills are listed in the system prompt under "Available Skills".

## Creating a skill

Use skill="create" with the full skill.md content:
  Skill(skill: "create", content: "---\\nname: my-skill\\ndescription: ...\\n---\\n\\n# Steps\\n1. ...")

### When to create a skill

Create a skill when ANY of these apply:
- The task required 5+ tool calls and succeeded
- You overcame errors through trial and correction
- The user corrected your approach and the corrected version worked
- You discovered a non-trivial multi-step workflow
- The user explicitly asks you to remember how to do something

### When NOT to create a skill

- Simple one-step tasks (just reading a file, answering a question)
- Tasks too specific to be reusable
- The user explicitly said "don't save this"

### Skill content guidelines

- One task per skill — don't bundle unrelated procedures
- Include the "why" — explain reasoning behind each step
- Include error handling — what can go wrong and how to recover
- Be specific — include actual paths, field names, parameter values
- Keep it concise — focus on the procedure, not background knowledge

### Required frontmatter format

---
name: skill-name           # Required. Lowercase, hyphens, max 64 chars
description: What it does  # Required. One line
when_to_use: When to apply # Optional. Trigger conditions
---

## Updating a skill

Use skill="update" with the skill name in args and new content:
  Skill(skill: "update", args: "my-skill", content: "---\\nname: ...")

- Can only update memory/ skills. For bundle/ skills, creates a memory override.

## Deleting a skill

Use skill="delete" with the skill name in args:
  Skill(skill: "delete", args: "my-skill")

- Can only delete memory/ skills. Bundle skills cannot be deleted.''';
