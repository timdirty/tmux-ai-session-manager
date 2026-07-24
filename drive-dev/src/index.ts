#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import fg from 'fast-glob';
import { z } from 'zod';
import type { Request, Response } from 'express';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { createMcpExpressApp } from '@modelcontextprotocol/sdk/server/express.js';
import { isInitializeRequest } from '@modelcontextprotocol/sdk/types.js';
import { SessionStore } from './session.js';
import { assertCommandAllowed, isSecretPath, redact, resolveInside } from './security.js';
import { audit } from './audit.js';

const ROOT = path.resolve(process.env.DRIVE_DEV_ROOT || path.join(process.cwd(), '.drive-dev-sessions'));
const MAX_OUTPUT = Number(process.env.DRIVE_DEV_MAX_OUTPUT || 120_000);
const MAX_FILE = Number(process.env.DRIVE_DEV_MAX_FILE || 2_000_000);
const store = new SessionStore(ROOT);
await store.init();

type Context = { sessionId: string; workspace: string };
const text = (value: unknown) => ({ content: [{ type: 'text' as const, text: typeof value === 'string' ? value : JSON.stringify(value, null, 2) }] });
const clip = (value: string) => redact(value.length > MAX_OUTPUT ? `${value.slice(0, MAX_OUTPUT)}\n...[output clipped]` : value);

function createServer(ctx: Context): McpServer {
  const server = new McpServer({ name: 'drive_dev', version: '0.1.0' });

  server.registerTool('session_info', {
    description: 'Show the isolated working directory for this MCP connection.',
    inputSchema: {}
  }, async () => text({ sessionId: ctx.sessionId, workingDirectory: ctx.workspace, allowedRoot: ROOT }));

  server.registerTool('list_files', {
    description: 'List files inside the current isolated workspace.',
    inputSchema: { path: z.string().default('.'), depth: z.number().int().min(1).max(8).default(4) }
  }, async ({ path: requested, depth }) => {
    const base = await resolveInside(ctx.workspace, requested);
    const files = await fg(`${base.replaceAll('\\', '/')}/**/*`, {
      onlyFiles: false,
      dot: true,
      deep: depth,
      followSymbolicLinks: false,
      ignore: ['**/.git/**', '**/node_modules/**', '**/.drive-dev/**']
    });
    const result = files.slice(0, 1000).map((file) => path.relative(ctx.workspace, file));
    await audit(ctx.workspace, { tool: 'list_files', path: requested, count: result.length });
    return text(result);
  });

  server.registerTool('read_file', {
    description: 'Read a UTF-8 text file. Secret-like files are blocked by default.',
    inputSchema: {
      path: z.string().min(1),
      startLine: z.number().int().min(1).optional(),
      endLine: z.number().int().min(1).optional()
    }
  }, async ({ path: requested, startLine, endLine }) => {
    if (isSecretPath(requested)) throw new Error('Reading secret-like files is blocked.');
    const target = await resolveInside(ctx.workspace, requested);
    const stat = await fs.stat(target);
    if (stat.size > MAX_FILE) throw new Error(`File exceeds ${MAX_FILE} bytes.`);
    const lines = (await fs.readFile(target, 'utf8')).split('\n');
    const sliced = lines.slice((startLine || 1) - 1, endLine || lines.length).join('\n');
    await audit(ctx.workspace, { tool: 'read_file', path: requested, startLine, endLine });
    return text(clip(sliced));
  });

  server.registerTool('write_file', {
    description: 'Create or replace a UTF-8 text file inside the workspace.',
    inputSchema: {
      path: z.string().min(1),
      content: z.string(),
      createDirectories: z.boolean().default(true)
    }
  }, async ({ path: requested, content, createDirectories }) => {
    if (isSecretPath(requested)) throw new Error('Writing secret-like files is blocked.');
    if (Buffer.byteLength(content) > MAX_FILE) throw new Error(`Content exceeds ${MAX_FILE} bytes.`);
    const target = await resolveInside(ctx.workspace, requested);
    if (createDirectories) await fs.mkdir(path.dirname(target), { recursive: true });
    await fs.writeFile(target, content, 'utf8');
    await audit(ctx.workspace, { tool: 'write_file', path: requested, bytes: Buffer.byteLength(content) });
    return text({ ok: true, path: requested, bytes: Buffer.byteLength(content) });
  });

  server.registerTool('apply_patch', {
    description: 'Apply an exact text replacement. Fails if oldText is absent or non-unique.',
    inputSchema: { path: z.string().min(1), oldText: z.string().min(1), newText: z.string() }
  }, async ({ path: requested, oldText, newText }) => {
    if (isSecretPath(requested)) throw new Error('Patching secret-like files is blocked.');
    const target = await resolveInside(ctx.workspace, requested);
    const current = await fs.readFile(target, 'utf8');
    const first = current.indexOf(oldText);
    if (first < 0) throw new Error('oldText was not found.');
    if (current.indexOf(oldText, first + oldText.length) >= 0) throw new Error('oldText appears more than once; provide a larger unique block.');
    const updated = current.slice(0, first) + newText + current.slice(first + oldText.length);
    await fs.writeFile(target, updated, 'utf8');
    await audit(ctx.workspace, { tool: 'apply_patch', path: requested });
    return text({ ok: true, path: requested });
  });

  server.registerTool('search_text', {
    description: 'Search text recursively in project files.',
    inputSchema: {
      query: z.string().min(1),
      glob: z.string().default('**/*'),
      maxResults: z.number().int().min(1).max(500).default(100)
    }
  }, async ({ query, glob, maxResults }) => {
    const files = await fg(glob, {
      cwd: ctx.workspace,
      onlyFiles: true,
      dot: true,
      followSymbolicLinks: false,
      ignore: ['.git/**', 'node_modules/**', '.drive-dev/**']
    });
    const matches: Array<{ path: string; line: number; text: string }> = [];
    for (const relative of files) {
      if (isSecretPath(relative)) continue;
      const target = await resolveInside(ctx.workspace, relative);
      const stat = await fs.stat(target);
      if (stat.size > MAX_FILE) continue;
      let content: string;
      try { content = await fs.readFile(target, 'utf8'); } catch { continue; }
      for (const [index, line] of content.split('\n').entries()) {
        if (line.toLowerCase().includes(query.toLowerCase())) matches.push({ path: relative, line: index + 1, text: clip(line) });
        if (matches.length >= maxResults) break;
      }
      if (matches.length >= maxResults) break;
    }
    await audit(ctx.workspace, { tool: 'search_text', query, count: matches.length });
    return text(matches);
  });

  server.registerTool('run_command', {
    description: 'Run one allowlisted development command. Shell operators, sudo, destructive Git, and piped installers are blocked.',
    inputSchema: {
      command: z.string().min(1),
      timeoutMs: z.number().int().min(1000).max(300000).default(120000)
    }
  }, async ({ command, timeoutMs }) => {
    assertCommandAllowed(command);
    const [program, ...args] = command.trim().split(/\s+/);
    const started = Date.now();
    const result = await new Promise<{ code: number | null; stdout: string; stderr: string; timedOut: boolean }>((resolve, reject) => {
      const child = spawn(program!, args, {
        cwd: ctx.workspace,
        env: { ...process.env, CI: '1', NO_COLOR: '1' },
        shell: false
      });
      let stdout = '';
      let stderr = '';
      let timedOut = false;
      child.stdout.on('data', (chunk) => { if (stdout.length < MAX_OUTPUT) stdout += chunk.toString(); });
      child.stderr.on('data', (chunk) => { if (stderr.length < MAX_OUTPUT) stderr += chunk.toString(); });
      child.on('error', reject);
      const timer = setTimeout(() => { timedOut = true; child.kill('SIGTERM'); }, timeoutMs);
      child.on('close', (code) => {
        clearTimeout(timer);
        resolve({ code, stdout: clip(stdout), stderr: clip(stderr), timedOut });
      });
    });
    const durationMs = Date.now() - started;
    await audit(ctx.workspace, { tool: 'run_command', command, code: result.code, timedOut: result.timedOut, durationMs });
    return text({ ...result, durationMs });
  });

  server.registerTool('diagnostics', {
    description: 'Inspect workspace health, package scripts, AGENTS.md, and SKILL files.',
    inputSchema: {}
  }, async () => {
    const files = await fg(['AGENTS.md', '**/SKILL.md', 'package.json', 'pyproject.toml', 'Cargo.toml', 'go.mod'], {
      cwd: ctx.workspace,
      onlyFiles: true,
      dot: true,
      ignore: ['node_modules/**', '.git/**']
    });
    let packageScripts: Record<string, string> | undefined;
    try {
      packageScripts = JSON.parse(await fs.readFile(path.join(ctx.workspace, 'package.json'), 'utf8')).scripts;
    } catch {}
    await audit(ctx.workspace, { tool: 'diagnostics', discovered: files.length });
    return text({ sessionId: ctx.sessionId, workspace: ctx.workspace, discovered: files, packageScripts });
  });

  server.registerTool('export_workspace', {
    description: 'Create a tar.gz archive excluding Git metadata, dependencies, and audit logs.',
    inputSchema: { outputName: z.string().regex(/^[a-zA-Z0-9._-]+$/).default('workspace.tar.gz') }
  }, async ({ outputName }) => {
    const output = await resolveInside(ctx.workspace, outputName);
    await new Promise<void>((resolve, reject) => {
      const child = spawn('tar', ['--exclude=.git', '--exclude=node_modules', '--exclude=.drive-dev', '--exclude', outputName, '-czf', output, '.'], { cwd: ctx.workspace });
      let stderr = '';
      child.stderr.on('data', (chunk) => stderr += chunk.toString());
      child.on('error', reject);
      child.on('close', (code) => code === 0 ? resolve() : reject(new Error(clip(stderr))));
    });
    await audit(ctx.workspace, { tool: 'export_workspace', outputName });
    return text({ ok: true, archive: output });
  });

  return server;
}

async function startStdio(): Promise<void> {
  const session = await store.workspace(process.env.DRIVE_DEV_SESSION || 'stdio-default');
  const server = createServer({ sessionId: session.id, workspace: session.dir });
  await server.connect(new StdioServerTransport());
}

async function startHttp(): Promise<void> {
  const host = process.env.HOST || '127.0.0.1';
  const port = Number(process.env.PORT || 3000);
  const token = process.env.DRIVE_DEV_TOKEN;
  const allowedHosts = process.env.DRIVE_DEV_ALLOWED_HOSTS?.split(',').map((item) => item.trim()).filter(Boolean);
  const app = createMcpExpressApp({ host, allowedHosts });
  const transports: Record<string, StreamableHTTPServerTransport> = {};

  app.get('/health', (_req, res) => res.json({ ok: true, sessions: Object.keys(transports).length }));
  app.use('/mcp', (req, res, next) => {
    if (!token) return next();
    const supplied = req.headers.authorization?.replace(/^Bearer\s+/i, '') || req.headers['x-drive-dev-token'];
    if (supplied !== token) return res.status(401).json({ error: 'Unauthorized' });
    next();
  });

  const post = async (req: Request, res: Response) => {
    try {
      const id = req.headers['mcp-session-id'] as string | undefined;
      let transport = id ? transports[id] : undefined;
      if (!transport && !id && isInitializeRequest(req.body)) {
        const session = await store.workspace(randomUUID());
        transport = new StreamableHTTPServerTransport({
          sessionIdGenerator: () => session.id,
          onsessioninitialized: (sessionId) => { transports[sessionId] = transport!; }
        });
        transport.onclose = () => { if (transport?.sessionId) delete transports[transport.sessionId]; };
        await createServer({ sessionId: session.id, workspace: session.dir }).connect(transport);
      }
      if (!transport) return res.status(400).json({ jsonrpc: '2.0', error: { code: -32000, message: 'Invalid MCP session' }, id: null });
      await transport.handleRequest(req, res, req.body);
    } catch (error) {
      if (!res.headersSent) res.status(500).json({ error: redact(String(error)) });
    }
  };

  const existing = async (req: Request, res: Response) => {
    const id = req.headers['mcp-session-id'] as string | undefined;
    const transport = id ? transports[id] : undefined;
    if (!transport) return res.status(400).send('Invalid or missing MCP session id');
    await transport.handleRequest(req, res);
  };

  app.post('/mcp', post);
  app.get('/mcp', existing);
  app.delete('/mcp', existing);
  app.listen(port, host, () => console.error(`drive_dev MCP listening at http://${host}:${port}/mcp`));
}

const mode = process.argv.includes('--http') || process.env.DRIVE_DEV_TRANSPORT === 'http' ? 'http' : 'stdio';
await (mode === 'http' ? startHttp() : startStdio());
