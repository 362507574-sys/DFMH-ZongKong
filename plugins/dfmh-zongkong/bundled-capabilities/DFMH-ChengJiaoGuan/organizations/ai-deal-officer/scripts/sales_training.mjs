const KNOWLEDGE_STATUSES = new Set(['matched', 'no_hit', 'degraded']);
const PROHIBITED = /100%成交|保证成交|稳赚|无风险|必须购买|逼单|恐吓|羞辱|虚假稀缺/u;

export function validateSalesTrainingCandidate({ candidate, context } = {}) {
  const failures = [];
  const add = (code, message, path) => failures.push({ code, message, path });
  if (!isObject(candidate)) {
    add('candidate_invalid', '销售训练候选必须是对象', '$');
    return result(failures);
  }
  if (candidate.schemaVersion !== 1 || candidate.capabilityId !== 'sales-training') {
    add('candidate_identity_invalid', '候选版本或技能身份错误', 'capabilityId');
  }
  if (candidate.enterpriseId !== context?.enterpriseId) {
    add('enterprise_mismatch', '候选与当前企业不一致', 'enterpriseId');
  }
  if (candidate.taskId !== context?.taskId) {
    add('task_mismatch', '候选与当前任务不一致', 'taskId');
  }
  if (!KNOWLEDGE_STATUSES.has(context?.knowledgeStatus)) {
    add('knowledge_preflight_incomplete', '飞书知识前置尚未完成', 'knowledgeStatus');
  }
  for (const scope of ['deal.strategy.read', 'deal.training.write']) {
    if (!context?.allowedScopes?.includes(scope)) {
      add('access_scope_missing', `缺少权限：${scope}`, 'allowedScopes');
    }
  }
  if (!isObject(candidate.dealStrategyRef)
    || !Number.isInteger(candidate.dealStrategyRef.version)
    || !/^[a-f0-9]{64}$/u.test(candidate.dealStrategyRef.sha256 ?? '')) {
    add('deal_strategy_ref_missing', '必须绑定已验证成交策略版本和哈希', 'dealStrategyRef');
  }
  const scenario = candidate.simulationScenario;
  if (!isObject(scenario)
    || !nonEmptyString(scenario.customerRole)
    || !nonEmptyString(scenario.context)
    || !nonEmptyArray(scenario.successCriteria)) {
    add('simulation_context_missing', '模拟客户必须包含角色、场景和成功条件', 'simulationScenario');
  }
  if (!nonEmptyArray(scenario?.pauseConditions) || !nonEmptyArray(scenario?.stopConditions)) {
    add('simulation_stop_missing', '模拟客户必须包含暂停和停止条件', 'simulationScenario');
  }
  if (!isObject(candidate.coachingPlan)
    || candidate.coachingPlan.feedbackAfterScenario !== true
    || candidate.coachingPlan.answerForLearner !== false
    || !Number.isInteger(candidate.coachingPlan.rounds)
    || candidate.coachingPlan.rounds < 1) {
    add('coaching_boundary_violated', '陪练必须完整场景后反馈且不得替学员作答', 'coachingPlan');
  }
  if (!nonEmptyArray(candidate.scorecard)) {
    add('scorecard_missing', '至少需要一个评分维度', 'scorecard');
  } else {
    candidate.scorecard.forEach((item, index) => {
      if (!nonEmptyArray(item?.observableEvidence) || !nonEmptyArray(item?.levels)) {
        add('score_evidence_missing', '评分必须包含可观察证据和等级说明', `scorecard[${index}]`);
      }
      if (!Number.isFinite(item?.weight) || item.weight <= 0) {
        add('score_weight_invalid', '评分权重必须为正数', `scorecard[${index}].weight`);
      }
    });
  }
  const replication = candidate.championReplication;
  if (!isObject(replication)
    || replication.authorized !== true
    || !Array.isArray(replication.sourceSamples)
    || replication.sourceSamples.length < 3
    || !nonEmptyArray(replication.verifiedPatterns)
    || !Array.isArray(replication.excludedAdvantages)
    || replication.pilotRequired !== true) {
    add(
      'champion_replication_evidence_missing',
      '销冠复制需要授权、多样本、已验证模式、优势排除和试运行',
      'championReplication',
    );
  }
  if (candidate.evaluationBoundary?.humanDecisionRequired !== true
    || candidate.evaluationBoundary?.employmentActionAllowed !== false) {
    add(
      'employment_decision_boundary_violated',
      'AI评分不得自动触发人事决定',
      'evaluationBoundary',
    );
  }
  if (!nonEmptyArray(candidate.evidenceIndex)) {
    add('evidence_index_missing', '必须提供证据索引', 'evidenceIndex');
  }
  if (!Array.isArray(candidate.unknowns)) {
    add('unknowns_invalid', '未知项必须是数组', 'unknowns');
  }
  if (candidate.clientAutonomy?.pressureTacticsUsed !== false
    || candidate.clientAutonomy?.guaranteeMade !== false
    || candidate.clientAutonomy?.noSaleAllowed !== true
    || PROHIBITED.test(JSON.stringify(candidate))) {
    add('customer_autonomy_violated', '训练包含保证成交、施压或不允许拒绝', 'clientAutonomy');
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

function nonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0;
}
