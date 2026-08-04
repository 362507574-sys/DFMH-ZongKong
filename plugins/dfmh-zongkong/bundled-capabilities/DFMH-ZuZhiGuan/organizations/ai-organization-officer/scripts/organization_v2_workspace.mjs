import { mkdir, readFile } from 'node:fs/promises';
import path from 'node:path';

import { createProjectPaths } from '../../../scripts/control-center/project_paths.mjs';

const TASK_ID = /^[0-9]{8}-[0-9]{3}-[a-z0-9-]{3,80}$/u;

export async function createOrganizationV2Workspace({
  projectRoot,
  enterpriseId,
  businessProjectId,
  taskId,
} = {}) {
  if (!TASK_ID.test(taskId ?? '')) throw new Error('taskId is invalid');
  const projectPaths = await createProjectPaths({ projectRoot });
  const projectFile = projectPaths.projectFile(enterpriseId, businessProjectId);
  const project = JSON.parse(await readFile(projectFile, 'utf8'));
  if (project.enterpriseId !== enterpriseId || project.businessProjectId !== businessProjectId) {
    throw new Error('business project identity mismatch');
  }
  if (['cancelled', 'archived'].includes(project.status)) {
    throw new Error(`business project is inactive: ${project.status}`);
  }
  const organizationWorkspace = projectPaths.organizationWorkspace(
    enterpriseId,
    businessProjectId,
    'ai-organization-officer',
  );
  const taskRoot = path.join(organizationWorkspace, 'tasks', taskId);
  const debugRoot = path.join(taskRoot, 'debug-records');
  const handoffRoot = path.join(taskRoot, 'handoffs');
  const decisionRoot = path.join(taskRoot, 'decisions');
  await Promise.all([
    taskRoot,
    path.join(taskRoot, 'candidates'),
    debugRoot,
    handoffRoot,
    decisionRoot,
  ].map((directory) => mkdir(directory, { recursive: true })));
  return Object.freeze({
    organizationWorkspace,
    taskRoot,
    invocationFile: path.join(taskRoot, 'invocation.json'),
    planFile: path.join(taskRoot, 'plan.json'),
    executionFile: path.join(taskRoot, 'execution.json'),
    timelineFile: path.join(taskRoot, 'execution-timeline.json'),
    evidenceFile: path.join(taskRoot, 'evidence-index.json'),
    qualityFile: path.join(taskRoot, 'quality-report.json'),
    debugRoot,
    handoffRoot,
    decisionRoot,
    returnFile: path.join(taskRoot, 'return-package.json'),
  });
}
