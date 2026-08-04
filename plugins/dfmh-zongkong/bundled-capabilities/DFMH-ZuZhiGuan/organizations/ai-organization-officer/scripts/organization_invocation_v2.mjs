const SKILLS = ['talent-allocation', 'talent-development', 'process-replication'];
const MODES = ['single-skill', 'continuous-chain', 'continuation'];
const FORBIDDEN_SCOPES = /root\.outputs\.write|shared-artifacts\.write|organization\.route\.change/u;
const BUSINESS_PROJECT_ID = /^[0-9]{8}-[0-9]{3}-[a-z0-9-]{3,80}$/u;

export function validateOrganizationInvocationV2(value) {
  if (!value || value.schemaVersion !== 2) throw new Error('invocation schemaVersion must be 2');
  if (value.primaryOrganization !== 'ai-organization-officer') {
    throw new Error('primary organization mismatch');
  }
  if (!SKILLS.includes(value.primarySkill)) throw new Error('primarySkill is invalid');
  if (!MODES.includes(value.mode)) throw new Error('invocation mode is invalid');
  for (const field of ['enterpriseId', 'businessProjectId', 'taskId', 'goal']) {
    if (typeof value[field] !== 'string' || !value[field].trim()) {
      throw new Error(`${field} is required`);
    }
  }
  if (!BUSINESS_PROJECT_ID.test(value.businessProjectId)) {
    throw new Error('businessProjectId is invalid');
  }
  if (value.permissionPackage?.enterpriseId !== value.enterpriseId) {
    throw new Error('permission enterprise mismatch');
  }
  const scopes = value.permissionPackage?.allowedScopes ?? [];
  if (!Array.isArray(scopes) || scopes.some((scope) => FORBIDDEN_SCOPES.test(scope))) {
    throw new Error('forbidden root or shared scope');
  }
  const chain = value.allowedCapabilityChain;
  if (!Array.isArray(chain) || chain.length === 0 || chain.some((skill) => !SKILLS.includes(skill))) {
    throw new Error('allowed capability chain is invalid');
  }
  if (chain[0] !== value.primarySkill) throw new Error('primarySkill must start capability chain');
  if (value.mode === 'single-skill' && chain.length !== 1) {
    throw new Error('single-skill invocation cannot expand capability chain');
  }
  const indexes = chain.map((skill) => SKILLS.indexOf(skill));
  if (indexes.some((index, position) => position > 0 && index <= indexes[position - 1])) {
    throw new Error('capability chain order is invalid');
  }
  if (!Array.isArray(value.decisionBoundary) || value.decisionBoundary.length === 0) {
    throw new Error('decisionBoundary is required');
  }
  if (value.mode === 'continuation') {
    const context = value.continuationContext;
    if (!context
      || context.enterpriseId !== value.enterpriseId
      || context.businessProjectId !== value.businessProjectId
      || context.taskId !== value.taskId
      || !context.checkpointId) {
      throw new Error('continuationContext identity or checkpoint is invalid');
    }
  }
  return deepFreeze(structuredClone(value));
}

function deepFreeze(value) {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const item of Object.values(value)) deepFreeze(item);
  }
  return value;
}
