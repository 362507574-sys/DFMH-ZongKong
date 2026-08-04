import assert from 'node:assert/strict';

import {
  POSTER_ACTION_SLA_MS,
  runPosterGenerationToDownload,
  runPosterUploadBlock,
} from '../scripts/poster_chatgpt_browser_fastlane.mjs';

function createVirtualClock() {
  let current = 0;
  return {
    now: () => current,
    sleep: async (ms) => {
      current += ms;
    },
  };
}

async function testUploadBlockRunsContinuously() {
  const clock = createVirtualClock();
  const actionsRun = [];
  let thumbnailVisible = false;

  const result = await runPosterUploadBlock({
    observe: async (state) => {
      if (state === 'page_ready') return true;
      if (state === 'asset_thumbnail_verified') return thumbnailVisible;
      return false;
    },
    actions: {
      pasteAsset: async () => {
        actionsRun.push('paste_asset');
        thumbnailVisible = true;
      },
    },
    controllerOptions: {
      now: clock.now,
      sleep: clock.sleep,
    },
  });

  assert.deepEqual(actionsRun, ['paste_asset']);
  assert.equal(result.status, 'completed');
  assert.deepEqual(
    result.timeline.filter((event) => event.event === 'step_completed').map((event) => event.step),
    ['page_ready', 'asset_thumbnail_verified'],
  );
}

async function testGenerationToDownloadRunsInOneOrderedSequence() {
  const clock = createVirtualClock();
  const actionsRun = [];
  const state = {
    generationPolls: 0,
    viewerOpen: false,
    downloadDialogOpen: false,
    downloadComplete: false,
  };

  const result = await runPosterGenerationToDownload({
    prompt: 'synthetic poster prompt',
    downloadFileName: 'synthetic-poster.png',
    observe: async (name) => {
      if (name === 'composer_ready') return true;
      if (name === 'generation_complete') {
        state.generationPolls += 1;
        return state.generationPolls >= 3;
      }
      if (name === 'viewer_open') return state.viewerOpen;
      if (name === 'download_dialog_open') return state.downloadDialogOpen;
      if (name === 'download_complete') return state.downloadComplete;
      return false;
    },
    actions: {
      submitPrompt: async (prompt) => {
        assert.equal(prompt, 'synthetic poster prompt');
        actionsRun.push('submit_prompt');
      },
      openGeneratedImage: async () => {
        actionsRun.push('open_viewer');
        state.viewerOpen = true;
      },
      requestDownload: async () => {
        actionsRun.push('request_download');
        state.downloadDialogOpen = true;
      },
      confirmDownload: async (fileName) => {
        assert.equal(fileName, 'synthetic-poster.png');
        actionsRun.push('confirm_download');
        state.downloadComplete = true;
      },
    },
    controllerOptions: {
      now: clock.now,
      sleep: clock.sleep,
    },
  });

  assert.deepEqual(actionsRun, [
    'submit_prompt',
    'open_viewer',
    'request_download',
    'confirm_download',
  ]);
  assert.equal(state.generationPolls, 3);
  assert.equal(
    result.timeline.filter((event) => event.event === 'action_started').length,
    4,
    'each deterministic action should run exactly once',
  );
  const viewerAction = result.timeline.find(
    (event) => event.event === 'action_completed' && event.step === 'generation_complete',
  );
  assert.equal(viewerAction.actionSlaMs, POSTER_ACTION_SLA_MS.openGeneratedImage);
  assert.equal(viewerAction.slaBreached, false, 'generation waiting must not count against action SLA');
}

await testUploadBlockRunsContinuously();
await testGenerationToDownloadRunsInOneOrderedSequence();

console.log('PASS: poster ChatGPT browser fast-lane tests (2 cases).');
