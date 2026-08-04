import { deepFreeze } from '../../../scripts/control-center/project_contract.mjs';

const SKILL_ORDER = Object.freeze(['customer-insight', 'deal-strategy', 'sales-training']);
const REQUEST_FIELDS = new Set([
  'schemaVersion',
  'taskId',
  'enterpriseId',
  'businessProjectId',
  'goal',
  'requestedSkillIds',
  'issueSignals',
  'availableInputs',
  'allowedScopes',
  'knowledgeStatus',
]);
const KNOWLEDGE_STATUSES = new Set(['matched', 'ready', 'no_hit', 'degraded']);
const INPUT_CLASSES = new Set([
  'enterprise_fact',
  'customer_statement',
  'behavior_evidence',
  'public_source',
  'ai_inference',
  'hypothesis',
  'unknown',
]);
const KNOWN_FACT_CLASSES = new Set([
  'enterprise_fact',
  'customer_statement',
  'behavior_evidence',
  'public_source',
]);
const HYPOTHESIS_CLASSES = new Set(['ai_inference', 'hypothesis']);
const SKILL_CONFIG = deepFreeze({
  'customer-insight': {
    requiredScopes: ['deal.customer.read', 'deal.candidate.write'],
    completionCriteria: [
      'identity_bound',
      'evidence_classified',
      'customer_profile_complete',
      'buying_motivation_evidenced',
      'deal_stage_evidenced',
      'core_concern_evidenced',
    ],
    outputArtifactId: 'customer-insight',
    upstreamArtifactId: '',
  },
  'deal-strategy': {
    requiredScopes: ['deal.insight.read', 'deal.candidate.write'],
    completionCriteria: [
      'exact_insight_dependency',
      'communication_strategy_complete',
      'value_framing_complete',
      'objection_handling_complete',
      'deal_path_complete',
    ],
    outputArtifactId: 'deal-strategy',
    upstreamArtifactId: 'customer-insight',
  },
  'sales-training': {
    requiredScopes: ['deal.strategy.read', 'deal.training.write'],
    completionCriteria: [
      'exact_strategy_dependency',
      'ai_customer_simulation_complete',
      'sales_coaching_complete',
      'sales_scoring_complete',
      'top_performer_replication_complete',
    ],
    outputArtifactId: 'sales-training',
    upstreamArtifactId: 'deal-strategy',
  },
});
const ISSUE_ROUTES = deepFreeze({
  traffic_quality: { ownerOrganizationId: 'ai-growth-strategist', collaborationRequired: true },
  product_fit: { ownerOrganizationId: 'ai-helmsman', collaborationRequired: true },
  pricing: { ownerOrganizationId: 'ai-helmsman', collaborationRequired: true },
  delivery: { ownerOrganizationId: 'ai-helmsman', collaborationRequired: true },
  brand_trust: { ownerOrganizationId: 'ai-brand-officer', collaborationRequired: true },
  customer_insight: { ownerOrganizationId: 'ai-deal-officer', collaborationRequired: false },
  deal_strategy: { ownerOrganizationId: 'ai-deal-officer', collaborationRequired: false },
  sales_execution: { ownerOrganizationId: 'ai-deal-officer', collaborationRequired: false },
  evidence_insufficient: { ownerOrganizationId: 'ai-deal-officer', collaborationRequired: false },
});

export function buildDealExecutionPlan({
  request,
  projectContext,
  now = () => new Date(),
} = {}) {
  validateRequest(request);
  const readableArtifacts = validateProjectContext(projectContext, request);
  const requested = new Set(request.requestedSkillIds);
  const readableIds = new Set(readableArtifacts.map((item) => item.artifactId));

  if (requested.has('deal-strategy') && !readableIds.has('customer-insight')) {
    requested.add('customer-insight');
  }
  if (requested.has('sales-training') && !readableIds.has('deal-strategy')) {
    requested.add('deal-strategy');
    if (!readableIds.has('customer-insight')) requested.add('customer-insight');
  }

  const ordered = SKILL_ORDER.filter((skillId) => requested.has(skillId));
  const missingScopes = ordered
    .flatMap((skillId) => SKILL_CONFIG[skillId].requiredScopes)
    .filter((scope) => !request.allowedScopes.includes(scope));
  if (missingScopes.length > 0) {
    throw new Error(`permission gap for scopes: ${[...new Set(missingScopes)].join(',')}`);
  }

  const steps = ordered.map((skillId, index) => {
    const config = SKILL_CONFIG[skillId];
    return {
      stepId: `step-${index + 1}-${skillId}`,
      skillId,
      dependsOn: index === 0 ? [] : [`step-${index}-${ordered[index - 1]}`],
      inputArtifactRefs: config.upstreamArtifactId
        ? readableArtifacts.filter((item) => item.artifactId === config.upstreamArtifactId)
        : [],
      outputArtifactId: config.outputArtifactId,
      requiredScopes: config.requiredScopes,
      completionCriteria: config.completionCriteria,
      debugCheckpoints: ['before_execution', 'during_execution', 'after_execution'],
      status: 'pending',
    };
  });
  const rootCauseHypothesis = classifyIssue(request.issueSignals);
  const evidenceSummary = summarizeEvidence(request.availableInputs);

  return deepFreeze({
    schemaVersion: 1,
    planId: `${request.taskId}-plan`,
    planVersion: 1,
    taskId: request.taskId,
    enterpriseId: request.enterpriseId,
    businessProjectId: request.businessProjectId,
    projectContextVersion: projectContext.projectContextVersion,
    ownerOrganizationId: 'ai-deal-officer',
    goal: request.goal.trim(),
    scope: ordered,
    nonGoals: [
      'traffic_acquisition',
      'product_redesign',
      'brand_repositioning',
      'external_customer_contact',
    ],
    knowledgeStatus: request.knowledgeStatus,
    evidenceSummary,
    rootCauseHypothesis,
    collaborationRequests: rootCauseHypothesis.collaborationRequired
      ? [{
        organizationId: rootCauseHypothesis.ownerOrganizationId,
        reasonCode: rootCauseHypothesis.code,
        requestedScope: ['diagnose_and_return_versioned_artifact'],
      }]
      : [],
    steps,
    retryLimitPerRootCause: 3,
    externalActionsAllowed: false,
    decisionBoundaries: [
      'payment',
      'external_publish',
      'irreversible_change',
      'account_permission',
    ],
    stopConditions: [
      'same_root_cause_failed_three_times',
      'cancelled',
      'identity_mismatch',
      'compliance_blocked',
    ],
    resumeFrom: {
      stepId: steps[0]?.stepId ?? '',
      checkpoint: 'before_execution',
    },
    createdAt: requireIsoNow(now),
  });
}

function validateRequest(request) {
  if (!isPlainObject(request)) throw new TypeError('request must be an object');
  const unknown = Object.keys(request).filter((key) => !REQUEST_FIELDS.has(key));
  if (unknown.length > 0) throw new Error(`unknown request fields: ${unknown.join(',')}`);
  if (request.schemaVersion !== 1) throw new Error('request schema version is unsupported');
  for (const field of ['taskId', 'enterpriseId']) requireSafeId(request[field], field);
  if (!/^[0-9]{8}-[0-9]{3}-[a-z0-9-]{3,80}$/u.test(request.businessProjectId ?? '')) {
    throw new Error('businessProjectId is invalid');
  }
  if (typeof request.goal !== 'string' || request.goal.trim().length < 4) {
    throw new Error('request goal is incomplete');
  }
  if (!Array.isArray(request.requestedSkillIds)
    || request.requestedSkillIds.length === 0
    || new Set(request.requestedSkillIds).size !== request.requestedSkillIds.length
    || request.requestedSkillIds.some((skillId) => !SKILL_ORDER.includes(skillId))) {
    throw new Error('requested skills are invalid');
  }
  if (!Array.isArray(request.issueSignals)
    || request.issueSignals.some((signal) => !Object.hasOwn(ISSUE_ROUTES, signal))) {
    throw new Error('issue signals are invalid');
  }
  if (!Array.isArray(request.availableInputs)) throw new Error('available inputs are invalid');
  for (const item of request.availableInputs) validateAvailableInput(item);
  if (!Array.isArray(request.allowedScopes)
    || request.allowedScopes.some((scope) => typeof scope !== 'string')) {
    throw new Error('allowed scopes are invalid');
  }
  if (!KNOWLEDGE_STATUSES.has(request.knowledgeStatus)) {
    throw new Error('knowledge preflight is incomplete');
  }
}

function validateProjectContext(context, request) {
  if (!isPlainObject(context)) throw new TypeError('project context must be an object');
  if (context.enterpriseId !== request.enterpriseId
    || context.businessProjectId !== request.businessProjectId
    || context.taskId !== request.taskId) {
    throw new Error('request identity does not match project context');
  }
  if (!Number.isInteger(context.projectContextVersion) || context.projectContextVersion < 1) {
    throw new Error('project context version is invalid');
  }
  if (!Array.isArray(context.readableArtifacts)) {
    throw new Error('project context readable artifacts are invalid');
  }
  const seen = new Set();
  return context.readableArtifacts.map((item) => {
    if (!isPlainObject(item)
      || !SKILL_ORDER.includes(item.artifactId)
      || !Number.isInteger(item.version)
      || item.version < 1
      || !/^[a-f0-9]{64}$/u.test(item.sha256 ?? '')
      || typeof item.sourceOrganizationId !== 'string') {
      throw new Error('readable artifact must bind an exact valid version');
    }
    const key = `${item.artifactId}@${item.version}`;
    if (seen.has(key)) throw new Error('readable artifact is duplicated');
    seen.add(key);
    return {
      artifactId: item.artifactId,
      version: item.version,
      sha256: item.sha256,
      sourceOrganizationId: item.sourceOrganizationId,
    };
  });
}

function validateAvailableInput(item) {
  if (!isPlainObject(item)
    || Object.keys(item).some((key) => !['classification', 'evidenceRef', 'summary'].includes(key))
    || !INPUT_CLASSES.has(item.classification)
    || typeof item.evidenceRef !== 'string'
    || typeof item.summary !== 'string'
    || item.summary.trim() === '') {
    throw new Error('available input is invalid');
  }
  if (item.classification !== 'unknown' && item.evidenceRef.trim() === '') {
    throw new Error('known input requires evidence reference');
  }
}

function classifyIssue(issueSignals) {
  const code = issueSignals[0] ?? 'evidence_insufficient';
  return { code, ...ISSUE_ROUTES[code] };
}

function summarizeEvidence(inputs) {
  return {
    knownFacts: inputs.filter((item) => KNOWN_FACT_CLASSES.has(item.classification)),
    hypotheses: inputs.filter((item) => HYPOTHESIS_CLASSES.has(item.classification)),
    unknowns: inputs.filter((item) => item.classification === 'unknown'),
    evidenceRefs: inputs.map((item) => item.evidenceRef).filter(Boolean),
  };
}

function requireSafeId(value, label) {
  if (typeof value !== 'string' || !/^[a-z0-9][a-z0-9-]{2,119}$/u.test(value)) {
    throw new Error(`${label} is invalid`);
  }
}

function requireIsoNow(now) {
  const value = now();
  if (!(value instanceof Date) || Number.isNaN(value.getTime())) {
    throw new Error('planner clock is invalid');
  }
  return value.toISOString();
}

function isPlainObject(value) {
  return value !== null
    && typeof value === 'object'
    && !Array.isArray(value)
    && [Object.prototype, null].includes(Object.getPrototypeOf(value));
}
