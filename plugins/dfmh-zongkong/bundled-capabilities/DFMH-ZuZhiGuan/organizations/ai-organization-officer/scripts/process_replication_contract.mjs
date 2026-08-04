const AUTOMATED_ATTENDANCE = /自动.{0,8}(处罚|奖惩|扣薪|认定缺勤|辞退)/u;
const AUTOMATED_PAYROLL = /自动.{0,8}(发薪|改工资|调薪|扣款|提交银行|报税)/u;
const EXTERNAL_WRITE = /(自动签.{0,4}合同|提交社保|提交公积金|银行付款|生产系统写入|正式发薪)/u;

export function validateProcessReplicationCandidate({
  candidate,
  task,
  enterpriseProfile,
  knowledgeContext,
  upstreamTalentAsset,
  upstreamDevelopmentAsset,
} = {}) {
  const failures = [];
  if (!candidate || typeof candidate !== 'object' || Array.isArray(candidate)) {
    return result([failure('candidate_missing', '流程复制候选必须是对象', 'candidate')]);
  }
  if (candidate.schemaVersion !== 1 || !Number.isInteger(candidate.version) || candidate.version < 1) {
    failures.push(failure('candidate_identity_invalid', '候选结构或版本无效', 'version'));
  }
  if (!task
    || task.capabilityId !== 'process-replication'
    || candidate.taskId !== task.taskId
    || candidate.enterpriseId !== task.enterpriseId
    || enterpriseProfile?.enterpriseId !== task.enterpriseId) {
    failures.push(failure('enterprise_task_mismatch', '企业、任务或能力不匹配', 'enterpriseId'));
  }
  if (!knowledgeContext
    || !['matched', 'no_hit', 'degraded'].includes(knowledgeContext.status)
    || task?.knowledgeStatus !== knowledgeContext?.status) {
    failures.push(failure('knowledge_preflight_incomplete', '流程复制前必须完成知识前置', 'knowledgeContext'));
  }
  if (knowledgeContext?.status === 'degraded' && !knowledgeContext.degradedReason?.trim()) {
    failures.push(failure('knowledge_degraded_reason_missing', '知识降级必须保留原因', 'knowledgeContext'));
  }

  if (!upstreamMatches(candidate.upstreamAssets?.talentAllocation, upstreamTalentAsset, 'talent-allocation')
    || !upstreamMatches(
      candidate.upstreamAssets?.talentDevelopment,
      upstreamDevelopmentAsset,
      'talent-development',
    )) {
    failures.push(failure(
      'upstream_asset_mismatch',
      '流程复制必须固定绑定同企业人才配置与人才培养正式资产及哈希',
      'upstreamAssets',
    ));
  }

  const diagnosis = candidate.processDiagnosis;
  if (!diagnosis?.targetSystem?.trim()
    || !diagnosis.objective?.trim()
    || !diagnosis.sourceScope?.trim()
    || !nonEmptyStrings(diagnosis.actualEvidenceRefs)
    || !nonEmptyStrings(diagnosis.writtenVsActual)
    || !nonEmptyStrings(diagnosis.gaps)) {
    failures.push(failure(
      'actual_process_evidence_missing',
      '必须还原实际流程并比较书面流程与真实执行',
      'processDiagnosis',
    ));
  }

  const processMap = candidate.processMap;
  if (!processMap?.trigger?.trim()
    || !nonEmptyStrings(processMap.inputs)
    || !nonEmptyStrings(processMap.participants)
    || !Array.isArray(processMap.steps)
    || processMap.steps.length === 0
    || processMap.steps.some((step) => (
      !step.id?.trim()
      || !step.action?.trim()
      || !step.owner?.trim()
      || !Array.isArray(step.collaborators)
      || !step.reviewer?.trim()
      || !nonEmptyStrings(step.tools)
      || !nonEmptyStrings(step.outputs)
      || !step.timeLimit?.trim()
      || !step.qualityStandard?.trim()
    ))
    || !Array.isArray(processMap.waits)
    || !Array.isArray(processMap.errorPoints)
    || !Array.isArray(processMap.exceptions)) {
    failures.push(failure('process_map_incomplete', '流程地图缺少关键执行字段', 'processMap'));
  }

  if (!Array.isArray(candidate.responsibilityMatrix)
    || candidate.responsibilityMatrix.length === 0
    || candidate.responsibilityMatrix.some((item) => (
      !item.activity?.trim()
      || !item.owner?.trim()
      || !Array.isArray(item.collaborators)
      || !item.reviewer?.trim()
      || !item.escalation?.trim()
    ))) {
    failures.push(failure(
      'responsibility_matrix_missing',
      '流程必须明确负责、协作、审核与升级责任',
      'responsibilityMatrix',
    ));
  }

  if (!Array.isArray(candidate.sops)
    || candidate.sops.length === 0
    || candidate.sops.some((sop) => (
      !sop.id?.trim()
      || !sop.purpose?.trim()
      || !sop.scope?.trim()
      || !nonEmptyStrings(sop.preconditions)
      || !nonEmptyStrings(sop.materials)
      || !nonEmptyStrings(sop.steps)
      || !nonEmptyStrings(sop.examples)
      || !nonEmptyStrings(sop.qualityStandards)
      || !nonEmptyStrings(sop.commonErrors)
      || !nonEmptyStrings(sop.exceptions)
      || !nonEmptyStrings(sop.checklist)
      || !sop.owner?.trim()
      || !sop.version?.trim()
      || Number.isNaN(Date.parse(sop.effectiveDate))
      || !nonEmptyStrings(sop.updateConditions)
    ))) {
    failures.push(failure('sop_incomplete', 'SOP结构不完整', 'sops'));
  }

  const approvals = candidate.formsAndApprovals;
  if (!nonEmptyStrings(approvals?.forms)
    || !nonEmptyStrings(approvals?.approvalSteps)
    || !nonEmptyStrings(approvals?.auditTrail)) {
    failures.push(failure('forms_and_approvals_incomplete', '表单、审批和审计轨迹不完整', 'formsAndApprovals'));
  }
  if (EXTERNAL_WRITE.test(approvals?.approvalSteps?.join(' ') ?? '')) {
    failures.push(failure(
      'unauthorized_external_write',
      '候选不得自动执行合同、社保、付款或生产写入',
      'formsAndApprovals.approvalSteps',
    ));
  }

  const knowledge = candidate.knowledgeBase;
  if (!nonEmptyStrings(knowledge?.structure)
    || !Array.isArray(knowledge?.entries)
    || knowledge.entries.length === 0
    || knowledge.entries.some((entry) => (
      !entry.id?.trim()
      || entry.enterpriseId !== candidate.enterpriseId
      || !entry.department?.trim()
      || !entry.owner?.trim()
      || !entry.sourceRef?.trim()
      || !nonEmptyStrings(entry.audience)
      || !nonEmptyStrings(entry.permissions)
      || !entry.version?.trim()
      || Number.isNaN(Date.parse(entry.effectiveDate))
      || !entry.reviewCycle?.trim()
      || !Array.isArray(entry.relatedRefs)
      || !Object.hasOwn(entry, 'replaces')
    ))
    || !knowledge.staleContentRule?.trim()) {
    failures.push(failure(
      'knowledge_metadata_incomplete',
      '知识库条目必须包含来源、权限、版本、生效与复核元数据',
      'knowledgeBase',
    ));
  }

  const attendance = candidate.attendanceSystem;
  if (!['template-only', 'not-applicable', 'active'].includes(attendance?.mode)
    || !attendance.applicability?.trim()
    || !nonEmptyStrings(attendance.rules)
    || !nonEmptyStrings(attendance.dataSources)
    || !nonEmptyStrings(attendance.validation)
    || !attendance.decisionBoundary?.includes('使用者最终决定')
    || AUTOMATED_ATTENDANCE.test(attendance.decisionBoundary)) {
    failures.push(failure(
      'automated_attendance_decision',
      '考勤只能计算、核验和建议，不得自动认定或处罚',
      'attendanceSystem',
    ));
  }
  if (attendance?.mode === 'active'
    && (attendance.pilot?.fullCycleCovered !== true
      || !Array.isArray(attendance.pilot?.unresolvedExceptions)
      || attendance.pilot.unresolvedExceptions.length > 0)) {
    failures.push(failure(
      'attendance_full_cycle_required',
      '真实考勤必须覆盖企业定义的完整周期且全部异常已确认',
      'attendanceSystem.pilot',
    ));
  }

  const payroll = candidate.payrollSystem;
  if (!['template-only', 'not-applicable', 'active'].includes(payroll?.mode)
    || !payroll.applicability?.trim()
    || !nonEmptyStrings(payroll.inputs)
    || !nonEmptyStrings(payroll.formulas)
    || !nonEmptyStrings(payroll.validation)
    || !nonEmptyStrings(payroll.separationOfDuties)
    || !payroll.employeeConfirmation?.trim()
    || !payroll.disputeProcess?.trim()
    || !payroll.decisionBoundary?.includes('使用者最终决定')
    || AUTOMATED_PAYROLL.test(payroll.decisionBoundary)) {
    failures.push(failure(
      'automated_payroll_action',
      '工资模块不得自动发薪、调薪、扣款或提交外部文件',
      'payrollSystem',
    ));
  }
  if (payroll?.mode === 'active'
    && (!payroll.region?.trim()
      || payroll.region === 'unknown'
      || !payroll.cycle?.trim()
      || payroll.cycle === 'unknown'
      || Number.isNaN(Date.parse(payroll.currentPolicyAsOf)))) {
    failures.push(failure(
      'current_policy_evidence_missing',
      '真实工资任务必须绑定地区、周期和当前政策核验日期',
      'payrollSystem.currentPolicyAsOf',
    ));
  }
  if (payroll?.mode === 'active'
    && (payroll.shadowRun?.completed !== true
      || !Array.isArray(payroll.shadowRun?.unexplainedDifferences)
      || payroll.shadowRun.unexplainedDifferences.length > 0)) {
    failures.push(failure(
      'payroll_shadow_run_required',
      '真实工资启用前必须完成影子核算且不存在无法解释的差异',
      'payrollSystem.shadowRun',
    ));
  }

  if (!nonEmptyStrings(candidate.employeeLifecycle?.stages)
    || !nonEmptyStrings(candidate.employeeLifecycle?.handoffs)
    || !candidate.employeeLifecycle?.decisionBoundary?.includes('使用者')) {
    failures.push(failure('employee_lifecycle_incomplete', '员工全周期与交接边界不完整', 'employeeLifecycle'));
  }
  const compliance = candidate.laborCompliance;
  if (compliance?.currentResearchRequired !== true
    || !nonEmptyStrings(compliance.requiredDimensions)
    || compliance.professionalReviewRequired !== true
    || compliance.legalAdviceProvided !== false
    || !compliance.sourceStandard?.trim()) {
    failures.push(failure(
      'legal_advice_overreach',
      '劳动合规模块必须要求当前核验和专业复核，且不得冒充法律意见',
      'laborCompliance',
    ));
  }

  const replicationPackage = candidate.replicationPackage;
  for (const field of [
    'conditions',
    'organizationModel',
    'staffing',
    'recruiting',
    'onboarding',
    'management',
    'sopRefs',
    'formRefs',
    'knowledgeRefs',
    'tools',
    'qualityControls',
    'launchConditions',
  ]) {
    if (!nonEmptyStrings(replicationPackage?.[field])) {
      failures.push(failure(
        'replication_package_incomplete',
        '新组织复制包缺少必要组成',
        `replicationPackage.${field}`,
      ));
      break;
    }
  }

  const pilot = candidate.pilotPlan;
  if (pilot?.required !== true
    || !pilot.scope?.trim()
    || !nonEmptyStrings(pilot.scenarios)
    || !nonEmptyStrings(pilot.successMetrics)
    || !pilot.rollbackPlan?.trim()
    || pilot.userApprovalRequired !== true) {
    failures.push(failure('pilot_required', '流程复制正式启用前必须试点并保留回退', 'pilotPlan'));
  }
  const version = candidate.versionGovernance;
  if (!version?.release?.trim()
    || version.nonOverwrite !== true
    || Number.isNaN(Date.parse(version.effectiveDate))
    || !version.reviewCycle?.trim()
    || !nonEmptyStrings(version.changeTriggers)) {
    failures.push(failure('version_governance_incomplete', '版本、生效、复核和变更触发不完整', 'versionGovernance'));
  }
  if (!nonEmptyObjects(candidate.evidenceIndex)
    || !Array.isArray(candidate.unknowns)
    || !Array.isArray(candidate.risks)
    || !nonEmptyObjects(candidate.decisionsRequired)) {
    failures.push(failure('evidence_and_decisions_incomplete', '证据、未知、风险或待决策项不完整', 'evidenceIndex'));
  }
  return result(failures);
}

function upstreamMatches(reference, asset, capabilityId) {
  return Boolean(reference
    && asset
    && asset.capabilityId === capabilityId
    && reference.capabilityId === capabilityId
    && asset.enterpriseId
    && reference.version === asset.version
    && reference.candidateSha256 === asset.candidateSha256
    && reference.formalAssetSha256 === asset.formalAssetSha256
    && /^[a-f0-9]{64}$/u.test(reference.candidateSha256 ?? '')
    && /^[a-f0-9]{64}$/u.test(reference.formalAssetSha256 ?? '')
    && reference.formalAssetRef?.trim());
}

function nonEmptyStrings(value) {
  return Array.isArray(value)
    && value.length > 0
    && value.every((item) => typeof item === 'string' && item.trim());
}

function nonEmptyObjects(value) {
  return Array.isArray(value)
    && value.length > 0
    && value.every((item) => item && typeof item === 'object' && !Array.isArray(item));
}

function failure(code, message, path) {
  return { code, message, path };
}

function result(failures) {
  const unique = [...new Map(failures.map((item) => [`${item.path}|${item.code}`, item])).values()];
  unique.sort((left, right) => left.path.localeCompare(right.path) || left.code.localeCompare(right.code));
  return Object.freeze({ ok: unique.length === 0, failures: Object.freeze(unique) });
}
