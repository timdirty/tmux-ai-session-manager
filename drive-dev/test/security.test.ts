import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { assertCommandAllowed, isSecretPath, redact, resolveInside } from '../src/security.js';
import { SessionStore } from '../src/session.js';

test('redacts common tokens and secrets', () => {
  assert.equal(redact('token=ghp_1234567890123456789012345'), '[REDACTED]');
});

test('blocks secret file names', () => {
  assert.equal(isSecretPath('.env.production'), true);
  assert.equal(isSecretPath('src/index.ts'), false);
});

test('blocks shell operators and destructive commands', () => {
  assert.throws(() => assertCommandAllowed('npm test && rm -rf /'));
  assert.throws(() => assertCommandAllowed('git push origin main'));
  assert.doesNotThrow(() => assertCommandAllowed('npm test'));
});

test('keeps paths in root', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'drive-dev-'));
  await assert.rejects(resolveInside(root, '../escape'));
});

test('isolates session directories', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'drive-dev-'));
  const store = new SessionStore(root);
  await store.init();
  const a = await store.workspace('chat-a');
  const b = await store.workspace('chat-b');
  assert.notEqual(a.dir, b.dir);
  assert.equal(path.dirname(a.dir), root);
});
