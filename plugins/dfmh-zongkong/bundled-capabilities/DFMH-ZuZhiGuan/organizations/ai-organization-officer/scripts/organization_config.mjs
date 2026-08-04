import path from 'node:path';
import { stat } from 'node:fs/promises';

import { deepFreeze, readStrictJson } from './strict_json.mjs';

const FIELDS = new Set([
  'schemaVersion',
  'id',
  'displayName',
  'systemName',
  'deploymentMode',
  'status',
  'acceptsFormalTasks',
  'rootControllerRegistration',
  'formalTaskRouting',
  'coreSkills',
  'publicSkillDependencies',
]);
const CORE = [
  ['talent-allocation', '人才配置'],
  ['talent-development', '人才培养'],
  ['process-replication', '流程复制'],
];
const PUBLIC = ['public.promotional-poster', 'public.taobao-ecommerce-image-set'];

export async function loadOrganizationConfig({ projectRoot } = {}) {
  const filePath = path.join(
    projectRoot,
    'organizations',
    'ai-organization-officer',
    'config',
    'organization.json',
  );
  const value = await readStrictJson(filePath, {
    label: 'AI organization officer config',
    allowedKeys: FIELDS,
  });
  for (const field of FIELDS) {
    if (!Object.hasOwn(value, field)) throw new Error(`organization config missing field: ${field}`);
  }
  if (value.schemaVersion !== 1
    || value.id !== 'ai-organization-officer'
    || value.displayName !== 'AI组织官'
    || value.systemName !== '组织复制系统'
    || value.deploymentMode !== 'same_project_organization_module') {
    throw new Error('organization identity or deployment mode drifted');
  }
  if (!['designing', 'pilot', 'operational'].includes(value.status)) {
    throw new Error('organization status is invalid');
  }
  if (value.status === 'operational') {
    if (value.acceptsFormalTasks !== true) {
      throw new Error('operational organization must accept formal tasks');
    }
    if (value.rootControllerRegistration !== 'registered_operational'
      || value.formalTaskRouting !== 'direct') {
      throw new Error('operational organization requires direct root registration');
    }
  } else {
    if (value.acceptsFormalTasks !== false) {
      throw new Error('non-operational organization cannot accept formal tasks');
    }
    if (value.rootControllerRegistration !== 'registered_designing'
      || value.formalTaskRouting !== 'fallback_existing') {
      throw new Error('root registration or formal task routing is overstated');
    }
  }
  if (!Array.isArray(value.coreSkills) || value.coreSkills.length !== 3) {
    throw new Error('organization must declare exactly three core skills');
  }
  value.coreSkills.forEach((skill, index) => {
    const expected = CORE[index];
    if (Object.keys(skill).sort().join(',') !== 'id,name,status'
      || skill.id !== expected[0]
      || skill.name !== expected[1]
      || !['designing', 'pilot', 'formal'].includes(skill.status)) {
      throw new Error(`core skill status or identity is invalid: ${expected[0]}`);
    }
  });
  for (const skill of value.coreSkills.filter((item) => item.status === 'formal')) {
    const formalSkill = path.join(
      projectRoot,
      'organizations',
      'ai-organization-officer',
      'skills',
      skill.id,
      'SKILL.md',
    );
    const details = await stat(formalSkill).catch(() => null);
    if (!details?.isFile() || details.size === 0) {
      throw new Error(`formal ${skill.id} requires a real SKILL.md`);
    }
  }
  if (!Array.isArray(value.publicSkillDependencies)
    || value.publicSkillDependencies.length !== 2
    || value.publicSkillDependencies.some(
      (item, index) => Object.keys(item).sort().join(',') !== 'id,mode'
        || item.id !== PUBLIC[index]
        || item.mode !== 'via-control-center',
    )) {
    throw new Error('public skill dependencies are invalid');
  }
  return deepFreeze(value);
}
