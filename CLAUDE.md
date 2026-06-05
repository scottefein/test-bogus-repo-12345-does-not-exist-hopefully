# sef-industries-team

Centralized source of truth for Claude Code configurations (agents, skills, MCP, etc.) shared across all repos.

## Repo Structure

- `src/agents/*.md` — Canonical agent content (role-specific, no memory boilerplate)
- `src/templates/agent-memory.md` — Shared memory boilerplate template (`{{AGENT_NAME}}` placeholder)
- `repos/*.yml` — Per-repo sync configs (one YAML per onboarded repo)
- `bin/build` — Compile `src/` -> `.claude/agents/` for this repo
- `bin/sync` — Push compiled configs to target repos via PRs
- `bin/onboard` — Register a repo for config sync
- `.claude/agents/*.md` — Compiled output (built from `src/` + template)
- `.claude/agent-memory/<agent>/` — Runtime memory dirs (contents gitignored)

## Workflow

1. Edit agent content in `src/agents/<name>.md`
2. Run `bin/build` to compile locally
3. Commit changes
4. Run `bin/sync <owner/repo>` or `bin/sync --all` to push to target repos

## Adding a New Agent

1. Create `src/agents/<name>.md` with frontmatter and role content
2. Run `bin/build` — this compiles the agent and creates the memory directory
3. Commit and sync

## Onboarding a Repo

```bash
bin/onboard owner/repo-name       # Creates config, validates repo exists
bin/onboard owner/repo-name --sync # Creates config and runs initial sync
```

## Key Rules

- Never edit `.claude/agents/*.md` directly — they are compiled output from `bin/build`
- Agent source files must NOT include the memory boilerplate — it's appended from the template
- The `{{AGENT_NAME}}` placeholder in the template gets replaced with the filename (without .md)
- Template-created repos auto-clean tooling via `.github/workflows/template-cleanup.yml`
