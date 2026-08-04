import { readFile } from 'node:fs/promises';

import { writeJsonAtomic } from '../../../scripts/feishu-commander/atomic_store.mjs';

const ALLOWED = new Map([
  ['planning', ['evidence', 'waiting_input', 'blocked', 'failed', 'cancelled']],
  ['evidence', ['executing', 'waiting_input', 'waiting_collaboration', 'blocked', 'failed', 'cancelled']],
  ['executing', ['validating', 'debugging', 'waiting_input', 'waiting_collaboration', 'waiting_decision', 'blocked', 'failed', 'cancelled']],
  ['validating', ['debugging', 'waiting_decision', 'formalizing', 'completed', 'blocked', 'failed', 'cancelled']],
  ['debugging', ['evidence', 'executing', 'validating', 'waiting_input', 'waiting_decision', 'blocked', 'failed', 'cancelled']],
  ['waiting_input', ['planning', 'evidence', 'executing', 'cancelled', 'failed']],
  ['waiting_collaboration', ['evidence', 'executing', 'cancelled', 'failed']],
  ['waiting_decision', ['executing', 'formalizing', 'completed', 'cancelled', 'failed']],
  ['formalizing', ['completed', 'debugging', 'blocked', 'failed']],
  ['completed', ['archived']],
]);

export function createOrganizationExecutionStore({
  workspace,
  now = () => new Date(),
} = {}) {
  if (!workspace?.executionFile || !workspace?.timelineFile) {
    throw new Error('execution workspace is required');
  }

  const read = async () => JSON.parse(await readFile(workspace.executionFile, 'utf8'));
  const readTimeline = async () => JSON.parse(await readFile(workspace.timelineFile, 'utf8'));

  return Object.freeze({
    async create(input) {
      validateExecution(input);
      const existing = await readFile(workspace.executionFile, 'utf8').catch((error) =>
        error?.code === 'ENOENT' ? null : Promise.reject(error));
      if (existing !== null) {
        const stored = JSON.parse(existing);
        if (!sameIdentity(stored, input)) throw new Error('execution identity conflict');
        return deepFreeze(stored);
      }
      await writeJsonAtomic(workspace.executionFile, input);
      await writeJsonAtomic(workspace.timelineFile, {
        schemaVersion: 2,
        enterpriseId: input.enterpriseId,
        businessProjectId: input.businessProjectId,
        taskId: input.taskId,
        events: [],
      });
      return deepFreeze(await read());
    },

    async read() {
      return deepFreeze(await read());
    },

    async transition({
      expectedRevision,
      from,
      to,
      currentStageId,
      checkpoint = null,
    } = {}) {
      const current = await read();
      if (current.revision !== expectedRevision) throw new Error('execution revision conflict');
      if (current.status !== from) throw new Error('execution transition source mismatch');
      if (!ALLOWED.get(from)?.includes(to)) {
        throw new Error(`execution transition not allowed: ${from} -> ${to}`);
      }
      if (checkpoint !== null) validateCheckpoint(checkpoint);
      const occurredAt = isoNow(now);
      const next = {
        ...current,
        status: to,
        revision: current.revision + 1,
        currentStageId,
        checkpoint: checkpoint ?? current.checkpoint,
        updatedAt: occurredAt,
      };
      const timeline = await readTimeline();
      timeline.events.push({
        sequence: timeline.events.length + 1,
        from,
        to,
        stageId: currentStageId,
        revision: next.revision,
        occurredAt,
      });
      await writeJsonAtomic(workspace.executionFile, next);
      await writeJsonAtomic(workspace.timelineFile, timeline);
      return deepFreeze(await read());
    },

    async resume({ expectedRevision, invocationIdentity } = {}) {
      const current = await read();
      if (current.revision !== expectedRevision) throw new Error('execution revision conflict');
      if (!sameIdentity(current, invocationIdentity)) throw new Error('resume identity mismatch');
      if (!current.checkpoint?.id || current.checkpoint.safeToResume !== true) {
        throw new Error('safe checkpoint is required for resume');
      }
      if (current.checkpoint.sideEffect === 'non-idempotent-pending') {
        throw new Error('non-idempotent checkpoint requires manual decision');
      }
      return deepFreeze(current);
    },
  });
}

function validateExecution(value) {
  if (!value || value.schemaVersion !== 2 || value.status !== 'planning') {
    throw new Error('initial execution is invalid');
  }
  if (!sameIdentity(value, value)
    || !Number.isInteger(value.planVersion)
    || !Number.isInteger(value.revision)
    || value.revision !== 1
    || !value.currentStageId) {
    throw new Error('initial execution fields are invalid');
  }
}

function validateCheckpoint(value) {
  if (!value?.id || typeof value.safeToResume !== 'boolean' || !value.sideEffect) {
    throw new Error('checkpoint is invalid');
  }
}

function sameIdentity(left, right) {
  return Boolean(left?.enterpriseId
    && left.enterpriseId === right?.enterpriseId
    && left.businessProjectId === right?.businessProjectId
    && left.taskId === right?.taskId);
}

function isoNow(now) {
  const value = now();
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) throw new Error('now is invalid');
  return date.toISOString();
}

function deepFreeze(value) {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const item of Object.values(value)) deepFreeze(item);
  }
  return value;
}
