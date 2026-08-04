const STATUSES = new Set([
  'completed', 'needs_decision', 'needs_collaboration',
  'needs_input', 'blocked', 'failed',
]);

export function createOrganizationReturnPackage({
  execution,
  status,
  artifacts = [],
  quality,
  decisions = [],
  risks = [],
  limitations = [],
  nextAction,
  resumeFrom = null,
} = {}) {
  if (!STATUSES.has(status)) throw new Error('return status is invalid');
  if (!execution?.enterpriseId || !execution?.businessProjectId || !execution?.taskId) {
    throw new Error('return execution identity is required');
  }
  if (status === 'completed' && quality?.ok !== true) {
    throw new Error('completed return requires passed quality');
  }
  if (status === 'needs_decision'
    && !decisions.some((item) => item?.executed === false && item?.owner)) {
    throw new Error('needs_decision requires an unexecuted user decision');
  }
  return Object.freeze({
    schemaVersion: 2,
    enterpriseId: execution.enterpriseId,
    businessProjectId: execution.businessProjectId,
    taskId: execution.taskId,
    status,
    artifacts: Object.freeze(structuredClone(artifacts)),
    quality: Object.freeze(structuredClone(quality ?? {})),
    decisions: Object.freeze(structuredClone(decisions)),
    risks: Object.freeze([...risks]),
    limitations: Object.freeze([...limitations]),
    nextAction,
    resumeFrom: resumeFrom ? Object.freeze(structuredClone(resumeFrom)) : null,
  });
}
