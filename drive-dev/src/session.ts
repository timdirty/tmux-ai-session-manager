import fs from 'node:fs/promises';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { resolveInside } from './security.js';

export class SessionStore {
  constructor(public readonly root: string) {}

  async init(): Promise<void> {
    await fs.mkdir(this.root, { recursive: true });
  }

  normalize(id?: string): string {
    const value = (id || randomUUID()).replace(/[^a-zA-Z0-9._-]/g, '-').slice(0, 80);
    if (!value || value === '.' || value === '..') throw new Error('Invalid session id.');
    return value;
  }

  async workspace(id?: string): Promise<{ id: string; dir: string }> {
    const safeId = this.normalize(id);
    const dir = await resolveInside(this.root, safeId);
    await fs.mkdir(dir, { recursive: true });
    await fs.mkdir(path.join(dir, '.drive-dev'), { recursive: true });
    return { id: safeId, dir };
  }

  async list(): Promise<string[]> {
    const entries = await fs.readdir(this.root, { withFileTypes: true });
    return entries.filter((entry) => entry.isDirectory()).map((entry) => entry.name).sort();
  }
}
