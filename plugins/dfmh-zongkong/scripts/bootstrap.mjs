import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { gunzipSync } from 'node:zlib';

const pluginRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

export async function initializeDfmh({ codexHome = process.env.CODEX_HOME, now = () => new Date().toISOString(), failAt = '' } = {}) {
  if (typeof codexHome !== 'string' || !codexHome.trim()) throw new TypeError('codexHome is required');
  const home = path.resolve(codexHome);
  await mkdir(home, { recursive: true });
  const target = path.join(home, 'dfmh-zongkong');
  const statePath = path.join(target, 'state.json');
  if (await exists(statePath)) {
    const current = JSON.parse(await readFile(statePath, 'utf8'));
    if (current.status !== 'installed') throw new Error('existing DFMH state is not stable');
    if (failAt === 'before-commit') throw new Error('simulated initialization failure');
    return Object.freeze({ status: 'installed', feishu: current.feishu, created: false, runtimeRoot: target });
  }
  if (await exists(target)) throw new Error('existing DFMH directory has no stable state');
  const stage = await mkdtemp(path.join(home, '.dfmh-zongkong-stage-'));
  try {
    const lock = JSON.parse(await readFile(path.join(pluginRoot, 'assets', 'dependency-lock.json'), 'utf8'));
    if (!Array.isArray(lock.packages) || lock.packages.length !== 7) throw new Error('DFMH capability lock is invalid');
    for (const item of lock.packages) await extractCapability({ stage, item });
    const state = {
      schemaVersion: 1,
      status: 'installed',
      version: '1.0.1',
      installedAt: now(),
      installCount: 1,
      capabilityCount: lock.packages.length,
      feishu: 'not_configured',
      telemetry: false,
    };
    const config = {
      schemaVersion: 1,
      administrator: { displayName: '管理员', directChatId: '', allowedGroupIds: [] },
      feishu: { enabled: false, appId: '', secretSource: 'secrets.local.json' },
      knowledge: { enabled: false, preferredSpaces: [] },
      runtime: { maxConcurrentProjects: 2, maxRecoveryAttempts: 3 },
    };
    await writeJson(path.join(stage, 'config.json'), config);
    await writeJson(path.join(stage, 'secrets.local.json'), {});
    await writeJson(path.join(stage, 'state.json'), state);
    if (failAt === 'before-commit') throw new Error('simulated initialization failure');
    await rename(stage, target);
    return Object.freeze({ status: 'installed', feishu: 'not_configured', created: true, runtimeRoot: target });
  } catch (error) {
    await rm(stage, { recursive: true, force: true });
    throw error;
  }
}

async function extractCapability({ stage, item }) {
  if (!/^[a-z]{2}$/u.test(item.alias) || typeof item.archivePath !== 'string' || !/^[a-f0-9]{64}$/u.test(item.archiveSha256)) {
    throw new Error('DFMH capability record is invalid');
  }
  const archivePath = path.resolve(pluginRoot, item.archivePath);
  if (!archivePath.startsWith(pluginRoot + path.sep)) throw new Error('DFMH archive path escapes plugin root');
  const archive = await readFile(archivePath);
  if (sha256(archive) !== item.archiveSha256) throw new Error('DFMH archive hash mismatch');
  const payload = JSON.parse(gunzipSync(archive).toString('utf8'));
  if (payload.alias !== item.alias || payload.repoName !== item.repoName || !Array.isArray(payload.files)) throw new Error('DFMH archive identity mismatch');
  const destinationRoot = path.resolve(stage, 'capabilities', item.alias);
  for (const entry of payload.files) {
    if (typeof entry.path !== 'string' || path.posix.isAbsolute(entry.path) || entry.path.split('/').includes('..')) throw new Error('DFMH archive entry escapes destination');
    const destination = path.resolve(destinationRoot, ...entry.path.split('/'));
    if (!destination.startsWith(destinationRoot + path.sep)) throw new Error('DFMH archive entry escapes destination');
    const data = Buffer.from(String(entry.data ?? ''), 'base64');
    if (data.length !== entry.bytes || sha256(data) !== entry.sha256) throw new Error('DFMH archive entry hash mismatch');
    await mkdir(path.dirname(destination), { recursive: true });
    await writeFile(destination, data);
  }
}

async function writeJson(filePath, value) {
  await writeFile(filePath, JSON.stringify(value, null, 2) + '\n', 'utf8');
}

async function exists(filePath) {
  try { await stat(filePath); return true; }
  catch (error) { if (error?.code === 'ENOENT') return false; throw error; }
}
function sha256(value) { return createHash('sha256').update(value).digest('hex'); }
