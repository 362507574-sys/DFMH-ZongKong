import { lstat } from 'node:fs/promises';
import path from 'node:path';

import {
  sha256File,
  writeJsonAtomic,
} from '../../../scripts/feishu-commander/atomic_store.mjs';
import { createOrganizationPaths } from './organization_paths.mjs';
import { readStrictJson } from './strict_json.mjs';

const CAPABILITIES = new Set([
  'talent-allocation',
  'talent-development',
  'process-replication',
]);

export async function promoteApprovedOrganizationAsset({
  projectRoot,
  task,
  candidatePath,
  decision,
  gateResult,
  accessEnvelope,
} = {}) {
  validateTaskAndDecision(task, decision);
  validateFormalWriteAccess(accessEnvelope, task.enterpriseId);
  if (!gateResult?.ok) {
    const codes = gateResult?.failures?.map((item) => item.code).filter(Boolean) ?? [];
    throw new Error(`candidate gate failed: ${codes.join(', ') || 'unknown_failure'}`);
  }

  const paths = await createOrganizationPaths({ projectRoot });
  const expectedCandidatePath = paths.capabilityCandidateFile(
    task.enterpriseId,
    task.taskId,
    task.capabilityId,
    decision.candidateVersion,
  );
  if (path.resolve(candidatePath) !== path.resolve(expectedCandidatePath)) {
    throw new Error('candidate path must stay in the current enterprise task');
  }

  const candidate = await readStrictJson(candidatePath, {
    label: `${task.capabilityId} candidate`,
  });
  const actualCandidateSha256 = await sha256File(candidatePath);
  if (actualCandidateSha256 !== decision.candidateSha256) {
    throw new Error('candidate hash mismatch with user decision');
  }
  if (candidate.version !== decision.candidateVersion
    || candidate.enterpriseId !== task.enterpriseId
    || candidate.taskId !== task.taskId) {
    throw new Error('candidate identity mismatch');
  }

  const formalPath = paths.enterpriseAssetVersion(
    task.enterpriseId,
    task.capabilityId,
    candidate.version,
  );
  if (await exists(formalPath)) {
    throw new Error('approved formal asset version cannot be overwritten');
  }
  const formalRecord = {
    schemaVersion: 1,
    enterpriseId: task.enterpriseId,
    taskId: task.taskId,
    capabilityId: task.capabilityId,
    version: candidate.version,
    candidateSha256: actualCandidateSha256,
    approval: decision,
    asset: candidate,
    archivedAt: decision.decidedAt,
  };
  await writeJsonAtomic(formalPath, formalRecord);
  const formalAssetSha256 = await sha256File(formalPath);
  await writeJsonAtomic(paths.enterpriseAssetCurrent(task.enterpriseId, task.capabilityId), {
    schemaVersion: 1,
    enterpriseId: task.enterpriseId,
    capabilityId: task.capabilityId,
    version: candidate.version,
    formalAssetSha256,
    updatedAt: decision.decidedAt,
  });

  const formalAssetRef = path.relative(projectRoot, formalPath).split(path.sep).join('/');
  const candidateRef = path.relative(projectRoot, candidatePath).split(path.sep).join('/');
  const upstreamAssetBindings = candidate.upstreamAssets
    ?? (candidate.upstreamTalentAsset
      ? { talentAllocation: candidate.upstreamTalentAsset }
      : {});
  const returnPackage = {
    schemaVersion: 1,
    parentTaskId: task.parentTaskId,
    enterpriseId: task.enterpriseId,
    primaryOrganization: 'ai-organization-officer',
    capabilityId: task.capabilityId,
    status: 'completed',
    businessProjectId: task.businessProjectId ?? null,
    projectIsolationMode: task.businessProjectId
      ? 'business-project-silo'
      : 'legacy-organization-build',
    candidateRef,
    candidateVersion: candidate.version,
    candidateSha256: actualCandidateSha256,
    approvalRef: task.decisionRef,
    approval: decision,
    upstreamAssetBindings,
    formalAssetRef,
    formalAssetSha256,
    evidenceRefs: candidate.evidenceIndex?.map((item) => item.ref).filter(Boolean) ?? [],
    risks: candidate.risks ?? [],
    unresolvedItems: candidate.unknowns ?? [],
    completedAt: decision.decidedAt,
  };
  await writeJsonAtomic(paths.returnPackageFile(task.enterpriseId, task.taskId), returnPackage);
  return Object.freeze(returnPackage);
}

function validateTaskAndDecision(task, decision) {
  if (!task || task.status !== 'approved') throw new Error('organization task must be approved');
  if (!CAPABILITIES.has(task.capabilityId)) throw new Error('unsupported organization capability');
  if (decision?.decision !== 'approve') throw new Error('user approval required before promotion');
  if (decision.enterpriseId !== task.enterpriseId
    || decision.taskId !== task.taskId
    || decision.capabilityId !== task.capabilityId) {
    throw new Error('promotion enterprise, task or capability mismatch');
  }
  if (!Number.isInteger(decision.candidateVersion) || decision.candidateVersion < 1) {
    throw new Error('approved candidate version is invalid');
  }
  if (!/^[a-f0-9]{64}$/u.test(decision.candidateSha256 ?? '')) {
    throw new Error('approved candidate hash is invalid');
  }
  if (!decision.decidedBy?.trim() || !decision.decisionText?.trim()
    || !decision.scope?.trim() || Number.isNaN(Date.parse(decision.decidedAt))) {
    throw new Error('complete user decision evidence is required');
  }
}

function validateFormalWriteAccess(envelope, enterpriseId) {
  const scope = 'organization.formal.write';
  if (!envelope || envelope.enterpriseId !== enterpriseId) {
    throw new Error('formal write enterprise mismatch');
  }
  if (envelope.deniedScopes?.includes(scope)) throw new Error('formal write scope is denied');
  if (!envelope.allowedScopes?.includes(scope)) throw new Error('formal write scope is missing');
  if (envelope.expiresAt && Date.parse(envelope.expiresAt) <= Date.now()) {
    throw new Error('formal write access expired');
  }
}

async function exists(filePath) {
  return Boolean(await lstat(filePath).catch((error) => {
    if (error?.code === 'ENOENT') return null;
    throw error;
  }));
}
