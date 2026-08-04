import { lstat, readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { loadOrganizationConfig } from './organization_config.mjs';
import { validateOrganizationChain } from './organization_chain_validator.mjs';
import { readStrictJson } from './strict_json.mjs';
import { sha256File } from '../../../scripts/feishu-commander/atomic_store.mjs';

const REQUIRED_FILES = [
  'AGENTS.md',
  'ORGANIZATION.md',
  'ORGANIZATION_OVERVIEW.md',
  'WORKFLOWS.md',
  'USER_GUIDE.md',
  'DECISIONS.md',
  'CHANGELOG.md',
  'TROUBLESHOOTING.md',
  'ENVIRONMENT.md',
  'config/organization.json',
  'contracts/enterprise-profile.schema.json',
  'contracts/organization-task.schema.json',
  'contracts/collaboration-request.schema.json',
  'contracts/collaboration-result.schema.json',
  'contracts/talent-allocation-candidate.schema.json',
  'contracts/talent-development-candidate.schema.json',
  'contracts/process-replication-candidate.schema.json',
  'contracts/organization-invocation-v2.schema.json',
  'contracts/organization-execution-v2.schema.json',
  'contracts/upstream-change-request-v2.schema.json',
  'contracts/return-package-v2.schema.json',
  'integration/root-registration-candidate.json',
  'integration/CONTROL_CENTER_HANDOFF.md',
  'scripts/strict_json.mjs',
  'scripts/organization_paths.mjs',
  'scripts/organization_config.mjs',
  'scripts/enterprise_store.mjs',
  'scripts/organization_task_store.mjs',
  'scripts/knowledge_preflight_adapter.mjs',
  'scripts/collaboration_contract.mjs',
  'scripts/talent_allocation_contract.mjs',
  'scripts/talent_allocation_gate.mjs',
  'scripts/talent_development_contract.mjs',
  'scripts/talent_development_gate.mjs',
  'scripts/process_replication_contract.mjs',
  'scripts/process_replication_gate.mjs',
  'scripts/organization_asset_promotion.mjs',
  'scripts/organization_chain_validator.mjs',
  'scripts/organization_v2_workspace.mjs',
  'scripts/organization_invocation_v2.mjs',
  'scripts/organization_execution_planner.mjs',
  'scripts/organization_execution_store.mjs',
  'scripts/organization_evidence_engine.mjs',
  'scripts/organization_quality_engine.mjs',
  'scripts/organization_debug_engine.mjs',
  'scripts/organization_handoff_engine.mjs',
  'scripts/organization_return_engine.mjs',
  'scripts/organization_v2_runtime.mjs',
  'workflows/TALENT_ALLOCATION_PILOT.md',
  'workflows/TALENT_DEVELOPMENT_PILOT.md',
  'workflows/PROCESS_REPLICATION_PILOT.md',
  'templates/ENTERPRISE_ORGANIZATION_PROFILE.json',
  'templates/ORGANIZATION_TASK.json',
  'templates/TALENT_ALLOCATION_CANDIDATE.json',
  'templates/TALENT_DEVELOPMENT_CANDIDATE.json',
  'templates/PROCESS_REPLICATION_CANDIDATE.json',
  'templates/ORGANIZATION_INVOCATION_V2.json',
  'templates/ORGANIZATION_EXECUTION_V2.json',
  'templates/UPSTREAM_CHANGE_REQUEST_V2.json',
  'templates/RETURN_PACKAGE_V2.json',
  'enterprises/README.md',
  'tasks/README.md',
  'temp/foundation-baseline.json',
  'temp/phase-1-baseline.json',
  'temp/README.md',
  'skills/README.md',
  'skills/talent-allocation/SKILL.md',
  'skills/talent-allocation/agents/openai.yaml',
  'skills/talent-development/SKILL.md',
  'skills/talent-development/agents/openai.yaml',
  'skills/process-replication/SKILL.md',
  'skills/process-replication/agents/openai.yaml',
  'enterprises/ai-digital-employee-control-center/assets/organization-chain/versions/1.json',
  'enterprises/ai-digital-employee-control-center/assets/organization-chain/versions/2.json',
  'enterprises/ai-digital-employee-control-center/assets/organization-chain/current.json',
];

export async function runOrganizationSelfCheck({ projectRoot } = {}) {
  const organizationRoot = path.join(
    projectRoot,
    'organizations',
    'ai-organization-officer',
  );
  const issues = [];
  for (const relative of REQUIRED_FILES) {
    const details = await lstat(path.join(organizationRoot, relative)).catch(() => null);
    if (!details?.isFile() || details.size === 0) issues.push(`missing or empty file: ${relative}`);
  }

  let config;
  try {
    config = await loadOrganizationConfig({ projectRoot });
  } catch (error) {
    issues.push(`organization config invalid: ${error.message}`);
    try {
      const rawConfig = await readStrictJson(
        path.join(organizationRoot, 'config', 'organization.json'),
        { label: 'organization config audit' },
      );
      if (rawConfig.coreSkills?.some((item) => item.status !== 'formal')) {
        issues.push('all three organization skills must be formal after complete-chain validation');
      }
    } catch {
      // The primary configuration error already preserves the actionable evidence.
    }
  }
  if (config) {
    if (config.coreSkills.some((item) => item.status !== 'formal')) {
      issues.push('all three organization skills must be formal after complete-chain validation');
    }
    if (config.coreSkills.some((item) => item.id.startsWith('public.'))) {
      issues.push('public skills must not enter coreSkills');
    }
  }

  const charter = await readText(path.join(organizationRoot, 'ORGANIZATION.md'));
  if (!/不修改.*总控根级路由/u.test(charter)) issues.push('charter must state 不修改总控根级路由');
  if (!/不直接写根级`outputs\/`/u.test(charter)) issues.push('charter must forbid root outputs writes');
  for (const skill of ['人才配置', '人才培养', '流程复制']) {
    if (!charter.includes(skill)) issues.push(`charter is missing core skill: ${skill}`);
  }

  const workflow = await readText(path.join(organizationRoot, 'workflows', 'TALENT_ALLOCATION_PILOT.md'));
  for (const expected of ['飞书知识前置', '使用者决策', '小范围试运行', '正式晋级']) {
    if (!workflow.includes(expected)) issues.push(`TALENT_ALLOCATION_PILOT missing: ${expected}`);
  }
  const developmentWorkflow = await readText(
    path.join(organizationRoot, 'workflows', 'TALENT_DEVELOPMENT_PILOT.md'),
  );
  for (const expected of ['飞书知识前置', '岗位能力模型', '实战', '使用者决策', '复训']) {
    if (!developmentWorkflow.includes(expected)) {
      issues.push(`TALENT_DEVELOPMENT_PILOT missing: ${expected}`);
    }
  }
  const replicationWorkflow = await readText(
    path.join(organizationRoot, 'workflows', 'PROCESS_REPLICATION_PILOT.md'),
  );
  for (const expected of ['飞书知识前置', '真实流程', 'SOP', '考勤', '工资', '组织复制包', '试点']) {
    if (!replicationWorkflow.includes(expected)) {
      issues.push(`PROCESS_REPLICATION_PILOT missing: ${expected}`);
    }
  }

  for (const relative of REQUIRED_FILES.filter((item) => (
    item.endsWith('.json') && item.startsWith('contracts/')
  ))) {
    try {
      await readStrictJson(path.join(organizationRoot, relative), { label: relative });
    } catch (error) {
      issues.push(`${relative} invalid: ${error.message}`);
    }
  }

  try {
    const candidate = await readStrictJson(
      path.join(organizationRoot, 'integration', 'root-registration-candidate.json'),
      { label: 'root registration candidate' },
    );
    if (candidate.rootControllerRegistration !== 'registered_operational'
      || candidate.formalTaskRouting !== 'direct'
      || candidate.peerOrganizationCalls !== 'contract_only'
      || candidate.acceptsFormalTasks !== true
      || candidate.localReadiness !== 'operational-v2'
      || candidate.activationRequiresControlCenter !== false) {
      issues.push('root registration candidate does not match operational V2 activation');
    }
    const updates = new Map(candidate.coreSkillStatusUpdates?.map((item) => [item.id, item.status]));
    if (['talent-allocation', 'talent-development', 'process-replication'].some(
      (skill) => updates.get(skill) !== 'formal',
    )) {
      issues.push('root registration candidate must declare all three locally validated skills formal');
    }
    const chainPath = path.join(
      organizationRoot,
      'enterprises',
      'ai-digital-employee-control-center',
      'assets',
      'organization-chain',
      'versions',
      '2.json',
    );
    const chain = await validateOrganizationChain({
      projectRoot,
      enterpriseId: 'ai-digital-employee-control-center',
      manifestPath: chainPath,
    });
    if (!chain.ok) issues.push(`organization chain invalid: ${JSON.stringify(chain.failures)}`);
    if (candidate.chainManifestSha256 !== await sha256File(chainPath)) {
      issues.push('root registration candidate chain manifest hash drifted');
    }
  } catch (error) {
    issues.push(`root registration candidate invalid: ${error.message}`);
  }

  const scriptFiles = REQUIRED_FILES.filter((item) => item.startsWith('scripts/'));
  for (const relative of scriptFiles) {
    const source = await readText(path.join(organizationRoot, relative));
    if (/['"`]outputs[\\/'"`]/u.test(source)) {
      issues.push(`organization script must not write root outputs: ${relative}`);
    }
  }

  const counts = await countTree(organizationRoot);
  return Object.freeze({
    ok: issues.length === 0,
    files: counts.files,
    directories: counts.directories,
    issues: Object.freeze(issues.sort()),
  });
}

async function countTree(root) {
  let files = 0;
  let directories = 1;
  const walk = async (directory) => {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const target = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        directories += 1;
        await walk(target);
      } else if (entry.isFile()) files += 1;
    }
  };
  await walk(root);
  return { files, directories };
}

async function readText(filePath) {
  return readFile(filePath, 'utf8').catch(() => '');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
  const result = await runOrganizationSelfCheck({ projectRoot });
  if (result.ok) {
    console.log(
      `PASS: AI organization officer self-check completed. Files=${result.files}, Directories=${result.directories}, Issues=0.`,
    );
  } else {
    for (const issue of result.issues) console.error(`FAIL: ${issue}`);
    process.exitCode = 1;
  }
}
