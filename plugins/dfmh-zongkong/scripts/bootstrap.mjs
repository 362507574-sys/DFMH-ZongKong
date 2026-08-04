import { mkdir, mkdtemp, readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';

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
    const state = {
      schemaVersion: 1,
      status: 'installed',
      version: '1.0.0',
      installedAt: now(),
      installCount: 1,
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

async function writeJson(filePath, value) {
  await writeFile(filePath, JSON.stringify(value, null, 2) + '\n', 'utf8');
}

async function exists(filePath) {
  try { await stat(filePath); return true; }
  catch (error) { if (error?.code === 'ENOENT') return false; throw error; }
}
