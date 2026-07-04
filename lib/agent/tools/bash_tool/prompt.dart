/// Short description for LLM function calling.
const description =
    'Executes a shell command on desktop Flutter targets and returns output.';

/// Full instructions for the LLM.
/// Reference: claude-code-best/src/tools/BashTool/prompt.ts getSimplePrompt()
const prompt = '''Executes a given shell command and returns its output.

This tool is available only on desktop Flutter targets where the runtime can
start local processes, currently macOS and Linux. It is not included in the
agent tool list on Android or iOS. If this tool is unavailable, use the
dedicated file, data, UI, or workflow tools instead of assuming shell access.

The working directory persists between commands, but shell state does not. The shell environment is initialized from the user's profile (bash or zsh).

IMPORTANT: Avoid using this tool to run `find`, `grep`, `cat`, `head`, `tail`, `sed`, `awk`, or `echo` commands, unless explicitly instructed or after you have verified that a dedicated tool cannot accomplish your task. Instead, use the appropriate dedicated tool as this will provide a much better experience for the user:

 - File search: Use Glob (NOT find or ls)
 - Content search: Use Grep (NOT grep or rg)
 - Read files: Use Read (NOT cat/head/tail)
 - Edit files: Use Edit (NOT sed/awk)
 - Write files: Use Write (NOT echo >/cat <<EOF)
 - Communication: Output text directly (NOT echo/printf)
While the Bash tool can do similar things, it's better to use the built-in tools as they provide a better user experience and make it easier to review tool calls and give permission.

# Instructions
 - If your command will create new directories or files, first use this tool to run `ls` to verify the parent directory exists and is the correct location.
 - Always quote file paths that contain spaces with double quotes in your command (e.g., cd "path with spaces/file.txt")
 - Try to maintain your current working directory throughout the session by using absolute paths and avoiding usage of `cd`. You may use `cd` if the User explicitly requests it.
 - You may specify an optional timeout in milliseconds (up to 600000ms / 10 minutes). By default, your command will timeout after 120000ms (2 minutes).
 - You can use the `run_in_background` parameter to run the command in the background. You will be notified when it completes.
 - When issuing multiple commands:
   - If the commands are independent and can run in parallel, make multiple Bash tool calls in a single message.
   - If the commands depend on each other and must run sequentially, use a single Bash call with '&&' to chain them together.
   - Use ';' only when you need to run commands sequentially but don't care if earlier commands fail.
   - DO NOT use newlines to separate commands (newlines are ok in quoted strings).
 - For git commands:
   - Prefer to create a new commit rather than amending an existing commit.
   - Before running destructive operations (e.g., git reset --hard, git push --force, git checkout --), consider whether there is a safer alternative.
   - Never skip hooks (--no-verify) or bypass signing unless the user explicitly asks for it.
 - Avoid unnecessary `sleep` commands:
   - Do not sleep between commands that can run immediately — just run them.
   - If your command is long running, use `run_in_background`. No sleep needed.
   - Do not retry failing commands in a sleep loop — diagnose the root cause.
   - If you must sleep, keep the duration short (1-5 seconds) to avoid blocking the user.

# Destructive Operations
Be careful with destructive commands. The following will show extra warnings:
 - `git reset --hard`, `git checkout .`, `git clean -f` — may discard changes
 - `git push --force` / `git push -f` — may overwrite remote history
 - `rm -rf`, `rm -r` — may recursively remove files
 - `DROP TABLE`, `DELETE FROM` — may delete database data
Before running destructive operations, consider whether there is a safer alternative.''';
