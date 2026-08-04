const CLASSES = ['fact', 'source', 'inference', 'assumption', 'unknown'];

export function buildEvidenceIndex({
  enterpriseId,
  businessProjectId,
  taskId,
  entries,
} = {}) {
  if (![enterpriseId, businessProjectId, taskId].every((item) => typeof item === 'string' && item)) {
    throw new Error('evidence identity is required');
  }
  if (!Array.isArray(entries)) throw new Error('evidence entries must be an array');
  const ids = new Set();
  const normalized = entries.map((entry) => {
    if (!entry?.id || ids.has(entry.id)) throw new Error('evidence id must be unique');
    if (!CLASSES.includes(entry.classification)) throw new Error('evidence classification is invalid');
    if (!entry.statement?.trim() || !entry.observedAt) throw new Error('evidence statement and time are required');
    if (!entry.sourceRef && !['unknown', 'assumption'].includes(entry.classification)) {
      throw new Error('evidence sourceRef is required');
    }
    ids.add(entry.id);
    return Object.freeze({
      ...structuredClone(entry),
      conflictsWith: Object.freeze([...(entry.conflictsWith ?? [])]),
    });
  });
  return Object.freeze({
    schemaVersion: 2,
    enterpriseId,
    businessProjectId,
    taskId,
    entries: Object.freeze(normalized),
    conflicts: Object.freeze(
      normalized.filter((entry) => entry.conflictsWith.length > 0).map((entry) => entry.id),
    ),
  });
}
