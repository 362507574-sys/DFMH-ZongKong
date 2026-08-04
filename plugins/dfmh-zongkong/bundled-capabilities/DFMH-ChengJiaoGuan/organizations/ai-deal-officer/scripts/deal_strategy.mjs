const KNOWLEDGE_STATUSES = new Set(['matched', 'no_hit', 'degraded']);
const PROHIBITED = /100%成交|保证成交|稳赚|无风险|必须购买|逼单|恐吓|羞辱|虚假稀缺/u;

export function validateDealStrategyCandidate({ candidate, context } = {}) {
  const failures = [];
  const add = (code, message, path) => failures.push({ code, message, path });
  if (!isObject(candidate)) {
    add('candidate_invalid', '成交策略候选必须是对象', '$');
    return result(failures);
  }
  if (candidate.schemaVersion !== 1 || candidate.capabilityId !== 'deal-strategy') {
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
  for (const scope of ['deal.insight.read', 'deal.candidate.write']) {
    if (!context?.allowedScopes?.includes(scope)) {
      add('access_scope_missing', `缺少权限：${scope}`, 'allowedScopes');
    }
  }
  if (!isObject(candidate.customerInsightRef)
    || !Number.isInteger(candidate.customerInsightRef.version)
    || !/^[a-f0-9]{64}$/u.test(candidate.customerInsightRef.sha256 ?? '')) {
    add('customer_insight_ref_missing', '必须绑定已验证客户洞察版本和哈希', 'customerInsightRef');
  }
  if (!isObject(candidate.communicationStrategy)
    || !nonEmptyArray(candidate.communicationStrategy.objectives)
    || !nonEmptyArray(candidate.communicationStrategy.questions)) {
    add('communication_strategy_missing', '缺少沟通目标或关键问题', 'communicationStrategy');
  }
  if (!nonEmptyArray(candidate.valueEvidenceMatrix)) {
    add('value_matrix_missing', '至少需要一项价值证据', 'valueEvidenceMatrix');
  } else {
    candidate.valueEvidenceMatrix.forEach((item, index) => {
      if (!nonEmptyArray(item?.evidenceRefs)) {
        add('value_evidence_missing', '价值主张必须绑定证据', `valueEvidenceMatrix[${index}]`);
      }
      if (!nonEmptyArray(item?.conditions) || !nonEmptyArray(item?.limitations)) {
        add('value_limitations_missing', '价值主张必须包含适用条件和限制', `valueEvidenceMatrix[${index}]`);
      }
    });
  }
  if (!nonEmptyArray(candidate.objectionHandling)) {
    add('objection_handling_missing', '至少需要一项异议处理', 'objectionHandling');
  } else {
    candidate.objectionHandling.forEach((item, index) => {
      if (!nonEmptyArray(item?.clarifyQuestions) || !nonEmptyArray(item?.responseEvidenceRefs)) {
        add('objection_evidence_missing', '异议处理必须先澄清并绑定证据', `objectionHandling[${index}]`);
      }
      if (!item?.allowedOutcomes?.includes('pause')
        || !item?.allowedOutcomes?.includes('no_sale')) {
        add('objection_exit_missing', '异议处理必须允许暂停和不成交', `objectionHandling[${index}]`);
      }
    });
  }
  if (!nonEmptyArray(candidate.dealPath)) {
    add('deal_path_missing', '至少需要一个成交路径阶段', 'dealPath');
  } else {
    candidate.dealPath.forEach((item, index) => {
      if (!nonEmptyArray(item?.entryCriteria)) {
        add('deal_path_entry_missing', '路径阶段必须有进入条件', `dealPath[${index}]`);
      }
      if (!nonEmptyArray(item?.stopConditions)) {
        add('deal_path_stop_missing', '路径阶段必须有停止条件', `dealPath[${index}]`);
      }
    });
  }
  if (!isObject(candidate.followUpPlan) || !nonEmptyArray(candidate.followUpPlan.stopAfter)) {
    add('follow_up_stop_missing', '跟进计划必须有停止条件', 'followUpPlan');
  }
  if (!nonEmptyArray(candidate.evidenceIndex)) {
    add('evidence_index_missing', '必须提供证据索引', 'evidenceIndex');
  }
  if (!Array.isArray(candidate.unknowns)) {
    add('unknowns_invalid', '未知项必须是数组', 'unknowns');
  }
  if (!isObject(candidate.downstreamBrief?.salesTraining)) {
    add('downstream_brief_missing', '缺少销售训练下游简报', 'downstreamBrief');
  }
  if (candidate.clientAutonomy?.pressureTacticsUsed !== false
    || candidate.clientAutonomy?.guaranteeMade !== false
    || candidate.clientAutonomy?.noSaleAllowed !== true
    || PROHIBITED.test(JSON.stringify(candidate))) {
    add('customer_autonomy_violated', '候选包含保证成交、施压或不允许拒绝', 'clientAutonomy');
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
