import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import {
  ContinuousActionError,
  runContinuousActionSequence,
  writeTimelineFile,
} from '../scripts/browser_continuous_action_controller.mjs';

function createVirtualClock() {
  let current = 0;
  return {
    now: () => current,
    sleep: async (ms) => {
      current += ms;
    },
    advance: (ms) => {
      current += ms;
    },
  };
}

async function testImmediateTransitionAndSingleExecution() {
  const clock = createVirtualClock();
  let observations = 0;
  let actions = 0;

  const result = await runContinuousActionSequence({
    sequenceName: 'synthetic-sequence',
    now: clock.now,
    sleep: clock.sleep,
    steps: [
      {
        name: 'ready_then_act',
        pollIntervalMs: 2,
        timeoutMs: 20,
        condition: async () => {
          observations += 1;
          return observations >= 3;
        },
        action: async () => {
          actions += 1;
        },
        actionSlaMs: 3,
      },
    ],
  });

  assert.equal(observations, 3, 'condition should be polled only until it becomes true');
  assert.equal(actions, 1, 'a completed action must execute exactly once');
  assert.equal(result.status, 'completed');
  assert.equal(result.timeline.filter((event) => event.event === 'action_started').length, 1);
}

async function testSlaBreachIsRecordedWithoutCancellingValidAction() {
  const clock = createVirtualClock();

  const result = await runContinuousActionSequence({
    sequenceName: 'slow-valid-action',
    now: clock.now,
    sleep: clock.sleep,
    steps: [
      {
        name: 'download_confirm',
        condition: async () => true,
        action: async () => clock.advance(5),
        timeoutMs: 20,
        pollIntervalMs: 1,
        actionSlaMs: 3,
      },
    ],
  });

  const completed = result.timeline.find((event) => event.event === 'action_completed');
  assert.equal(completed.slaBreached, true, 'valid slow actions should be logged as an SLA breach');
  assert.equal(result.status, 'completed', 'an SLA breach must not discard a valid result');
}

async function testConditionTimeoutStopsSequence() {
  const clock = createVirtualClock();

  await assert.rejects(
    runContinuousActionSequence({
      sequenceName: 'timeout-sequence',
      now: clock.now,
      sleep: clock.sleep,
      steps: [
        {
          name: 'missing-dialog',
          condition: async () => false,
          action: async () => {
            throw new Error('must not run');
          },
          timeoutMs: 5,
          pollIntervalMs: 2,
          actionSlaMs: 3,
        },
      ],
    }),
    (error) => {
      assert.ok(error instanceof ContinuousActionError);
      assert.equal(error.code, 'CONDITION_TIMEOUT');
      assert.equal(error.step, 'missing-dialog');
      assert.equal(error.timeline.some((event) => event.event === 'step_failed'), true);
      return true;
    },
  );
}

async function testTimelineWritesOnlyInsideProjectTemp() {
  const root = await mkdtemp(path.join(os.tmpdir(), 'browser-action-controller-'));
  const taskDir = path.join(root, 'temp', 'jobs', 'synthetic');
  await mkdir(taskDir, { recursive: true });

  try {
    const output = await writeTimelineFile({
      projectRoot: root,
      taskDirectory: taskDir,
      fileName: 'timeline.jsonl',
      timeline: [{ event: 'page_ready', timestampMs: 1 }],
    });
    const saved = await readFile(output, 'utf8');
    assert.equal(saved.trim(), '{"event":"page_ready","timestampMs":1}');

    await assert.rejects(
      writeTimelineFile({
        projectRoot: root,
        taskDirectory: path.join(root, 'outside'),
        fileName: 'timeline.jsonl',
        timeline: [],
      }),
      (error) => {
        assert.equal(error.code, 'TIMELINE_PATH_OUTSIDE_TEMP');
        return true;
      },
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

await testImmediateTransitionAndSingleExecution();
await testSlaBreachIsRecordedWithoutCancellingValidAction();
await testConditionTimeoutStopsSequence();
await testTimelineWritesOnlyInsideProjectTemp();

console.log('PASS: browser continuous-action controller tests (4 cases).');
