# AGENTS.md

This repo is worked on by multiple coding agents (Claude Code, Codex, Gemini) via NTM.

## Coordination (Agent Mail)
- Use Agent Mail MCP tools for coordination and review requests.
- Before editing files, reserve them (exclusive) via Agent Mail.
- When you finish, release/let TTL expire and message dependents.

## Beads workflow
- Tasks are tracked in Beads (bd). Always:
  1) Triage what is ready with BV
  2) Claim a bead (set status in_progress)
  3) Implement + tests
  4) Close the bead and notify via Agent Mail

## Guardrails
- Run UBS before committing.
- Prefer small, atomic commits unless a refactor demands otherwise.
