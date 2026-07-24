import fs from 'node:fs/promises';
import path from 'node:path';
import { redact } from './security.js';

export async function audit(workspace: string, event: Record<string, unknown>): Promise<void> {
  const line = JSON.stringify({ at: new Date().toISOString(), ...event }, (_key, value) => typeof value === 'string' ? redact(value) : value) + '\n';
  await fs.appendFile(path.join(workspace, '.drive-dev', 'audit.jsonl'), line, 'utf8');
}
