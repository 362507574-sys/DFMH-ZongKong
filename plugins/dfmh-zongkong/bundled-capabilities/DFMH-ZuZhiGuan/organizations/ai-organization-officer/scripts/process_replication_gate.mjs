import { validateProcessReplicationCandidate } from './process_replication_contract.mjs';

export function checkBeforeProcessDiagnosis({
  task,
  enterpriseProfile,
  knowledgeContext,
  upstreamTalentAsset,
  upstreamDevelopmentAsset,
} = {}) {
  const failures = [];
  if (!task
    || task.capabilityId !== 'process-replication'
    || task.enterpriseId !== enterpriseProfile?.enterpriseId) {
    failures.push(failure('enterprise_context_missing', '企业与流程复制任务不匹配', 'enterpriseId'));
  }
  const scopes = task?.accessEnvelope?.allowedScopes ?? [];
  if (!scopes.includes('organization.read') || !scopes.includes('organization.draft.write')) {
    failures.push(failure('access_scope_missing', '流程诊断需要组织读取和候选写入权限', 'accessEnvelope'));
  }
  if (!knowledgeContext
    || !['matched', 'no_hit', 'degraded'].includes(knowledgeContext.status)
    || task?.knowledgeStatus !== knowledgeContext?.status) {
    failures.push(failure('knowledge_preflight_incomplete', '知识前置尚未完成', 'knowledgeContext'));
  }
  if (knowledgeContext?.status === 'degraded' && !knowledgeContext.degradedReason?.trim()) {
    failures.push(failure('knowledge_degraded_reason_missing', '知识降级必须保留原因', 'knowledgeContext'));
  }
  if (!validUpstream(upstreamTalentAsset, task?.enterpriseId, 'talent-allocation')
    || !validUpstream(upstreamDevelopmentAsset, task?.enterpriseId, 'talent-development')) {
    failures.push(failure(
      'approved_upstream_assets_missing',
      '必须绑定同企业人才配置和人才培养正式资产',
      'upstreamAssets',
    ));
  }
  return result(failures);
}

export function checkProcessReplicationCandidate({
  candidate,
  task,
  enterpriseProfile,
  knowledgeContext,
  upstreamTalentAsset,
  upstreamDevelopmentAsset,
} = {}) {
  const before = checkBeforeProcessDiagnosis({
    task,
    enterpriseProfile,
    knowledgeContext,
    upstreamTalentAsset,
    upstreamDevelopmentAsset,
  });
  const contract = validateProcessReplicationCandidate({
    candidate,
    task,
    enterpriseProfile,
    knowledgeContext,
    upstreamTalentAsset,
    upstreamDevelopmentAsset,
  });
  return result([...before.failures, ...contract.failures]);
}

function validUpstream(value, enterpriseId, capabilityId) {
  return Boolean(value
    && value.enterpriseId === enterpriseId
    && value.capabilityId === capabilityId
    && Number.isInteger(value.version)
    && value.version > 0
    && /^[a-f0-9]{64}$/u.test(value.candidateSha256 ?? '')
    && /^[a-f0-9]{64}$/u.test(value.formalAssetSha256 ?? '')
    && value.asset);
}

function failure(code, message, path) {
  return { code, message, path };
}

function result(failures) {
  const unique = [...new Map(failures.map((item) => [`${item.path}|${item.code}`, item])).values()];
  unique.sort((left, right) => left.path.localeCompare(right.path) || left.code.localeCompare(right.code));
  return Object.freeze({ ok: unique.length === 0, failures: Object.freeze(unique) });
}
