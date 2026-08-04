import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';

import { writeJsonAtomic } from '../../../scripts/feishu-commander/atomic_store.mjs';
import { diagnoseOrganizationFailure } from './organization_debug_engine.mjs';
import { buildEvidenceIndex } from './organization_evidence_engine.mjs';
import { buildOrganizationExecutionPlan } from './organization_execution_planner.mjs';
import { createOrganizationExecutionStore } from './organization_execution_store.mjs';
import {
  createSkillHandoff,
  createUpstreamChangeRequest,
} from './organization_handoff_engine.mjs';
import { validateOrganizationInvocationV2 } from './organization_invocation_v2.mjs';
import { evaluateOrganizationQuality } from './organization_quality_engine.mjs';
import { createOrganizationReturnPackage } from './organization_return_engine.mjs';
import { createOrganizationV2Workspace } from './organization_v2_workspace.mjs';

export async function createOrganizationV2Runtime({
  projectRoot,
  invocation,
  now = () => new Date(),
} = {}) {
  const call = validateOrganizationInvocationV2(invocation);
  const workspace = await createOrganizationV2Workspace({
    projectRoot,
    enterpriseId: call.enterpriseId,
    businessProjectId: call.businessProjectId,
    taskId: call.taskId,
  });
  const store = createOrganizationExecutionStore({ workspace, now });

  return Object.freeze({
    async initialize({ availableInputs = [] } = {}) {
      const plan = buildOrganizationExecutionPlan({ invocation: call, availableInputs, now });
      await writeSameOrNew(workspace.invocationFile, call, 'invocation');
      await writeSameOrNew(workspace.planFile, plan, 'plan');
      const execution = await store.create({
        schemaVersion: 2,
        enterpriseId: call.enterpriseId,
        businessProjectId: call.businessProjectId,
        taskId: call.taskId,
        planVersion: plan.planVersion,
        primarySkill: call.primarySkill,
        status: 'planning',
        revision: 1,
        currentStageId: plan.stages[0]?.id ?? 'context-lock',
        checkpoint: null,
        failureCounts: {},
        createdAt: plan.createdAt,
        updatedAt: plan.createdAt,
      });
      await writeSameOrNew(workspace.evidenceFile, buildEvidenceIndex({
        enterpriseId: call.enterpriseId,
        businessProjectId: call.businessProjectId,
        taskId: call.taskId,
        entries: [],
      }), 'evidence index');
      await writeSameOrNew(workspace.qualityFile, evaluateOrganizationQuality({
        evidenceReady: false,
        versionBindingsReady: call.pinnedInputs.length === 0,
        decisionBoundaryReady: call.decisionBoundary.length > 0,
        returnPackageReady: false,
      }), 'quality report');
      return Object.freeze({ workspace, plan, execution });
    },

    readExecution: () => store.read(),
    transition: (input) => store.transition(input),
    resume: (input) => store.resume(input),

    async saveEvidence(entries) {
      const evidence = buildEvidenceIndex({
        enterpriseId: call.enterpriseId,
        businessProjectId: call.businessProjectId,
        taskId: call.taskId,
        entries,
      });
      await writeJsonAtomic(workspace.evidenceFile, evidence);
      return evidence;
    },

    async evaluateQuality(input) {
      const quality = evaluateOrganizationQuality(input);
      await writeJsonAtomic(workspace.qualityFile, quality);
      return quality;
    },

    async diagnose(observation) {
      const execution = await store.read();
      const priorDiagnostics = await readJsonDirectory(workspace.debugRoot);
      const diagnostic = diagnoseOrganizationFailure({
        execution,
        observation,
        priorDiagnostics,
        now,
      });
      await writeJsonAtomic(
        path.join(workspace.debugRoot, `${diagnostic.diagnosticId}.json`),
        diagnostic,
      );
      return diagnostic;
    },

    async createHandoff(input) {
      const handoff = createSkillHandoff({
        enterpriseId: call.enterpriseId,
        businessProjectId: call.businessProjectId,
        taskId: call.taskId,
        ...input,
      });
      const fileName = `handoff-${String((await readdir(workspace.handoffRoot)).length + 1).padStart(3, '0')}.json`;
      await writeJsonAtomic(path.join(workspace.handoffRoot, fileName), handoff);
      return handoff;
    },

    async requestUpstreamChange(input) {
      const execution = await store.read();
      const request = createUpstreamChangeRequest({ execution, ...input });
      const fileName = `upstream-change-${String((await readdir(workspace.handoffRoot)).length + 1).padStart(3, '0')}.json`;
      await writeJsonAtomic(path.join(workspace.handoffRoot, fileName), request);
      return request;
    },

    async buildReturn(input) {
      const execution = await store.read();
      const result = createOrganizationReturnPackage({ execution, ...input });
      await writeJsonAtomic(workspace.returnFile, result);
      return result;
    },
  });
}

async function writeSameOrNew(filePath, value, label) {
  const existing = await readFile(filePath, 'utf8').catch((error) =>
    error?.code === 'ENOENT' ? null : Promise.reject(error));
  if (existing !== null) {
    if (JSON.stringify(JSON.parse(existing)) !== JSON.stringify(value)) {
      throw new Error(`${label} conflicts with existing task`);
    }
    return;
  }
  await writeJsonAtomic(filePath, value);
}

async function readJsonDirectory(directory) {
  const names = (await readdir(directory)).filter((name) => name.endsWith('.json')).sort();
  return Promise.all(names.map(async (name) =>
    JSON.parse(await readFile(path.join(directory, name), 'utf8'))));
}
