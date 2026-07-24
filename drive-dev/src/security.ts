import path from 'node:path';
import fs from 'node:fs/promises';

const SECRET_FILE = /(^|\/)(\.env(?:\..*)?|\.npmrc|\.pypirc|id_(rsa|ed25519)|credentials(?:\.json)?|secrets?\.(json|ya?ml))$/i;
const SECRET_VALUE = /(sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9_]{20,}|AIza[0-9A-Za-z_-]{20,}|-----BEGIN [A-Z ]+PRIVATE KEY-----|(?:api[_-]?key|token|secret|password)\s*[:=]\s*[^\s,;]+)/gi;

export function redact(text: string): string {
  return text.replace(SECRET_VALUE, '[REDACTED]');
}

export function isSecretPath(relativePath: string): boolean {
  return SECRET_FILE.test(relativePath.replaceAll('\\', '/'));
}

export async function resolveInside(root: string, requested = '.'): Promise<string> {
  const rootReal = await fs.realpath(root);
  const candidate = path.resolve(rootReal, requested);
  const relative = path.relative(rootReal, candidate);
  if (relative.startsWith('..') || path.isAbsolute(relative)) throw new Error('Path escapes the allowed workspace root.');

  try {
    const real = await fs.realpath(candidate);
    const realRelative = path.relative(rootReal, real);
    if (realRelative.startsWith('..') || path.isAbsolute(realRelative)) throw new Error('Symlink escapes the allowed workspace root.');
    return real;
  } catch (error: any) {
    if (error?.code === 'ENOENT') return candidate;
    throw error;
  }
}

const ALLOWED_COMMANDS = new Set([
  'node', 'npm', 'npx', 'pnpm', 'yarn', 'bun', 'deno',
  'python', 'python3', 'pip', 'pip3', 'pytest',
  'git', 'tsc', 'tsx', 'vite', 'vitest', 'jest',
  'cargo', 'rustc', 'go', 'java', 'javac', 'mvn', 'gradle',
  'ls', 'pwd', 'cat', 'head', 'tail', 'wc', 'find', 'grep', 'rg', 'sed', 'awk',
  'mkdir', 'cp', 'mv', 'touch', 'tar', 'zip', 'unzip'
]);

const BLOCKED_PATTERNS = [
  /\brm\s+-[^\n]*r[^\n]*f/i,
  /\bsudo\b/i,
  /\b(chmod|chown)\b[^\n]*-R/i,
  /\bgit\s+(push|reset\s+--hard|clean\s+-[a-z]*f)/i,
  /\b(curl|wget)\b[^\n]*\|\s*(sh|bash|zsh)/i,
  /(^|\s)(\/dev\/|\/etc\/|\/var\/|~\/\.ssh)/i
];

export function assertCommandAllowed(command: string): void {
  const trimmed = command.trim();
  if (!trimmed) throw new Error('Command is empty.');
  if (/[;&|`$<>]/.test(trimmed)) throw new Error('Shell operators and redirection are disabled. Run one command at a time.');
  if (BLOCKED_PATTERNS.some((pattern) => pattern.test(trimmed))) throw new Error('Command rejected by the safety policy.');
  const executable = trimmed.split(/\s+/)[0]!.replace(/^.*\//, '');
  if (!ALLOWED_COMMANDS.has(executable)) throw new Error(`Command '${executable}' is not in the allowlist.`);
}
