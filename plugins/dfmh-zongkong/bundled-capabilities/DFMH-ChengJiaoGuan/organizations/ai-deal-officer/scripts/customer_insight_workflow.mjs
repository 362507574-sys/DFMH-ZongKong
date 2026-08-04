import { deepFreeze } from '../../../scripts/control-center/project_contract.mjs';

import { validateCustomerInsightCandidate } from './customer_insight.mjs';
import { debugDealStep } from './deal_debugger.mjs';

const CHECKPOINTS = new Set(['before_execution', 'during_execution', 'after_execution']);
const STATUS_BY_ACTION = Object.freeze({
  continue: 'debugging',
  wait_for_input: 'waiting_input',
  request_collaboration: 'waiting_collaboration',
  repair_current_step: 'repairing',
  rollback_to_insight: 'repairing',
  rollback_to_strategy: 'repairing',
  retrain: 'repairing',
  stop: 'failed',
});

export function evaluateCustomerInsightWorkflow(input = {}) {
  if (!CHECKPOINTS.has(input.checkpoint)) {
    throw new Error('customer insight checkpoint is invalid');
  }
  if (input.task?.status === 'cancelled') {
    throw new Error('cancelled customer insight task cannot run');
  }
  if (!input.evidenceLedger || !Array.isArray(input.evidenceLedger.entries)) {
    throw new Error('customer insight evidence ledger is invalid');
  }

  const candidateResult = input.checkpoint === 'after_execution'
    ? validateCustomerInsightCandidate({
      candidate: input.candidate,
      context: input.context,
    })
    : null;
  const observations = observationsForCheckpoint(input, candidateResult);
  const diagnostic = debugDealStep({
    phase: input.checkpoint,
    plan: input.plan,
    task: input.task,
    observations,
    now: input.now,
  });

  const failureCounts = { ...input.task.failureCounts };
  let nextStatus = STATUS_BY_ACTION[diagnostic.action];
  if (diagnostic.action === 'continue') {
    nextStatus = input.checkpoint === 'before_execution'
      ? 'executing'
      : input.checkpoint === 'during_execution'
        ? 'debugging'
        : 'quality_review';
  } else if (diagnostic.retryable) {
    const count = (failureCounts[diagnostic.rootCauseCode] ?? 0) + 1;
    failureCounts[diagnostic.rootCauseCode] = count;
    if (count >= 3) nextStatus = 'failed';
  }

  return deepFreeze({
    ok: diagnostic.action === 'continue',
    checkpoint: input.checkpoint,
    diagnostic,
    diagnosticRef: `diagnostics/${diagnostic.diagnosticId}.json`,
    candidateResult,
    candidateStatus: input.checkpoint !== 'after_execution'
      ? ''
      : diagnostic.rootCauseCode === 'upstream_drift'
        ? 'review_required'
        : candidateResult.ok
          ? 'candidate_ready'
          : 'repair_required',
    nextStatus,
    failureCounts,
  });
}

function observationsForCheckpoint(input, candidateResult) {
  const observations = {};
  if (input.task.enterpriseId !== input.plan.enterpriseId
    || input.task.businessProjectId !== input.plan.businessProjectId
    || input.task.taskId !== input.plan.taskId) {
    observations.contextMismatch = true;
  }
  if (input.checkpoint === 'before_execution') {
    if (!input.context?.permissionsReady) observations.permissionMissing = true;
    if (!['matched', 'ready', 'no_hit', 'degraded'].includes(input.context?.knowledgeStatus)
      || !input.context?.requiredInputsReady
      || input.evidenceLedger.revision < 1) {
      observations.evidenceMissing = true;
    }
    if (input.context?.upstreamChanged) observations.upstreamChanged = true;
  }
  if (input.checkpoint === 'during_execution') {
    if (input.context?.scopeDrift) observations.contextMismatch = true;
    if (input.context?.evidenceGap) observations.evidenceMissing = true;
    if (input.context?.crossOrganization) {
      observations.crossOrganization = input.context.crossOrganization;
    }
    if (input.context?.externalActionUnauthorized) {
      observations.externalActionUnauthorized = true;
    }
    if (input.context?.complianceRisk) observations.complianceRisk = true;
    if (input.context?.temporaryFailure) observations.temporaryFailure = true;
  }
  if (input.checkpoint === 'after_execution') {
    if (!candidateResult.ok) observations.insightInvalid = true;
    if (input.context?.upstreamChanged) observations.upstreamChanged = true;
  }
  observations.evidenceRefs = input.evidenceLedger.entries
    .map((entry) => entry.evidenceId)
    .filter(Boolean);
  return observations;
}
