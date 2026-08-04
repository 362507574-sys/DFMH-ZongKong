import { lstat, mkdir, readFile, realpath } from 'node:fs/promises';
import path from 'node:path';

import { requireSafeId } from '../../../scripts/control-center/project_contract.mjs';
import { createProjectPaths } from '../../../scripts/control-center/project_paths.mjs';

const ORGANIZATION_ID = 'ai-deal-officer';

export async function createDealProjectWorkspace({
  projectRoot,
  enterpriseId,
  businessProjectId,
  taskId,
} = {}) {
  const safeTaskId = requireSafeId(taskId, 'taskId');
  const projectPaths = await createProjectPaths({ projectRoot });
  const businessProjectRoot = projectPaths.projectRoot(enterpriseId, businessProjectId);
  const canonicalProject = await realpath(businessProjectRoot).catch((error) => {
    throw new Error(`business project does not exist: ${error.message}`, { cause: error });
  });
  if (!(await lstat(canonicalProject)).isDirectory()) {
    throw new Error('business project must be a directory');
  }
  await assertProjectIdentity({
    businessProjectRoot: canonicalProject,
    enterpriseId,
    businessProjectId,
  });

  const organizationRoot = projectPaths.organizationWorkspace(
    enterpriseId,
    businessProjectId,
    ORGANIZATION_ID,
  );
  const tasksRoot = path.join(organizationRoot, 'tasks');
  await ensureRegularDirectory(organizationRoot);
  await ensureRegularDirectory(tasksRoot);

  const taskRoot = path.join(tasksRoot, safeTaskId);
  const existingTask = await lstat(taskRoot).catch((error) => {
    if (error?.code === 'ENOENT') return null;
    throw error;
  });
  if (existingTask?.isSymbolicLink()) {
    throw new Error('deal task workspace must not be symbolic');
  }
  if (existingTask && !existingTask.isDirectory()) {
    throw new Error('deal task workspace must be a regular directory');
  }
  await mkdir(taskRoot, { recursive: true });

  const canonicalTask = await realpath(taskRoot);
  assertWithin(canonicalProject, canonicalTask, 'deal task workspace escapes business project');

  const result = {
    projectRoot: canonicalProject,
    organizationRoot,
    taskRoot,
    planFile: path.join(taskRoot, 'plans', 'execution-plan.json'),
    taskFile: path.join(taskRoot, 'task.json'),
    evidenceLedgerFile: path.join(taskRoot, 'evidence', 'ledger.json'),
    candidatesRoot: path.join(taskRoot, 'candidates'),
    diagnosticsRoot: path.join(taskRoot, 'diagnostics'),
    reviewsRoot: path.join(taskRoot, 'reviews'),
  };
  for (const directory of [
    path.dirname(result.planFile),
    path.dirname(result.evidenceLedgerFile),
    result.candidatesRoot,
    result.diagnosticsRoot,
    result.reviewsRoot,
  ]) {
    await ensureRegularDirectory(directory);
    assertWithin(canonicalTask, await realpath(directory), 'deal task child path escapes task workspace');
  }
  return Object.freeze(result);
}

async function assertProjectIdentity({
  businessProjectRoot,
  enterpriseId,
  businessProjectId,
}) {
  const projectFile = path.join(businessProjectRoot, 'project.json');
  const project = JSON.parse(await readFile(projectFile, 'utf8').catch((error) => {
    throw new Error(`business project identity does not exist: ${error.message}`, { cause: error });
  }));
  if (project.enterpriseId !== enterpriseId || project.businessProjectId !== businessProjectId) {
    throw new Error('business project identity does not match requested project');
  }
}

async function ensureRegularDirectory(directory) {
  const existing = await lstat(directory).catch((error) => {
    if (error?.code === 'ENOENT') return null;
    throw error;
  });
  if (existing?.isSymbolicLink()) throw new Error(`directory must not be symbolic: ${directory}`);
  if (existing && !existing.isDirectory()) throw new Error(`path must be a directory: ${directory}`);
  if (!existing) await mkdir(directory, { recursive: true });
  const created = await lstat(directory);
  if (!created.isDirectory() || created.isSymbolicLink()) {
    throw new Error(`directory must be regular: ${directory}`);
  }
}

function assertWithin(base, candidate, message) {
  const relative = path.relative(path.resolve(base), path.resolve(candidate));
  if (relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
    throw new Error(message);
  }
}
