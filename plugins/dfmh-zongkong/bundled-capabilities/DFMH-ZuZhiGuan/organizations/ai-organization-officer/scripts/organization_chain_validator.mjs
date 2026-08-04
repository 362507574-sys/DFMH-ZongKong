import { sha256File } from '../../../scripts/feishu-commander/atomic_store.mjs';
import { loadOrganizationConfig } from './organization_config.mjs';
import { readStrictJson } from './strict_json.mjs';

const ORDER = ['talent-allocation', 'talent-development', 'process-replication'];
const HASH = /^[a-f0-9]{64}$/u;

export function validateOrganizationChainManifest(manifest) {
  const failures = [];
  if (!manifest || typeof manifest !== 'object' || Array.isArray(manifest)
    || manifest.schemaVersion !== 1
    || manifest.organizationId !== 'ai-organization-officer'
    || !manifest.enterpriseId?.trim()
    || !Number.isInteger(manifest.version)
    || manifest.version < 1) {
    failures.push(failure('manifest_identity_invalid', '链路清单身份或版本无效', 'manifest'));
    return result(failures, manifest);
  }
  if (!Array.isArray(manifest.sequence)
    || manifest.sequence.length !== ORDER.length
    || manifest.sequence.some((item, index) => item?.capabilityId !== ORDER[index])) {
    failures.push(failure('chain_order_invalid', '三技能顺序必须固定', 'sequence'));
  }
  for (const [index, item] of (manifest.sequence ?? []).entries()) {
    if (!validHash(item?.skillSha256)) {
      failures.push(failure('skill_hash_invalid', 'Skill必须绑定有效SHA-256', `sequence[${index}].skillSha256`));
    }
    if (!validHash(item?.formalAssetSha256) || !validHash(item?.candidateSha256)) {
      failures.push(failure('asset_hash_invalid', '正式资产与候选必须绑定有效SHA-256', `sequence[${index}]`));
    }
    if (!Number.isInteger(item?.version) || item.version < 1
      || !exactVersionRef(item?.formalAssetRef, item?.capabilityId, item?.version)
      || !exactSkillRef(item?.skillRef, item?.capabilityId)) {
      failures.push(failure('asset_ref_invalid', '链路必须使用精确版本资产和Skill路径', `sequence[${index}]`));
    }
  }
  for (const [name, binding] of Object.entries(manifest.dependencyBindings ?? {})) {
    const refs = [binding?.sourceRef, ...(binding?.sources ?? []).map((item) => item.sourceRef)]
      .filter((ref) => ref !== undefined);
    if (refs.some((ref) => !ref || /(^|\/)current(?:\.json)?$/u.test(ref) || /latest/u.test(ref))) {
      failures.push(failure(
        'ambiguous_dependency_ref',
        '下游依赖不得引用current或latest',
        `dependencyBindings.${name}`,
      ));
    }
  }
  if (manifest.rootIntegration?.rootRegistryModified !== false
    || manifest.rootIntegration?.status !== 'candidate') {
    failures.push(failure(
      'root_integration_overstated',
      '本组织只能提交根级集成候选',
      'rootIntegration',
    ));
  }
  return result(failures, manifest);
}

export async function validateOrganizationChain({
  projectRoot,
  enterpriseId,
  manifestPath,
} = {}) {
  const manifest = await readStrictJson(manifestPath, { label: 'organization chain manifest' });
  const base = validateOrganizationChainManifest(manifest);
  const failures = [...base.failures];
  if (manifest.enterpriseId !== enterpriseId) {
    failures.push(failure('enterprise_mismatch', '链路企业不匹配', 'enterpriseId'));
  }

  const config = await loadOrganizationConfig({ projectRoot });
  const status = new Map(config.coreSkills.map((item) => [item.id, item.status]));
  for (const item of manifest.sequence ?? []) {
    if (status.get(item.capabilityId) !== 'formal') {
      failures.push(failure('skill_not_formal', '链路能力尚未正式化', item.capabilityId));
      continue;
    }
    const absoluteFormal = resolveProjectRef(projectRoot, item.formalAssetRef);
    const absoluteSkill = resolveProjectRef(projectRoot, item.skillRef);
    const [formalRecord, actualFormalHash, actualSkillHash] = await Promise.all([
      readStrictJson(absoluteFormal, { label: `${item.capabilityId} formal asset` }),
      sha256File(absoluteFormal),
      sha256File(absoluteSkill),
    ]);
    if (actualFormalHash !== item.formalAssetSha256
      || formalRecord.candidateSha256 !== item.candidateSha256
      || formalRecord.enterpriseId !== enterpriseId
      || formalRecord.capabilityId !== item.capabilityId
      || formalRecord.version !== item.version) {
      failures.push(failure('formal_asset_drifted', '正式资产身份或哈希漂移', item.capabilityId));
    }
    if (actualSkillHash !== item.skillSha256) {
      failures.push(failure('skill_file_drifted', 'Skill文件哈希漂移', item.capabilityId));
    }
  }

  const byId = new Map((manifest.sequence ?? []).map((item) => [item.capabilityId, item]));
  const development = manifest.dependencyBindings?.talentDevelopment;
  const replication = manifest.dependencyBindings?.processReplication;
  if (!sameBinding(development, byId.get('talent-allocation'))) {
    failures.push(failure(
      'development_dependency_drifted',
      '人才培养未固定绑定人才配置正式资产',
      'dependencyBindings.talentDevelopment',
    ));
  }
  const replicationSources = new Map((replication?.sources ?? []).map((item) => [item.capabilityId, item]));
  if (!sameBinding(replicationSources.get('talent-allocation'), byId.get('talent-allocation'))
    || !sameBinding(replicationSources.get('talent-development'), byId.get('talent-development'))) {
    failures.push(failure(
      'replication_dependency_drifted',
      '流程复制未固定绑定两个上游正式资产',
      'dependencyBindings.processReplication',
    ));
  }
  return result(failures, manifest);
}

export function validateOrganizationV2Chain({
  invocation,
  plan,
  handoffs = [],
  quality,
  returnPackage,
} = {}) {
  const failures = [];
  const authorized = invocation?.allowedCapabilityChain ?? [];
  if (invocation?.schemaVersion !== 2
    || invocation?.primaryOrganization !== 'ai-organization-officer'
    || JSON.stringify(plan?.capabilitySequence) !== JSON.stringify(authorized)) {
    failures.push(failure(
      'v2_authorization_drifted',
      'V2计划必须与总控授权能力链一致',
      'plan.capabilitySequence',
    ));
  }
  if (invocation?.mode === 'single-skill' && plan?.capabilitySequence?.length !== 1) {
    failures.push(failure(
      'v2_single_skill_expanded',
      '单Skill任务不得自动扩链',
      'plan.capabilitySequence',
    ));
  }
  for (const [index, handoff] of handoffs.entries()) {
    if (handoff?.enterpriseId !== invocation?.enterpriseId
      || handoff?.businessProjectId !== invocation?.businessProjectId
      || handoff?.taskId !== invocation?.taskId
      || handoff?.status !== 'ready') {
      failures.push(failure('v2_handoff_identity_invalid', 'V2交接身份无效', `handoffs[${index}]`));
      continue;
    }
    for (const [bindingIndex, binding] of (handoff.bindings ?? []).entries()) {
      if (!Number.isInteger(binding.version)
        || binding.version < 1
        || !HASH.test(binding.sha256 ?? '')
        || /(^|\/)(current|latest)(\/|\.|$)/u.test(binding.sourceRef ?? '')) {
        failures.push(failure(
          'v2_handoff_binding_invalid',
          'V2交接必须固定精确版本与SHA-256',
          `handoffs[${index}].bindings[${bindingIndex}]`,
        ));
      }
    }
  }
  if (returnPackage?.status === 'completed' && quality?.ok !== true) {
    failures.push(failure(
      'v2_quality_not_passed',
      '完成回传必须通过四级质量验收',
      'quality',
    ));
  }
  if (returnPackage?.enterpriseId !== invocation?.enterpriseId
    || returnPackage?.businessProjectId !== invocation?.businessProjectId
    || returnPackage?.taskId !== invocation?.taskId) {
    failures.push(failure('v2_return_identity_invalid', 'V2回传身份无效', 'returnPackage'));
  }
  return result(failures, { invocation, plan, handoffs, quality, returnPackage });
}

function sameBinding(binding, sequenceItem) {
  return Boolean(binding
    && sequenceItem
    && binding.capabilityId === sequenceItem.capabilityId
    && binding.version === sequenceItem.version
    && binding.sourceRef === sequenceItem.formalAssetRef
    && binding.formalAssetSha256 === sequenceItem.formalAssetSha256
    && binding.candidateSha256 === sequenceItem.candidateSha256);
}

function exactVersionRef(ref, capabilityId, version) {
  return typeof ref === 'string'
    && ref.endsWith(`/assets/${capabilityId}/versions/${version}.json`)
    && !/(^|\/)(current|latest)(\/|\.|$)/u.test(ref);
}

function exactSkillRef(ref, capabilityId) {
  return typeof ref === 'string'
    && ref.endsWith(`/skills/${capabilityId}/SKILL.md`);
}

function resolveProjectRef(projectRoot, ref) {
  if (typeof ref !== 'string' || /^[A-Za-z]:|^[/\\]/u.test(ref)) {
    throw new Error('chain reference must be project-relative');
  }
  const normalized = ref.replaceAll('/', '\\');
  const absolute = `${projectRoot}\\${normalized}`.replaceAll('\\\\', '\\');
  const organizationPrefix = `${projectRoot}\\organizations\\ai-organization-officer\\`;
  if (!absolute.startsWith(organizationPrefix)) {
    throw new Error('chain reference escapes AI organization officer');
  }
  return absolute;
}

function validHash(value) {
  return HASH.test(value ?? '') && !/^([a-f0-9])\1{63}$/u.test(value);
}

function failure(code, message, path) {
  return { code, message, path };
}

function result(failures, manifest) {
  const unique = [...new Map(failures.map((item) => [`${item.path}|${item.code}`, item])).values()];
  unique.sort((left, right) => left.path.localeCompare(right.path) || left.code.localeCompare(right.code));
  return Object.freeze({ ok: unique.length === 0, failures: Object.freeze(unique), manifest });
}
