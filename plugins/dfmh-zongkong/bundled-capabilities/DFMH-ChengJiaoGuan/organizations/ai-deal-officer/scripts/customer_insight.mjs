const KNOWLEDGE_STATUSES = new Set(['matched', 'no_hit', 'degraded']);
const FIT_STATUSES = new Set(['fit', 'not_fit', 'evidence_insufficient']);
const DEAL_STAGES = new Set([
  'unqualified',
  'initial_contact',
  'discovery',
  'fit_confirmed',
  'value_alignment',
  'objection_resolution',
  'decision',
  'won',
  'lost',
  'paused',
  'handoff',
]);
const PROHIBITED = /100%成交|保证成交|稳赚|无风险|必须购买|逼单|恐吓|羞辱/u;

export function validateCustomerInsightCandidate({ candidate, context } = {}) {
  const failures = [];
  const add = (code, message, path) => failures.push({ code, message, path });
  if (!isObject(candidate)) {
    add('candidate_invalid', '客户洞察候选必须是对象', '$');
    return result(failures);
  }
  if (candidate.schemaVersion !== 1 || candidate.capabilityId !== 'customer-insight') {
    add('candidate_identity_invalid', '候选版本或技能身份错误', 'capabilityId');
  }
  if (candidate.enterpriseId !== context?.enterpriseId) {
    add('enterprise_mismatch', '候选与当前企业不一致', 'enterpriseId');
  }
  if (candidate.businessProjectId !== context?.businessProjectId) {
    add('business_project_mismatch', '候选与当前业务项目不一致', 'businessProjectId');
  }
  if (candidate.taskId !== context?.taskId) {
    add('task_mismatch', '候选与当前任务不一致', 'taskId');
  }
  if (!isExactPlanRef(candidate.planRef)
    || candidate.planRef.planId !== context?.expectedPlanRef?.planId
    || candidate.planRef.version !== context?.expectedPlanRef?.version
    || candidate.planRef.sha256 !== context?.expectedPlanRef?.sha256) {
    add('plan_ref_invalid', '客户洞察必须绑定当前精确计划版本与哈希', 'planRef');
  }
  if (!Number.isInteger(candidate.projectContextVersion)
    || candidate.projectContextVersion !== context?.projectContextVersion) {
    add(
      'project_context_version_mismatch',
      '客户洞察必须绑定当前项目上下文版本',
      'projectContextVersion',
    );
  }
  if (!Number.isInteger(candidate.evidenceLedgerRevision)
    || candidate.evidenceLedgerRevision < 1
    || candidate.evidenceLedgerRevision !== context?.evidenceLedgerRevision) {
    add(
      'evidence_ledger_revision_mismatch',
      '客户洞察必须绑定当前非空证据账本版本',
      'evidenceLedgerRevision',
    );
  }
  for (const key of ['beforeExecution', 'duringExecution', 'afterExecution']) {
    if (!/^diagnostics\/[a-z0-9-]+\.json$/u.test(candidate.debugCheckpoints?.[key] ?? '')) {
      add(
        'debug_checkpoint_invalid',
        '三个调试检查点必须完整且位于诊断目录',
        `debugCheckpoints.${key}`,
      );
    }
  }
  if (!Array.isArray(candidate.sourceCustomerRefs)
    || candidate.sourceCustomerRefs.length === 0
    || candidate.sourceCustomerRefs.some((customerRef) => (
      !context?.allowedCustomerRefs?.includes(customerRef)
    ))
    || !candidate.sourceCustomerRefs.includes(candidate.customerRef)) {
    add(
      'source_customer_out_of_scope',
      '客户洞察只能使用当前授权客户范围',
      'sourceCustomerRefs',
    );
  }
  if (!KNOWLEDGE_STATUSES.has(context?.knowledgeStatus)) {
    add('knowledge_preflight_incomplete', '飞书知识前置尚未完成', 'knowledgeStatus');
  }
  for (const scope of ['deal.customer.read', 'deal.candidate.write']) {
    if (!context?.allowedScopes?.includes(scope)) {
      add('access_scope_missing', `缺少权限：${scope}`, 'allowedScopes');
    }
  }
  if (!isObject(candidate.customerProfile)) {
    add('customer_profile_missing', '缺少客户画像', 'customerProfile');
  }
  if (!Array.isArray(candidate.buyingMotivations) || candidate.buyingMotivations.length === 0) {
    add('buying_motivations_missing', '至少需要一项购买动机', 'buyingMotivations');
  } else {
    candidate.buyingMotivations.forEach((item, index) => {
      if (!nonEmptyArray(item?.evidenceRefs)) {
        add('motivation_evidence_missing', '购买动机必须绑定证据', `buyingMotivations[${index}]`);
      }
    });
  }
  if (!isObject(candidate.dealStage) || !DEAL_STAGES.has(candidate.dealStage.stage)) {
    add('deal_stage_invalid', '成交阶段无效', 'dealStage.stage');
  } else if (!nonEmptyArray(candidate.dealStage.evidenceRefs)) {
    add('deal_stage_evidence_missing', '成交阶段必须绑定进入依据', 'dealStage.evidenceRefs');
  }
  if (!Number.isFinite(candidate.dealStage?.confidence)
    || candidate.dealStage.confidence < 0
    || candidate.dealStage.confidence > 1) {
    add('deal_stage_confidence_invalid', '阶段置信度必须在0到1之间', 'dealStage.confidence');
  }
  if (!nonEmptyArray(candidate.coreConcerns)) {
    add('core_concerns_missing', '至少需要一项核心顾虑', 'coreConcerns');
  }
  if (!FIT_STATUSES.has(candidate.fitAssessment?.status)) {
    add('fit_assessment_invalid', '适配判断必须明确适合、不适合或证据不足', 'fitAssessment.status');
  }
  if (!nonEmptyArray(candidate.nextBestQuestions)) {
    add('next_best_questions_missing', '必须给出下一步最佳问题', 'nextBestQuestions');
  }
  if (!nonEmptyArray(candidate.evidenceIndex)) {
    add('evidence_index_missing', '必须提供证据索引', 'evidenceIndex');
  }
  if (!Array.isArray(candidate.unknowns)) {
    add('unknowns_invalid', '未知项必须是数组', 'unknowns');
  }
  if (!isObject(candidate.downstreamBrief?.dealStrategy)) {
    add('downstream_brief_missing', '缺少成交策略下游简报', 'downstreamBrief');
  }
  if (candidate.clientAutonomy?.pressureTacticsUsed !== false
    || candidate.clientAutonomy?.guaranteeMade !== false
    || PROHIBITED.test(JSON.stringify(candidate))) {
    add('customer_autonomy_violated', '候选包含保证成交或施压内容', 'clientAutonomy');
  }
  if (!Array.isArray(candidate.externalActions) || candidate.externalActions.length !== 0) {
    add('external_action_not_allowed', '试运行候选不得执行外部动作', 'externalActions');
  }
  return result(failures);
}

function result(failures) {
  failures.sort((left, right) => (
    left.path.localeCompare(right.path) || left.code.localeCompare(right.code)
  ));
  return Object.freeze({
    ok: failures.length === 0,
    failures: Object.freeze(failures.map((item) => Object.freeze(item))),
  });
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function nonEmptyArray(value) {
  return Array.isArray(value) && value.length > 0;
}

function isExactPlanRef(value) {
  return Boolean(
    isObject(value)
    && typeof value.planId === 'string'
    && /^[a-z0-9][a-z0-9-]{2,119}$/u.test(value.planId)
    && Number.isInteger(value.version)
    && value.version >= 1
    && /^[a-f0-9]{64}$/u.test(value.sha256 ?? ''),
  );
}
