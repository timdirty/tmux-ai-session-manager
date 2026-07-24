# drive_dev MCP harness

`drive_dev` turns an MCP client such as ChatGPT into an operator for an isolated development workspace. Each HTTP MCP connection receives its own working directory, so multiple conversations can develop different projects at the same time without sharing files.

## Included tools

- Session: `session_info`
- Files: `list_files`, `read_file`, `write_file`
- Editing: `apply_patch`
- Search: `search_text`
- Package workflow: `run_command`
- Diagnostics: `diagnostics`
- Delivery: `export_workspace`

Every tool call is written to `.drive-dev/audit.jsonl`. Secret-like files are blocked, common credentials are redacted, paths are confined to the session root, symlink escapes are rejected, and commands use an explicit allowlist.

## Local stdio setup

```bash
cd drive-dev
npm install
npm run build
```

MCP client configuration:

```json
{
  "mcpServers": {
    "drive_dev": {
      "command": "node",
      "args": ["/absolute/path/to/drive-dev/dist/src/index.js"],
      "env": {
        "DRIVE_DEV_ROOT": "/absolute/path/to/workspaces",
        "DRIVE_DEV_SESSION": "chatgpt-local"
      }
    }
  }
}
```

## Remote HTTP setup

```bash
cp .env.example .env
# Set a strong DRIVE_DEV_TOKEN and review the bind address.
docker compose up -d --build
curl http://127.0.0.1:3000/health
```

MCP endpoint: `http://YOUR_HOST:3000/mcp`

Send either `Authorization: Bearer <DRIVE_DEV_TOKEN>` or `X-Drive-Dev-Token: <DRIVE_DEV_TOKEN>`. Put TLS and access control in front of the service before exposing it to the internet. Tailscale, Cloudflare Access, or an authenticated reverse proxy are safer than opening port 3000 publicly.

## Recommended workflow

1. Call `session_info` and inspect `AGENTS.md` / `SKILL.md`.
2. Create or import project files.
3. Use `apply_patch` for changes.
4. Run `npm test`, `npm run build`, `pytest`, or another allowlisted check.
5. Run `diagnostics` and inspect the preview separately.
6. Call `export_workspace` for delivery.

## Multi-agent extension

Keep orchestration outside this server initially. Let ChatGPT divide work, then launch Codex/GPT or Gemini workers in separate sessions or worktrees. Merge only after independent tests and review. This prevents two agents from editing the same working tree and turns the workflow into a small assembly line rather than a keyboard food fight.

## Current deliberate limits

- No arbitrary shell, pipes, redirects, sudo, destructive Git, or direct deployment.
- No binary file editing.
- No built-in cloud preview provider. Run a project preview command behind a private reverse proxy, or add a provider-specific adapter after the base harness is stable.
- Authentication is a shared bearer token, not OAuth. Use an access proxy for production.
