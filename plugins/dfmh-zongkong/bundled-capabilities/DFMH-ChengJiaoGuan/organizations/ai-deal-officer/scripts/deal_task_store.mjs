import { lstat, readFile, realpath } from 'node:fs/promises';
import path from 'node:path';

import { deepFreeze } from '../../../scripts/control-center/project_contract.mjs';
import { writeJsonAtomic } from '../../../scripts/feishu-commander/atomic_store.mjs';

const locks = new Map();
const TERMINAL = new Set(['completed', 'failed', 'cancelled']);
const FORWARD = deepFreeze({
  received: ['planning', 'waiting_input', 'cancelled'],
  planning: ['knowledge_preflight', 'waiting_input', 'cancelled'],
  knowledge_preflight: ['evidence_check', 'waiting_input', 'repairing', 'cancelled'],
  evidence_check: ['executing', 'waiting_input', 'waiting_collaboration', 'repairing', 'cancelled'],
  executing: ['debugging', 'waiting_input', 'waiting_collaboration', 'repairing', 'cancelled'],
  debugging: ['quality_review', 'waiting_input', 'waiting_collaboration', 'repairing', 'failed', 'cancelled'],
  quality_review: ['awaiting_emperor_review', 'repairing', 'failed', 'cancelled'],
  awaiting_emperor_review: ['pilot_running', 'repairing', 'cancelled'],
  pilot_running: ['performance_review', 'repairing', 'failed', 'cancelled'],
  performance_review: ['completed', 'repairing', 'failed', 'cancelled'],
  waiting_input: ['planning', 'knowledge_preflight', 'evidence_check', 'executing', 'debugging', 'cancelled'],
  waiting_collaboration: ['evidence_check', 'executing', 'debugging', 'cancelled'],
  repairing: ['planning', 'knowledge_preflight', 'evidence_check', 'executing', 'debugging', 'quality_review', 'failed', 'cancelled'],
  completed: [],
  failed: [],
  cancelled: [],
});
const IMMUTABLE = Object.freeze([
  'enterpriseId',
  'businessProjectId',
  'taskId',
  'planId',
  'planVersion',
  'planSha256',
  'capabilityId',
]);

export function createDealTaskStore({
  taskFile,
  taskRoot,
  initialTask,
} = {}) {
  if (typeof taskFile !== 'string' || typeof taskRoot !== 'string') {
    throw new TypeError('taskFile and taskRoot are required');
  }
  validateTask(initialTask);
  const seed = deepFreeze(structuredClone(initialTask));
  return Object.freeze({
    async initialize() {
      await assertTaskPath(taskFile, taskRoot);
      return exclusive(path.resolve(taskFile), async () => {
        const existing = await readFile(taskFile, 'utf8').catch((error) => {
          if (error?.code === 'ENOENT') return '';
          throw error;
        });
        if (existing) return deepFreeze(validateTask(JSON.parse(existing)));
        await writeJsonAtomic(taskFile, seed);
        return seed;
      });
    },
    async read() {
      await assertTaskPath(taskFile, taskRoot);
      return deepFreeze(validateTask(JSON.parse(await readFile(taskFile, 'utf8'))));
    },
    async update({
      expectedRevision,
      mutate,
      reason,
      now = () => new Date(),
    } = {}) {
      if (!Number.isInteger(expectedRevision) || expectedRevision < 1) {
        throw new Error('expected task revision is invalid');
      }
      if (typeof mutate !== 'function' || typeof reason !== 'string' || reason.trim() === '') {
        throw new Error('task update mutate and reason are required');
      }
      await assertTaskPath(taskFile, taskRoot);
      return exclusive(path.resolve(taskFile), async () => {
        const current = validateTask(JSON.parse(await readFile(taskFile, 'utf8')));
        if (current.revision !== expectedRevision) throw new Error('deal task revision conflict');
        const proposed = mutate(structuredClone(current));
        if (!proposed || typeof proposed !== 'object') throw new Error('task mutation returned invalid value');
        validateIdentityImmutable(current, proposed);
        if (current.status !== proposed.status && !canTransition(current.status, proposed.status)) {
          throw new Error(`invalid task transition: ${current.status} -> ${proposed.status}`);
        }
        if (TERMINAL.has(current.status) && proposed.status !== current.status) {
          throw new Error('terminal task cannot recover automatically');
        }
        const createdAt = requireIsoNow(now);
        proposed.revision = current.revision + 1;
        proposed.updatedAt = createdAt;
        proposed.statusHistory = [
          ...current.statusHistory,
          {
            from: current.status,
            to: proposed.status,
            reason: reason.trim(),
            taskRevision: proposed.revision,
            planVersion: current.planVersion,
            createdAt,
          },
        ];
        const valid = validateTask(proposed);
        await writeJsonAtomic(taskFile, valid);
        return deepFreeze(valid);
      });
    },
  });
}

export function canTransition(from, to) {
  return FORWARD[from]?.includes(to) ?? false;
}

export function incrementRootCause(task, rootCauseCode) {
  validateTask(task);
  if (typeof rootCauseCode !== 'string' || !/^[a-z][a-z0-9_]{2,63}$/u.test(rootCauseCode)) {
    throw new Error('root cause code is invalid');
  }
  const count = (task.failureCounts[rootCauseCode] ?? 0) + 1;
  return deepFreeze({
    ...structuredClone(task),
    failureCounts: {
      ...task.failureCounts,
      [rootCauseCode]: count,
    },
    status: count >= 3 ? 'failed' : 'repairing',
  });
}

function validateTask(task) {
  if (!task || typeof task !== 'object' || Array.isArray(task)) throw new Error('deal task is invalid');
  if (task.schemaVersion !== 1 || !Number.isInteger(task.revision) || task.revision < 1) {
    throw new Error('deal task version is invalid');
  }
  if (!Object.hasOwn(FORWARD, task.status)) throw new Error('deal task status is invalid');
  for (const field of IMMUTABLE.slice(0, 4)) {
    if (typeof task[field] !== 'string' || task[field].trim() === '') {
      throw new Error(`deal task ${field} is invalid`);
    }
  }
  if (!Number.isInteger(task.planVersion) || task.planVersion < 1
    || !/^[a-f0-9]{64}$/u.test(task.planSha256 ?? '')) {
    throw new Error('deal task plan binding is invalid');
  }
  if (!Array.isArray(task.statusHistory)
    || !task.failureCounts
    || typeof task.failureCounts !== 'object') {
    throw new Error('deal task recovery fields are invalid');
  }
  return task;
}

function validateIdentityImmutable(current, proposed) {
  for (const field of IMMUTABLE) {
    if (current[field] !== proposed[field]) {
      throw new Error(`immutable task identity changed: ${field}`);
    }
  }
}

async function assertTaskPath(taskFile, taskRoot) {
  const canonicalTask = await realpath(taskRoot);
  if (path.dirname(path.resolve(taskFile)) !== path.resolve(canonicalTask)) {
    throw new Error('task file escapes task root');
  }
  const details = await lstat(taskFile).catch((error) => {
    if (error?.code === 'ENOENT') return null;
    throw error;
  });
  if (details?.isSymbolicLink()) throw new Error('task file must not be symbolic');
}

async function exclusive(key, operation) {
  const previous = locks.get(key) ?? Promise.resolve();
  const current = previous.catch(() => {}).then(operation);
  locks.set(key, current);
  try { return await current; } finally {
    if (locks.get(key) === current) locks.delete(key);
  }
}

function requireIsoNow(now) {
  const value = now();
  if (!(value instanceof Date) || Number.isNaN(value.getTime())) throw new Error('task clock is invalid');
  return value.toISOString();
}
