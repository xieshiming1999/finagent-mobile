const description = 'Create a team of agents to collaborate on a complex task.';

const prompt = '''Create a team (agent swarm) for collaborative analysis.

Usage:
- Create a team when a task benefits from multiple specialized agents working together.
- After creating the team, spawn team members using Agent tool with the team_name parameter.
- Team members communicate via SendMessage and coordinate via TaskList.

Example workflow:
1. TeamCreate(team_name: "icbc_analysis", description: "全面分析工商银行")
2. Agent(name: "技术分析师", team_name: "icbc_analysis", prompt: "分析K线...", run_in_background: true)
3. Agent(name: "基本面研究员", team_name: "icbc_analysis", prompt: "分析财报...", run_in_background: true)
4. Wait for members to complete, then summarize results.

Guidelines:
- One team per analysis task. Don't create multiple teams for the same topic.
- Team members should SendMessage(to: "parent") to report their findings.
- The team leader (you) coordinates and produces the final summary.
''';
