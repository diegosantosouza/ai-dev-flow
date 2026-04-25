Scaffold a new subagent file in the agents/ directory.

If $ARGUMENTS is provided, use it as the agent name. Otherwise, ask the user.

Steps:
1. Collect the following information (use AskUserQuestion for any not provided):
   - **Name**: kebab-case identifier (e.g. `accessibility-reviewer`)
   - **Description**: one-line starting with an action verb + "Use proactively when <trigger>"
   - **Model**: haiku | sonnet | opus
   - **Effort**: low | medium | high
   - **Memory**: yes (user) or no
   - **Tools**: comma-separated list (default: `Read, Grep, Glob, Bash`)
   - **maxTurns**: integer (suggested: haiku→15, sonnet→20, opus→none)

2. Create `agents/<name>.md` with this structure:
   ```
   ---
   name: <name>
   description: <description>
   tools: <tools>
   model: <model>
   effort: <effort>
   [memory: user]
   [maxTurns: <n>]
   ---

   You are a <role>. Your job is to <one-sentence purpose>.

   ## When invoked

   1. <step 1>
   2. <step 2>
   3. <step 3>

   ## Output format

   - **<key>**: <description>

   ## Rules

   - Do NOT implement anything. Only <role-specific constraint>.
   - Keep output concise — verbose work stays in this context.
   ```

3. Run `bash scripts/validate-agents.sh agents` to confirm the file passes frontmatter validation.

4. Remind the user:
   - Run `./install.sh` to symlink the new agent into `~/.claude/agents/`.
   - Restart Claude Code to pick up the new agent.
