import { deepFreeze } from '../../../scripts/control-center/project_contract.mjs';

const FIELDS = new Set([
  'artifactId',
  'version',
  'sha256',
  'enterpriseId',
  'businessProjectId',
  'sourceOrganizationId',
]);

export function validateArtifactDependency(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError('artifact dependency must be an object');
  }
  const unknown = Object.keys(value).filter((key) => !FIELDS.has(key));
  if (unknown.length > 0) throw new Error(`artifact dependency has unknown fields: ${unknown.join(',')}`);
  for (const field of ['artifactId', 'enterpriseId', 'sourceOrganizationId']) {
    if (!/^[a-z0-9][a-z0-9-]{2,119}$/u.test(value[field] ?? '')) {
      throw new Error(`artifact dependency ${field} is invalid`);
    }
  }
  if (!/^[0-9]{8}-[0-9]{3}-[a-z0-9-]{3,80}$/u.test(value.businessProjectId ?? '')) {
    throw new Error('artifact dependency businessProjectId is invalid');
  }
  if (!Number.isInteger(value.version) || value.version < 1) {
    throw new Error('artifact dependency requires an exact version');
  }
  if (!/^[a-f0-9]{64}$/u.test(value.sha256 ?? '')) {
    throw new Error('artifact dependency sha256 is invalid');
  }
  return deepFreeze({
    artifactId: value.artifactId,
    version: value.version,
    sha256: value.sha256,
    enterpriseId: value.enterpriseId,
    businessProjectId: value.businessProjectId,
    sourceOrganizationId: value.sourceOrganizationId,
  });
}

export function invalidateDownstream({ changedArtifact, downstream } = {}) {
  const upstream = validateArtifactDependency(changedArtifact);
  if (!Array.isArray(downstream)) throw new TypeError('downstream candidates must be an array');
  return deepFreeze(downstream.map((candidate) => {
    if (!candidate || typeof candidate !== 'object' || !Array.isArray(candidate.dependencies)) {
      throw new Error('downstream candidate is invalid');
    }
    const dependencies = candidate.dependencies.map(validateArtifactDependency);
    const ids = dependencies.map((item) => item.artifactId);
    if (new Set(ids).size !== ids.length) throw new Error('downstream dependencies contain duplicate artifacts');
    const dependency = dependencies.find((item) => item.artifactId === upstream.artifactId);
    if (!dependency) return structuredClone(candidate);
    if (dependency.enterpriseId !== upstream.enterpriseId
      || dependency.businessProjectId !== upstream.businessProjectId) {
      throw new Error('cross-project dependency is forbidden');
    }
    if (dependency.version === upstream.version
      && dependency.sha256 === upstream.sha256
      && dependency.sourceOrganizationId === upstream.sourceOrganizationId) {
      return structuredClone(candidate);
    }
    return {
      ...structuredClone(candidate),
      status: 'review_required',
      reason: 'upstream_drift',
      invalidatedBy: upstream,
    };
  }));
}
