export function createController() {
  return freezeState({ schemaVersion: 1, projects: [], activeByChat: {}, processedMessageIds: [] });
}

export function handleMessage(inputState, message = {}) {
  const state = cloneState(inputState);
  const chatId = required(message.chatId, 'chatId');
  const messageId = required(message.messageId, 'messageId');
  const text = required(message.text, 'text');
  if (state.processedMessageIds.includes(messageId)) {
    return Object.freeze({ state: freezeState(state), decision: Object.freeze({ mode: 'duplicate_ignored' }) });
  }
  state.processedMessageIds.push(messageId);
  const createMatch = text.match(/^\s*(?:项目|新建项目)\s*[：:]\s*(.+)$/u);
  if (createMatch) {
    const projectId = 'P-' + String(state.projects.length + 1).padStart(4, '0');
    state.projects.push({ id: projectId, chatId, title: createMatch[1].trim(), status: 'active', revisions: [] });
    state.activeByChat[chatId] = projectId;
    return result(state, { mode: 'create_project', projectId });
  }
  const activeId = state.activeByChat[chatId];
  const active = state.projects.find((project) => project.id === activeId && project.status === 'active');
  if (active && isProjectContinuation(text)) {
    active.revisions.push({ messageId, text });
    return result(state, { mode: 'continue_project', projectId: active.id });
  }
  return result(state, { mode: 'quick_chat' });
}

export function authorizeChannelAction({ channel, action } = {}) {
  const groupDenied = new Set(['system_control', 'credential_access', 'cross_project_read', 'account_permission_change']);
  if (channel === 'group_work') return Object.freeze({ allowed: !groupDenied.has(action), reason: groupDenied.has(action) ? 'group_boundary' : '' });
  if (channel === 'owner_control') return Object.freeze({ allowed: true, reason: '' });
  return Object.freeze({ allowed: false, reason: 'unknown_channel' });
}

export function feishuStatus(config = {}) {
  if (!config.enabled) return Object.freeze({ status: 'not_configured' });
  if (!config.appId || !config.secretAvailable) return Object.freeze({ status: 'configuration_incomplete' });
  return Object.freeze({ status: 'ready' });
}

function isProjectContinuation(text) {
  return /(?:修改|改成|调整|补充|继续|这个项目|该项目|上一版|重新汇报|素材|方案|目标客户)/u.test(text);
}

function result(state, decision) { return Object.freeze({ state: freezeState(state), decision: Object.freeze(decision) }); }
function cloneState(value) { return JSON.parse(JSON.stringify(value ?? createController())); }
function freezeState(value) { return Object.freeze(value); }
function required(value, label) { if (typeof value !== 'string' || !value.trim()) throw new TypeError(label + ' is required'); return value.trim(); }
