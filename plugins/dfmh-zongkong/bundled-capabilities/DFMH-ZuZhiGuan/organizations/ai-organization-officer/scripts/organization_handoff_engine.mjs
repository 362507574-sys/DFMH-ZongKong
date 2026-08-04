const ORDER = ['talent-allocation', 'talent-development', 'process-replication'];
const HASH = /^[a-f0-9]{64}$/u;

export function createSkillHandoff(input = {}) {
  if (ORDER.indexOf(input.fromSkill) < 0
    || ORDER.indexOf(input.fromSkill) >= ORDER.indexOf(input.toSkill)) {
    throw new Error('handoff skill order is invalid');
  }
  const bindings = (input.bindings ?? []).map((binding) => {
    if (!Number.isInteger(binding.version) || binding.version < 1
      || !HASH.test(binding.sha256 ?? '')
      || /(^|\/)(current|latest)(\/|\.|$)/u.test(binding.sourceRef ?? '')) {
      throw new Error('handoff requires exact version hash and sourceRef');
    }
    return Object.freeze(structuredClone(binding));
  });
  if (bindings.length === 0) throw new Error('handoff bindings are required');
  return Object.freeze({
    schemaVersion: 2,
    enterpriseId: input.enterpriseId,
    businessProjectId: input.businessProjectId,
    taskId: input.taskId,
    fromSkill: input.fromSkill,
    toSkill: input.toSkill,
    bindings: Object.freeze(bindings),
    payload: Object.freeze(structuredClone(input.payload ?? {})),
    status: 'ready',
  });
}

export function createUpstreamChangeRequest(input = {}) {
  const { execution } = input;
  if (ORDER.indexOf(input.targetSkill) < 0
    || ORDER.indexOf(input.targetSkill) >= ORDER.indexOf(execution?.primarySkill)) {
    throw new Error('targetSkill must be upstream');
  }
  if (!input.problem?.trim() || !(input.evidence?.length) || !(input.impact?.length)) {
    throw new Error('upstream request problem evidence and impact are required');
  }
  if (!Number.isInteger(input.currentBinding?.version)
    || !HASH.test(input.currentBinding?.sha256 ?? '')) {
    throw new Error('upstream request current binding is invalid');
  }
  return Object.freeze({
    schemaVersion: 2,
    enterpriseId: execution.enterpriseId,
    businessProjectId: execution.businessProjectId,
    taskId: execution.taskId,
    sourceSkill: execution.primarySkill,
    sourceStageId: execution.currentStageId,
    targetSkill: input.targetSkill,
    problem: input.problem,
    evidence: Object.freeze([...input.evidence]),
    impact: Object.freeze([...input.impact]),
    pausePosition: execution.currentStageId,
    currentBinding: Object.freeze(structuredClone(input.currentBinding)),
    recommendedChange: Object.freeze([...(input.recommendedChange ?? [])]),
    status: 'requested_to_control_center',
  });
}
