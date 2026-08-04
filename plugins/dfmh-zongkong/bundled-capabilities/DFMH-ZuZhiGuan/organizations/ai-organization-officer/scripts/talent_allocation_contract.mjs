const DISCRIMINATORY = /男性|女性|男士|女士|未婚|已婚|婚育|怀孕|民族|籍贯|疾病|残疾|年轻人|年龄(?:不超过|小于)|属相|星座/u;
const VAGUE_RESPONSIBILITY = /^(?:完成)?(?:领导|上级)交办的(?:其他|其它)?工作[。.]?$/u;
const ADVERSE_ACTION = /辞退|开除|降职|降薪|处罚|淘汰/u;

export function validateTalentAllocationCandidate({
  candidate,
  task,
  enterpriseProfile,
  knowledgeContext,
} = {}) {
  const failures = [];
  const add = (code, message, path) => failures.push({ code, message, path });
  if (!isObject(candidate)) {
    add('candidate_invalid', '人才配置候选必须是对象', '$');
    return result(failures);
  }
  if (candidate.schemaVersion !== 1) add('schema_version_invalid', '候选版本必须为1', 'schemaVersion');
  if (candidate.enterpriseId !== task?.enterpriseId
    || candidate.enterpriseId !== enterpriseProfile?.enterpriseId) {
    add('enterprise_mismatch', '候选、任务和企业档案必须属于同一企业', 'enterpriseId');
  }
  if (candidate.taskId !== task?.taskId) {
    add('task_mismatch', '候选必须绑定当前组织任务', 'taskId');
  }
  if (!knowledgeContext
    || !['matched', 'no_hit', 'degraded'].includes(knowledgeContext.status)
    || task?.knowledgeStatus === 'pending') {
    add('knowledge_preflight_missing', '正式候选必须绑定真实知识前置凭证', 'knowledgeContext');
  }

  for (const [field, message] of [
    ['diagnosis', '缺少组织与非人才根因诊断'],
    ['organizationDesign', '缺少组织设计'],
    ['staffingPlan', '缺少人员编制方案'],
    ['recruitmentPackage', '缺少招聘评估包'],
    ['performanceDesign', '缺少绩效设计'],
    ['compensationDesign', '缺少薪酬边界说明'],
  ]) {
    if (!isObject(candidate[field])) add(`${field}_missing`, message, field);
  }

  if (!Array.isArray(candidate.jobProfiles) || candidate.jobProfiles.length === 0) {
    add('job_profiles_missing', '至少需要一个岗位说明', 'jobProfiles');
  } else {
    candidate.jobProfiles.forEach((job, index) => {
      const responsibilities = Array.isArray(job?.responsibilities) ? job.responsibilities : [];
      if (responsibilities.length === 0
        || responsibilities.some((item) => typeof item !== 'string' || VAGUE_RESPONSIBILITY.test(item.trim()))) {
        add(
          'job_responsibility_too_vague',
          '岗位职责无法形成可执行成果标准',
          `jobProfiles[${index}].responsibilities`,
        );
      }
      if (!Array.isArray(job?.deliverables) || job.deliverables.length === 0
        || !Array.isArray(job?.qualityStandards) || job.qualityStandards.length === 0) {
        add(
          'job_output_standard_missing',
          '岗位必须包含交付成果和质量标准',
          `jobProfiles[${index}]`,
        );
      }
    });
  }

  if (!Array.isArray(candidate.talentProfiles) || candidate.talentProfiles.length === 0) {
    add('talent_profiles_missing', '至少需要一个人才画像', 'talentProfiles');
  } else {
    candidate.talentProfiles.forEach((profile, index) => {
      const serialized = JSON.stringify(profile);
      if (DISCRIMINATORY.test(serialized)) {
        add(
          'discriminatory_criterion',
          '人才标准包含与岗位无关或可能违法的歧视条件',
          `talentProfiles[${index}]`,
        );
      }
      if (!Array.isArray(profile?.observableEvidence) || profile.observableEvidence.length === 0) {
        add(
          'talent_evidence_missing',
          '人才画像必须给出可观察证据',
          `talentProfiles[${index}].observableEvidence`,
        );
      }
    });
  }

  if (!Array.isArray(candidate.personJobMatches)) {
    add('person_job_matches_invalid', '人岗匹配必须是数组', 'personJobMatches');
  } else {
    candidate.personJobMatches.forEach((match, index) => {
      if (!Array.isArray(match?.dimensions)
        || match.dimensions.length === 0
        || !Array.isArray(match?.unknowns)) {
        add(
          'person_job_match_missing_evidence',
          '人岗匹配不能只有总分，必须包含分项证据和未知项',
          `personJobMatches[${index}]`,
        );
      }
    });
  }

  if (Array.isArray(candidate.adjustmentRecommendations)) {
    candidate.adjustmentRecommendations.forEach((recommendation, index) => {
      const text = JSON.stringify(recommendation);
      if (ADVERSE_ACTION.test(text)
        && (recommendation?.status === 'executed' || recommendation?.requiresUserDecision !== true)) {
        add(
          'automatic_adverse_employment_action',
          'AI建议不能直接执行不利人事决定',
          `adjustmentRecommendations[${index}]`,
        );
      }
    });
  }

  if (!isObject(candidate.downstreamBrief)
    || !isObject(candidate.downstreamBrief.talentDevelopment)
    || !isObject(candidate.downstreamBrief.processReplication)) {
    add(
      'downstream_brief_missing',
      '候选必须包含人才培养和流程复制下游简报',
      'downstreamBrief',
    );
  }
  if (!Array.isArray(candidate.decisionsRequired)
    || candidate.decisionsRequired.some((item) => item?.executed === true)) {
    add(
      'user_decision_boundary_missing',
      '重大人事事项必须保留为使用者待决策项',
      'decisionsRequired',
    );
  }
  return result(failures);
}

function result(failures) {
  failures.sort((left, right) => (
    left.path.localeCompare(right.path) || left.code.localeCompare(right.code)
  ));
  return Object.freeze({ ok: failures.length === 0, failures: Object.freeze(failures) });
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
