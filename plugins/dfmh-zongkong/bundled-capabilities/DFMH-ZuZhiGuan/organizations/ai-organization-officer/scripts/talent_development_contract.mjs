const PERSONNEL_ACTION = /自动.{0,8}(转正|晋升|降级|降职|处罚|辞退|调薪)|考试不合格.{0,8}(辞退|降级|处罚)/u;
const DIRECT_HIGH_IMPACT = /(直接|立即|系统).{0,8}(淘汰|解雇|解除劳动关系|解除劳动合同|辞退|降职|调岗|调薪|处罚)/u;
const OVERREACH = /所有问题.*(培训|能力)|都是员工不会|一律.*能力/u;

export function validateTalentDevelopmentCandidate({
  candidate,
  task,
  enterpriseProfile,
  knowledgeContext,
  upstreamTalentAsset,
} = {}) {
  const failures = [];
  if (!candidate || typeof candidate !== 'object' || Array.isArray(candidate)) {
    return result([failure('candidate_missing', '人才培养候选必须是对象', 'candidate')]);
  }
  if (candidate.schemaVersion !== 1 || !Number.isInteger(candidate.version) || candidate.version < 1) {
    failures.push(failure('candidate_identity_invalid', '候选版本或结构版本无效', 'version'));
  }
  if (!task
    || task.capabilityId !== 'talent-development'
    || candidate.taskId !== task.taskId
    || candidate.enterpriseId !== task.enterpriseId
    || enterpriseProfile?.enterpriseId !== task.enterpriseId) {
    failures.push(failure('enterprise_task_mismatch', '企业、任务或能力不匹配', 'enterpriseId'));
  }
  if (!knowledgeContext
    || !['matched', 'no_hit', 'degraded'].includes(knowledgeContext.status)
    || task?.knowledgeStatus !== knowledgeContext?.status) {
    failures.push(failure('knowledge_preflight_incomplete', '人才培养前必须完成知识前置', 'knowledgeContext'));
  }
  if (knowledgeContext?.status === 'degraded' && !knowledgeContext.degradedReason?.trim()) {
    failures.push(failure('knowledge_degraded_reason_missing', '知识降级必须保留原因', 'knowledgeContext.degradedReason'));
  }

  const upstream = candidate.upstreamTalentAsset;
  if (!upstreamTalentAsset
    || upstreamTalentAsset.capabilityId !== 'talent-allocation'
    || upstreamTalentAsset.enterpriseId !== candidate.enterpriseId
    || upstream?.capabilityId !== 'talent-allocation'
    || upstream?.version !== upstreamTalentAsset.version
    || upstream?.candidateSha256 !== upstreamTalentAsset.candidateSha256
    || upstream?.roleId !== candidate.developmentDiagnosis?.targetRoleId
    || !upstreamTalentAsset.asset?.jobProfiles?.some((item) => item.id === upstream?.roleId)) {
    failures.push(failure(
      'upstream_talent_asset_mismatch',
      '人才培养必须绑定同企业已批准岗位标准及其哈希',
      'upstreamTalentAsset',
    ));
  }

  const diagnosis = candidate.developmentDiagnosis;
  if (!diagnosis?.trainingNeeded
    || !diagnosis.trainingJustification?.trim()
    || !Array.isArray(diagnosis.evidenceRefs)
    || diagnosis.evidenceRefs.length === 0) {
    failures.push(failure('development_diagnosis_incomplete', '培养需求诊断和依据不完整', 'developmentDiagnosis'));
  }
  const rootCause = diagnosis?.rootCauseAnalysis;
  if (!rootCause
    || ['capability', 'management', 'process', 'resource', 'motivation'].some(
      (key) => !Array.isArray(rootCause[key]),
    )
    || OVERREACH.test(`${diagnosis?.trainingJustification ?? ''} ${rootCause?.capability?.join(' ') ?? ''}`)) {
    failures.push(failure(
      'training_root_cause_overreach',
      '不能把所有问题一律归因于员工能力或培训',
      'developmentDiagnosis.rootCauseAnalysis',
    ));
  }

  if (!candidate.learnerScope?.roleId
    || candidate.learnerScope.roleId !== upstream?.roleId
    || !Array.isArray(candidate.learnerScope.personRefs)) {
    failures.push(failure('learner_scope_invalid', '培养对象必须与批准岗位一致', 'learnerScope'));
  }
  if (!Array.isArray(candidate.capabilityModel) || candidate.capabilityModel.length === 0
    || candidate.capabilityModel.some((item) => (
      !item.id?.trim()
      || !item.name?.trim()
      || !item.targetLevel?.trim()
      || !nonEmpty(item.observableBehaviors)
      || !nonEmpty(item.evidenceRequired)
    ))) {
    failures.push(failure('capability_model_incomplete', '岗位能力模型缺少可观察行为或证据', 'capabilityModel'));
  }
  if (!nonEmpty(candidate.objectives)) {
    failures.push(failure('development_objectives_missing', '培养目标不能为空', 'objectives'));
  }
  if (!Array.isArray(candidate.modules) || candidate.modules.length === 0
    || candidate.modules.some((item) => (
      !item.id?.trim()
      || !item.title?.trim()
      || !item.objective?.trim()
      || !nonEmpty(item.materials)
      || !item.demonstration?.trim()
      || !item.practice?.trim()
      || !item.workTask?.trim()
      || !nonEmpty(item.commonErrors)
      || !nonEmpty(item.assessmentCriteria)
    ))) {
    failures.push(failure(
      'module_practice_incomplete',
      '每个课程模块必须包含示范、练习、实战、错误案例和评分标准',
      'modules',
    ));
  }
  if (!candidate.supportPlan?.mentorRole?.trim()
    || !candidate.supportPlan?.feedbackCadence?.trim()
    || !nonEmpty(candidate.supportPlan?.resources)) {
    failures.push(failure('support_plan_incomplete', '导师、反馈周期和资源不能为空', 'supportPlan'));
  }

  const assessment = candidate.assessmentPlan;
  if (!assessment
    || !nonEmpty(assessment.methods)
    || !nonEmpty(assessment.evidenceRequired)
    || !assessment.passRule?.trim()) {
    failures.push(failure('assessment_plan_incomplete', '评估方法、证据和通过规则不完整', 'assessmentPlan'));
  }
  if (assessment?.noPermanentLabel !== true
    || (assessment?.methods?.length ?? 0) < 2
    || /永久|终身|一次考试定/u.test(assessment?.decisionBoundary ?? '')) {
    failures.push(failure(
      'single_assessment_permanent_label',
      '单次考试不能形成永久能力标签',
      'assessmentPlan.noPermanentLabel',
    ));
  }
  const decisionBoundary = assessment?.decisionBoundary ?? '';
  const expresslyForbidsAutomation = /不自动|不得自动|不会自动/u.test(decisionBoundary);
  if (!decisionBoundary.includes('使用者最终决定')
    || DIRECT_HIGH_IMPACT.test(decisionBoundary)
    || (PERSONNEL_ACTION.test(decisionBoundary) && !expresslyForbidsAutomation)) {
    failures.push(failure(
      'automated_personnel_decision',
      '培养结果不得自动触发人员处理',
      'assessmentPlan.decisionBoundary',
    ));
  }

  if (!candidate.certification?.threshold?.trim()
    || !candidate.certification?.approver?.trim()
    || !nonEmpty(candidate.certification?.retrainingConditions)) {
    failures.push(failure('certification_incomplete', '认证阈值、批准人和复训条件不完整', 'certification'));
  }
  if (!candidate.growthPath?.currentLevel?.trim()
    || !candidate.growthPath?.targetLevel?.trim()
    || !nonEmpty(candidate.growthPath?.milestones)
    || !nonEmpty(candidate.growthPath?.alternativePaths)) {
    failures.push(failure('growth_path_incomplete', '成长路径与替代发展路径不完整', 'growthPath'));
  }
  if (!nonEmpty(candidate.operations?.metrics)
    || !candidate.operations?.reviewCycle?.trim()
    || !candidate.operations?.staleContentRule?.trim()) {
    failures.push(failure('development_operations_incomplete', '培养运营指标和内容复核规则不完整', 'operations'));
  }
  if (!nonEmpty(candidate.evidenceIndex)
    || !Array.isArray(candidate.unknowns)
    || !Array.isArray(candidate.risks)
    || !nonEmpty(candidate.decisionsRequired)) {
    failures.push(failure('evidence_and_decisions_incomplete', '证据、未知、风险或待决策项不完整', 'evidenceIndex'));
  }
  if (!nonEmpty(candidate.downstreamBrief?.processReplication?.needs)) {
    failures.push(failure(
      'process_replication_brief_missing',
      '人才培养候选必须形成流程复制下游简报',
      'downstreamBrief.processReplication',
    ));
  }
  return result(failures);
}

function nonEmpty(value) {
  return Array.isArray(value) && value.length > 0 && value.every(
    (item) => typeof item === 'string' ? item.trim().length > 0 : Boolean(item),
  );
}

function failure(code, message, path) {
  return { code, message, path };
}

function result(failures) {
  failures.sort((left, right) => left.path.localeCompare(right.path) || left.code.localeCompare(right.code));
  return Object.freeze({ ok: failures.length === 0, failures: Object.freeze(failures) });
}
