import { fileURLToPath } from 'node:url';
import path from 'node:path';

import { validateCustomerInsightCandidate } from './customer_insight.mjs';
import { validateDealStrategyCandidate } from './deal_strategy.mjs';
import { validateSalesTrainingCandidate } from './sales_training.mjs';
import { buildDealExecutionPlan } from './deal_planner.mjs';
import { debugDealStep } from './deal_debugger.mjs';
import { evaluateCustomerInsightWorkflow } from './customer_insight_workflow.mjs';

const VALIDATORS = new Map([
  ['customer-insight', validateCustomerInsightCandidate],
  ['deal-strategy', validateDealStrategyCandidate],
  ['sales-training', validateSalesTrainingCandidate],
]);
const RUNTIME_MODES = Object.freeze([
  'list-skills',
  'plan',
  'debug',
  'validate-candidate',
  'run-customer-insight-checkpoint',
]);

export function listDealSkillIds() {
  return Object.freeze([...VALIDATORS.keys()]);
}

export function listDealRuntimeModes() {
  return RUNTIME_MODES;
}

export function runDealRuntimeCommand({ mode, payload = {} } = {}) {
  if (!RUNTIME_MODES.includes(mode)) throw new Error(`unsupported runtime mode: ${mode}`);
  if (mode === 'list-skills') {
    return Object.freeze({ ok: true, skills: listDealSkillIds() });
  }
  if (mode === 'plan') {
    return Object.freeze({ ok: true, plan: buildDealExecutionPlan(payload) });
  }
  if (mode === 'debug') {
    return Object.freeze({ ok: true, diagnostic: debugDealStep(payload) });
  }
  if (mode === 'validate-candidate') {
    return validateDealSkillCandidate(payload);
  }
  return evaluateCustomerInsightWorkflow(payload);
}

export function validateDealSkillCandidate({
  capabilityId,
  candidate,
  context,
} = {}) {
  const validator = VALIDATORS.get(capabilityId);
  if (!validator) {
    return Object.freeze({
      ok: false,
      failures: Object.freeze([
        Object.freeze({
          code: 'unsupported_capability',
          message: 'AI成交官只接受三个已登记核心技能',
          path: 'capabilityId',
        }),
      ]),
    });
  }
  return validator({ candidate, context });
}

async function runCli() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  let input;
  try {
    input = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    process.stdout.write(`${JSON.stringify({
      ok: false,
      failures: [{
        code: 'input_json_invalid',
        message: '标准输入必须是合法JSON',
        path: '$',
      }],
    })}\n`);
    process.exitCode = 2;
    return;
  }
  const output = input?.mode
    ? runDealRuntimeCommand(input)
    : validateDealSkillCandidate(input);
  process.stdout.write(`${JSON.stringify(output)}\n`);
  if (!output.ok) process.exitCode = 2;
}

const currentFile = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === currentFile) {
  await runCli();
}
