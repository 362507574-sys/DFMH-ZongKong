const CATEGORIES = new Set([
  'input', 'context', 'evidence', 'business-logic', 'tool-or-file',
  'artifact-quality', 'dependency-version', 'permission-boundary', 'compliance-risk',
]);

export function diagnoseOrganizationFailure({
  execution,
  observation,
  priorDiagnostics = [],
  now = () => new Date(),
} = {}) {
  if (!execution?.enterpriseId || !execution?.businessProjectId || !execution?.taskId) {
    throw new Error('execution identity is required');
  }
  if (!CATEGORIES.has(observation?.category)) throw new Error('failure category is invalid');
  if (!observation.rootCauseKey || !observation.code || !observation.repairAction) {
    throw new Error('failure root cause code and repair are required');
  }
  const attempt = priorDiagnostics.filter(
    (item) => item.rootCauseKey === observation.rootCauseKey,
  ).length + 1;
  const nextStatus = observation.nonIdempotent
    ? 'waiting_decision'
    : attempt >= 3
      ? 'failed'
      : 'debugging';
  return Object.freeze({
    schemaVersion: 2,
    diagnosticId: `${execution.taskId}-${String(priorDiagnostics.length + 1).padStart(3, '0')}`,
    enterpriseId: execution.enterpriseId,
    businessProjectId: execution.businessProjectId,
    taskId: execution.taskId,
    skill: execution.primarySkill,
    stageId: execution.currentStageId,
    code: observation.code,
    category: observation.category,
    rootCauseKey: observation.rootCauseKey,
    attempt,
    evidenceRefs: Object.freeze([...(observation.evidenceRefs ?? [])]),
    impactedArtifacts: Object.freeze([...(observation.impactedArtifacts ?? [])]),
    repairAction: observation.repairAction,
    regressionScope: Object.freeze([...(observation.impactedArtifacts ?? [])]),
    nextStatus,
    retryAllowed: nextStatus === 'debugging',
    occurredAt: isoNow(now),
  });
}

function isoNow(now) {
  const value = now();
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) throw new Error('now is invalid');
  return date.toISOString();
}
