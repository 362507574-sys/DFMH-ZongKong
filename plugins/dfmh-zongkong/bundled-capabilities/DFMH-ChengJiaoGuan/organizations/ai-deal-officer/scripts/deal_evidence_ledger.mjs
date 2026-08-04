import { lstat, readFile, realpath } from 'node:fs/promises';
import path from 'node:path';

import { deepFreeze } from '../../../scripts/control-center/project_contract.mjs';
import { writeJsonAtomic } from '../../../scripts/feishu-commander/atomic_store.mjs';

const locks = new Map();
const FACT_CLASSES = new Set([
  'enterprise_fact',
  'customer_statement',
  'behavior_evidence',
  'public_source',
  'ai_inference',
  'hypothesis',
  'unknown',
]);
const ENTRY_FIELDS = new Set([
  'evidenceId',
  'enterpriseId',
  'businessProjectId',
  'taskId',
  'customerRef',
  'factClass',
  'summary',
  'sourceRef',
  'sha256',
  'createdAt',
]);
const IDENTITY_FIELDS = Object.freeze([
  'enterpriseId',
  'businessProjectId',
  'taskId',
  'customerRef',
]);
const SENSITIVE_TEXT = /(?:\b1\d{10}\b|\b\d{15,17}[0-9Xx]\b|\b\d{16,19}\b)/u;

export function createDealEvidenceLedger({
  ledgerPath,
  taskRoot,
  identity,
} = {}) {
  validateIdentity(identity);
  if (typeof ledgerPath !== 'string' || typeof taskRoot !== 'string') {
    throw new TypeError('ledgerPath and taskRoot are required');
  }
  const frozenIdentity = deepFreeze(structuredClone(identity));

  return Object.freeze({
    async read() {
      await assertLedgerPath({ ledgerPath, taskRoot });
      return deepFreeze(await readLedger(ledgerPath, frozenIdentity));
    },
    async append({ expectedRevision, entry } = {}) {
      if (!Number.isInteger(expectedRevision) || expectedRevision < 0) {
        throw new Error('expected ledger revision is invalid');
      }
      const valid = validateEntry(entry, frozenIdentity);
      await assertLedgerPath({ ledgerPath, taskRoot });
      return exclusive(path.resolve(ledgerPath), async () => {
        const current = await readLedger(ledgerPath, frozenIdentity);
        if (current.revision !== expectedRevision) {
          throw new Error('evidence ledger revision conflict');
        }
        if (current.entries.some((item) => item.evidenceId === valid.evidenceId)) {
          throw new Error('evidence id already exists');
        }
        const next = {
          schemaVersion: 1,
          revision: current.revision + 1,
          identity: frozenIdentity,
          entries: [...current.entries, valid],
        };
        await writeJsonAtomic(ledgerPath, next);
        return deepFreeze(next);
      });
    },
  });
}

async function readLedger(ledgerPath, identity) {
  let parsed;
  try {
    parsed = JSON.parse(await readFile(ledgerPath, 'utf8'));
  } catch (error) {
    if (error?.code === 'ENOENT') {
      return {
        schemaVersion: 1,
        revision: 0,
        identity,
        entries: [],
      };
    }
    throw error;
  }
  if (parsed.schemaVersion !== 1
    || !Number.isInteger(parsed.revision)
    || parsed.revision < 0
    || !Array.isArray(parsed.entries)) {
    throw new Error('stored evidence ledger is invalid');
  }
  assertIdentityMatch(parsed.identity, identity);
  const entries = parsed.entries.map((entry) => validateEntry(entry, identity));
  if (new Set(entries.map((entry) => entry.evidenceId)).size !== entries.length) {
    throw new Error('stored evidence ledger contains duplicate ids');
  }
  if (parsed.revision !== entries.length) {
    throw new Error('stored evidence ledger revision does not match entries');
  }
  return {
    schemaVersion: 1,
    revision: parsed.revision,
    identity,
    entries,
  };
}

function validateEntry(entry, identity) {
  if (!isPlainObject(entry)) throw new TypeError('evidence entry must be an object');
  const unknown = Object.keys(entry).filter((key) => !ENTRY_FIELDS.has(key));
  if (unknown.length > 0) throw new Error(`evidence entry has unknown fields: ${unknown.join(',')}`);
  assertIdentityMatch(entry, identity);
  if (!/^[a-z0-9][a-z0-9-]{2,119}$/u.test(entry.evidenceId ?? '')) {
    throw new Error('evidence id is invalid');
  }
  if (!FACT_CLASSES.has(entry.factClass)) throw new Error('evidence fact class is invalid');
  if (typeof entry.summary !== 'string' || entry.summary.trim() === '') {
    throw new Error('evidence summary is required');
  }
  if (SENSITIVE_TEXT.test(entry.summary)) {
    throw new Error('evidence summary contains sensitive data');
  }
  if (typeof entry.sourceRef !== 'string'
    || path.isAbsolute(entry.sourceRef)
    || /^[a-z]:[\\/]/iu.test(entry.sourceRef)) {
    throw new Error('evidence source reference is invalid');
  }
  if (entry.factClass === 'ai_inference' && entry.sourceRef.trim() === '') {
    throw new Error('ai inference requires a source reference');
  }
  if (entry.factClass === 'enterprise_fact' && /^https?:\/\//iu.test(entry.sourceRef)) {
    throw new Error('public source cannot be labeled as enterprise fact');
  }
  if (!/^[a-f0-9]{64}$/u.test(entry.sha256 ?? '')) {
    throw new Error('evidence sha256 is invalid');
  }
  if (typeof entry.createdAt !== 'string'
    || Number.isNaN(Date.parse(entry.createdAt))
    || new Date(entry.createdAt).toISOString() !== entry.createdAt) {
    throw new Error('evidence createdAt is invalid');
  }
  return deepFreeze(structuredClone(entry));
}

function validateIdentity(identity) {
  if (!isPlainObject(identity)) throw new TypeError('evidence identity is required');
  if (Object.keys(identity).length !== IDENTITY_FIELDS.length) {
    throw new Error('evidence identity fields are invalid');
  }
  for (const field of IDENTITY_FIELDS) {
    if (typeof identity[field] !== 'string'
      || !/^[a-z0-9][a-z0-9-]{2,119}$/u.test(identity[field])) {
      throw new Error(`evidence identity is invalid: ${field}`);
    }
  }
}

function assertIdentityMatch(actual, expected) {
  if (!isPlainObject(actual)
    || IDENTITY_FIELDS.some((field) => actual[field] !== expected[field])) {
    throw new Error('evidence identity does not match current task and customer');
  }
}

async function assertLedgerPath({ ledgerPath, taskRoot }) {
  if (!path.isAbsolute(ledgerPath) || !path.isAbsolute(taskRoot)) {
    throw new Error('ledger and task paths must be absolute');
  }
  const canonicalTask = await realpath(taskRoot);
  const evidenceRoot = path.join(canonicalTask, 'evidence');
  const evidenceDetails = await lstat(evidenceRoot).catch(() => null);
  if (!evidenceDetails?.isDirectory() || evidenceDetails.isSymbolicLink()) {
    throw new Error('task evidence directory must be a regular directory');
  }
  const resolvedLedger = path.resolve(ledgerPath);
  if (path.dirname(resolvedLedger) !== path.resolve(evidenceRoot)) {
    throw new Error('ledger path escapes the task evidence directory');
  }
  const ledgerDetails = await lstat(resolvedLedger).catch((error) => {
    if (error?.code === 'ENOENT') return null;
    throw error;
  });
  if (ledgerDetails?.isSymbolicLink()) throw new Error('ledger file must not be symbolic');
  if (ledgerDetails && !ledgerDetails.isFile()) throw new Error('ledger path must be a file');
}

async function exclusive(key, operation) {
  const previous = locks.get(key) ?? Promise.resolve();
  const current = previous.catch(() => {}).then(operation);
  locks.set(key, current);
  try {
    return await current;
  } finally {
    if (locks.get(key) === current) locks.delete(key);
  }
}

function isPlainObject(value) {
  return value !== null
    && typeof value === 'object'
    && !Array.isArray(value)
    && [Object.prototype, null].includes(Object.getPrototypeOf(value));
}
