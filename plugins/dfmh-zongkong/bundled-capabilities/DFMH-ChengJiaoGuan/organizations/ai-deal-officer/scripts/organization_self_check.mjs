import { lstat, readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

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
  'contracts/customer-insight-candidate.schema.json',
  'contracts/deal-strategy-candidate.schema.json',
  'contracts/sales-training-candidate.schema.json',
  'contracts/deal-execution-plan.schema.json',
  'contracts/deal-task.schema.json',
  'contracts/deal-evidence-ledger.schema.json',
  'contracts/deal-diagnostic.schema.json',
  'templates/CUSTOMER_INSIGHT_CANDIDATE.json',
  'templates/DEAL_STRATEGY_CANDIDATE.json',
  'templates/SALES_TRAINING_CANDIDATE.json',
  'templates/DEAL_EXECUTION_PLAN.json',
  'templates/DEAL_TASK.json',
  'templates/DEAL_DIAGNOSTIC.json',
  'scripts/customer_insight.mjs',
  'scripts/deal_strategy.mjs',
  'scripts/sales_training.mjs',
  'scripts/project_workspace.mjs',
  'scripts/deal_planner.mjs',
  'scripts/deal_evidence_ledger.mjs',
  'scripts/deal_task_store.mjs',
  'scripts/deal_debugger.mjs',
  'scripts/artifact_dependency_guard.mjs',
  'scripts/customer_insight_workflow.mjs',
  'scripts/deal_skill_runtime.mjs',
  'scripts/organization_self_check.mjs',
  'scripts/run_all_tests.ps1',
  'workflows/CUSTOMER_INSIGHT_PILOT.md',
  'workflows/DEAL_STRATEGY_PILOT.md',
  'workflows/SALES_TRAINING_PILOT.md',
  'skills/README.md',
  'skills/customer-insight/SKILL.md',
  'skills/customer-insight/agents/openai.yaml',
  'skills/deal-strategy/SKILL.md',
  'skills/deal-strategy/agents/openai.yaml',
  'skills/sales-training/SKILL.md',
  'skills/sales-training/agents/openai.yaml',
  'tests/customer_insight_skill.test.mjs',
  'tests/project_workspace.test.mjs',
  'tests/deal_planner.test.mjs',
  'tests/deal_evidence_ledger.test.mjs',
  'tests/deal_task_store.test.mjs',
  'tests/deal_debugger.test.mjs',
  'tests/artifact_dependency_guard.test.mjs',
  'tests/customer_insight_workflow.test.mjs',
  'tests/customer_insight_e2e.test.mjs',
  'tests/CUSTOMER_INSIGHT_REAL_TASK_ACCEPTANCE.md',
  'tests/deal_strategy_skill.test.mjs',
  'tests/sales_training_skill.test.mjs',
  'tests/organization_runtime.test.mjs',
];

const SKILL_HEADINGS = [
  '## 适用场景',
  '## 输入',
  '## 固定步骤',
  '## 输出',
  '## 依赖',
  '## 质量检查',
  '## 异常处理',
  '## 重试条件',
  '## 停止条件',
  '## 示例',
  '## 版本记录',
];

export async function runOrganizationSelfCheck({ projectRoot } = {}) {
  const organizationRoot = path.join(projectRoot, 'organizations', 'ai-deal-officer');
  const issues = [];
  for (const relativePath of REQUIRED_FILES) {
    const details = await lstat(path.join(organizationRoot, ...relativePath.split('/'))).catch(() => null);
    if (!details?.isFile() || details.size === 0) {
      issues.push(`missing or empty file: ${relativePath}`);
    }
  }

  const config = await readJson(
    path.join(organizationRoot, 'config', 'organization.json'),
    issues,
    'config/organization.json',
  );
  if (config) {
    if (config.id !== 'ai-deal-officer'
      || config.status !== 'pilot'
      || config.acceptsFormalTasks !== false
      || config.rootControllerRegistration !== 'registered_designing'
      || config.formalTaskRouting !== 'fallback_existing') {
      issues.push('organization config overstates or misstates current maturity');
    }
    const expected = new Map([
      ['customer-insight', 'pilot'],
      ['deal-strategy', 'pilot'],
      ['sales-training', 'pilot'],
    ]);
    if (!Array.isArray(config.coreSkills) || config.coreSkills.length !== 3) {
      issues.push('organization config must contain exactly three core skills');
    } else {
      for (const item of config.coreSkills) {
        if (expected.get(item.id) !== item.status) {
          issues.push(`core skill status mismatch: ${item.id}`);
        }
      }
    }
  }

  const rootRegistry = await readJson(
    path.join(projectRoot, 'control-center', 'registries', 'organizations.json'),
    issues,
    'control-center/registries/organizations.json',
  );
  const rootDealOfficer = rootRegistry?.organizations?.find((item) => item.id === 'ai-deal-officer');
  if (!rootDealOfficer
    || rootDealOfficer.status !== 'designing'
    || rootDealOfficer.acceptsFormalTasks !== false) {
    issues.push('root registry must keep AI成交官 registered_designing and non-formal');
  }

  for (const skillId of ['customer-insight', 'deal-strategy', 'sales-training']) {
    const source = await readFile(
      path.join(organizationRoot, 'skills', skillId, 'SKILL.md'),
      'utf8',
    ).catch(() => '');
    if (!/^---\r?\nname: [a-z0-9-]+\r?\ndescription: Use when /u.test(source)) {
      issues.push(`skill frontmatter invalid: ${skillId}`);
    }
    for (const heading of SKILL_HEADINGS) {
      if (!source.includes(heading)) issues.push(`${skillId} missing heading: ${heading}`);
    }
    if (/TODO|TBD/u.test(source)) issues.push(`${skillId} contains unfinished markers`);
  }

  for (const relativePath of REQUIRED_FILES.filter((item) => (
    item.endsWith('.json') && (item.startsWith('contracts/') || item.startsWith('templates/'))
  ))) {
    await readJson(
      path.join(organizationRoot, ...relativePath.split('/')),
      issues,
      relativePath,
    );
  }

  for (const relativePath of REQUIRED_FILES.filter((item) => item.startsWith('scripts/'))) {
    const source = await readFile(
      path.join(organizationRoot, ...relativePath.split('/')),
      'utf8',
    ).catch(() => '');
    if (/['"`]outputs[\\/]/u.test(source)) {
      issues.push(`organization script must not write root outputs: ${relativePath}`);
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

async function readJson(filePath, issues, label) {
  try {
    return JSON.parse(await readFile(filePath, 'utf8'));
  } catch (error) {
    issues.push(`invalid JSON: ${label}: ${error.message}`);
    return null;
  }
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
      } else if (entry.isFile()) {
        files += 1;
      }
    }
  };
  await walk(root);
  return { files, directories };
}

if (process.argv[1]
  && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
  const result = await runOrganizationSelfCheck({ projectRoot });
  if (result.ok) {
    console.log(
      `PASS: AI deal officer self-check completed. Files=${result.files}, Directories=${result.directories}, Issues=0.`,
    );
  } else {
    for (const issue of result.issues) console.error(`FAIL: ${issue}`);
    process.exitCode = 1;
  }
}
