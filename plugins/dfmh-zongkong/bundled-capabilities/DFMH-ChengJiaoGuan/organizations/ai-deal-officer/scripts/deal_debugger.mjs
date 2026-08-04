import path from 'node:path';

import { deepFreeze } from '../../../scripts/control-center/project_contract.mjs';

const PHASES = new Set(['before_execution', 'during_execution', 'after_execution']);
const RULES = Object.freeze([
  ['contextMismatch', 'context_mismatch', 'stop', false],
  ['complianceRisk', 'compliance_blocked', 'stop', false],
  ['externalActionUnauthorized', 'external_action_blocked', 'stop', false],
  ['permissionMissing', 'permission_gap', 'wait_for_input', false],
  ['upstreamChanged', 'upstream_drift', 'rollback_to_insight', true],
  ['crossOrganization', 'cross_org_issue', 'request_collaboration', false],
  ['evidenceMissing', 'evidence_gap', 'repair_current_step', true],
  ['insightInvalid', 'insight_error', 'rollback_to_insight', true],
  ['strategyInvalid', 'strategy_error', 'rollback_to_strategy', true],
  ['trainingInvalid', 'training_error', 'retrain', true],
  ['temporaryFailure', 'temporary_failure', 'repair_current_step', true],
]);
const OBSERVATION_KEYS = new Set([...RULES.map(([key]) => key), 'evidenceRefs']);
const REGISTERED_ORGANIZATIONS = new Set([
  'ai-helmsman',
  'ai-growth-strategist',
  'ai-deal-officer',
  'ai-organization-officer',
  'ai-brand-officer',
]);

export function debugDealStep({
  phase,
  plan,
  task,
  observations = {},
  now = () => new Date(),
} = {}) {
  if (!PHASES.has(phase)) throw new Error('debug phase is invalid');
  validateContext(plan, task);
  if (!observations || typeof observations !== 'object' || Array.isArray(observations)) {
    throw new Error('observations must be an object');
  }
  const unknown = Object.keys(observations).filter((key) => !OBSERVATION_KEYS.has(key));
  if (unknown.length > 0) throw new Error(`unknown observations: ${unknown.join(',')}`);
  const evidenceRefs = validateEvidenceRefs(observations.evidenceRefs ?? []);
  if (observations.crossOrganization
    && (!REGISTERED_ORGANIZATIONS.has(observations.crossOrganization)
      || observations.crossOrganization === 'ai-deal-officer')) {
    throw new Error('cross-organization target is invalid');
  }
  const matched = RULES.find(([key]) => Boolean(observations[key]));
  const [observationKey, rootCauseCode, action, retryable] = matched
    ?? ['', 'none', 'continue', false];
  const affectedStepIds = affectedSteps({ action, plan, task });
  const createdAt = requireIsoNow(now);
  return deepFreeze({
    schemaVersion: 1,
    diagnosticId: `${task.taskId}-${phase}-${rootCauseCode}`,
    taskId: task.taskId,
    planId: plan.planId,
    planVersion: plan.planVersion,
    phase,
    rootCauseCode,
    action,
    retryable,
    evidenceRefs,
    affectedStepIds,
    collaborationOrganizationId: observationKey === 'crossOrganization'
      ? observations.crossOrganization
      : '',
    createdAt,
  });
}

function validateContext(plan, task) {
  if (!plan || !task
    || task.taskId !== plan.taskId
    || task.enterpriseId !== plan.enterpriseId
    || task.businessProjectId !== plan.businessProjectId
    || task.planId !== plan.planId
    || task.planVersion !== plan.planVersion) {
    throw new Error('debug context does not match plan');
  }
  if (!Array.isArray(plan.steps)
    || !plan.steps.some((step) => step.stepId === task.currentStepId)) {
    throw new Error('debug current step is outside the plan');
  }
}

function affectedSteps({ action, plan, task }) {
  const fromSkill = action === 'rollback_to_insight'
    ? 'customer-insight'
    : action === 'rollback_to_strategy'
      ? 'deal-strategy'
      : action === 'retrain'
        ? 'sales-training'
        : '';
  if (!fromSkill) return action === 'continue' ? [] : [task.currentStepId];
  const start = plan.steps.findIndex((step) => step.skillId === fromSkill);
  if (start < 0) return [task.currentStepId];
  return plan.steps.slice(start).map((step) => step.stepId);
}

function validateEvidenceRefs(refs) {
  if (!Array.isArray(refs)) throw new Error('diagnostic evidence references are invalid');
  return refs.map((ref) => {
    if (typeof ref !== 'string'
      || ref.trim() === ''
      || path.isAbsolute(ref)
      || /^[a-z]:[\\/]/iu.test(ref)
      || ref.includes('..')) {
      throw new Error('diagnostic evidence reference is unsafe');
    }
    return ref;
  });
}

function requireIsoNow(now) {
  const value = now();
  if (!(value instanceof Date) || Number.isNaN(value.getTime())) {
    throw new Error('debug clock is invalid');
  }
  return value.toISOString();
}
