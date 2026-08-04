import { validateOrganizationInvocationV2 } from './organization_invocation_v2.mjs';

const STAGES = Object.freeze({
  'talent-allocation': [
    'context-lock', 'evidence-preflight', 'talent-problem-diagnosis',
    'organization-staffing', 'job-design', 'talent-profile',
    'recruitment-selection', 'person-job-match', 'management-reference',
    'downstream-handoff',
  ],
  'talent-development': [
    'context-lock', 'evidence-preflight', 'training-problem-diagnosis',
    'capability-gap', 'training-objectives', 'training-path',
    'learning-modules', 'real-work', 'mentor-feedback',
    'assessment-certification', 'growth-path', 'knowledge-transfer',
    'effectiveness-review', 'downstream-handoff',
  ],
  'process-replication': [
    'context-lock', 'evidence-preflight', 'process-reconstruction',
    'current-diagnosis', 'target-process', 'responsibility-controls',
    'sop-forms-checklists', 'mode-specific-assets', 'pilot',
    'debug-optimize', 'knowledge-base', 'replication-package',
    'monitor-version',
  ],
});

export function buildOrganizationExecutionPlan({
  invocation,
  availableInputs = [],
  now = () => new Date(),
} = {}) {
  const call = validateOrganizationInvocationV2(invocation);
  const createdAt = isoNow(now);
  const stages = call.allowedCapabilityChain.flatMap((skill, skillIndex) =>
    STAGES[skill].map((id, stageIndex) => ({
      id,
      skill,
      order: `${skillIndex + 1}.${stageIndex + 1}`,
      status: 'pending',
      enterWhen: stageIndex === 0 ? 'skill-authorized' : 'previous-stage-accepted',
      completeWhen: 'artifact-and-evidence-accepted',
    })));
  return Object.freeze({
    schemaVersion: 2,
    planVersion: call.continuationContext?.planVersion ?? 1,
    enterpriseId: call.enterpriseId,
    businessProjectId: call.businessProjectId,
    taskId: call.taskId,
    primarySkill: call.primarySkill,
    mode: call.mode,
    capabilitySequence: Object.freeze([...call.allowedCapabilityChain]),
    stages: Object.freeze(stages),
    availableInputs: Object.freeze(structuredClone(availableInputs)),
    pinnedInputs: Object.freeze(structuredClone(call.pinnedInputs ?? [])),
    acceptanceLevels: Object.freeze(['artifact', 'skill', 'cross-skill', 'organization-chain']),
    stopConditions: Object.freeze([
      'same-root-cause-three-failures',
      'missing-irreplaceable-fact',
      'permission-or-version-drift',
      'high-impact-decision-required',
      'non-idempotent-external-action',
    ]),
    createdAt,
  });
}

function isoNow(now) {
  const date = now();
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) throw new Error('now is invalid');
  return date.toISOString();
}
