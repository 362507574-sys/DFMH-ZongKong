import { validateTalentDevelopmentCandidate } from './talent_development_contract.mjs';

export function checkBeforeDevelopmentDiagnosis({
  task,
  enterpriseProfile,
  knowledgeContext,
  upstreamTalentAsset,
} = {}) {
  const failures = [];
  if (!task
    || task.capabilityId !== 'talent-development'
    || task.enterpriseId !== enterpriseProfile?.enterpriseId) {
    failures.push(failure('enterprise_context_missing', '企业与人才培养任务不匹配', 'enterpriseId'));
  }
  const scopes = task?.accessEnvelope?.allowedScopes ?? [];
  if (!scopes.includes('organization.read') || !scopes.includes('organization.draft.write')) {
    failures.push(failure('access_scope_missing', '培养诊断需要组织读取和候选写入权限', 'accessEnvelope'));
  }
  if (!knowledgeContext
    || !['matched', 'no_hit', 'degraded'].includes(knowledgeContext.status)
    || task?.knowledgeStatus !== knowledgeContext?.status) {
    failures.push(failure('knowledge_preflight_incomplete', '知识前置尚未完成', 'knowledgeContext'));
  }
  if (knowledgeContext?.status === 'degraded' && !knowledgeContext.degradedReason?.trim()) {
    failures.push(failure('knowledge_degraded_reason_missing', '知识降级必须保留原因', 'knowledgeContext.degradedReason'));
  }
  if (!upstreamTalentAsset
    || upstreamTalentAsset.capabilityId !== 'talent-allocation'
    || upstreamTalentAsset.enterpriseId !== task?.enterpriseId
    || !/^[a-f0-9]{64}$/u.test(upstreamTalentAsset.candidateSha256 ?? '')) {
    failures.push(failure(
      'approved_talent_asset_missing',
      '必须绑定同企业已批准人才配置资产',
      'upstreamTalentAsset',
    ));
  }
  return result(failures);
}

export function checkDevelopmentCandidate({
  candidate,
  task,
  enterpriseProfile,
  knowledgeContext,
  upstreamTalentAsset,
} = {}) {
  const before = checkBeforeDevelopmentDiagnosis({
    task,
    enterpriseProfile,
    knowledgeContext,
    upstreamTalentAsset,
  });
  const contract = validateTalentDevelopmentCandidate({
    candidate,
    task,
    enterpriseProfile,
    knowledgeContext,
    upstreamTalentAsset,
  });
  return result([...before.failures, ...contract.failures]);
}

function failure(code, message, path) {
  return { code, message, path };
}

function result(failures) {
  const unique = [...new Map(failures.map((item) => [`${item.path}|${item.code}`, item])).values()];
  unique.sort((left, right) => left.path.localeCompare(right.path) || left.code.localeCompare(right.code));
  return Object.freeze({ ok: unique.length === 0, failures: Object.freeze(unique) });
}
