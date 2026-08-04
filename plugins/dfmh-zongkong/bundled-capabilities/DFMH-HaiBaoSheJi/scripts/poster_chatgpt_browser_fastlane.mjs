import { runContinuousActionSequence } from './browser_continuous_action_controller.mjs';

export const POSTER_ACTION_SLA_MS = Object.freeze({
  pasteAsset: 3_000,
  submitPrompt: 5_000,
  openGeneratedImage: 2_000,
  requestDownload: 2_000,
  confirmDownload: 3_000,
});

export const POSTER_STATE_TIMEOUT_MS = Object.freeze({
  pageReady: 15_000,
  assetThumbnailVerified: 30_000,
  composerReady: 10_000,
  generationComplete: 300_000,
  viewerOpen: 10_000,
  downloadDialogOpen: 10_000,
  downloadComplete: 60_000,
});

const POSTER_POLL_INTERVAL_MS = Object.freeze({
  normal: 500,
  generation: 1_000,
});

function requireFunction(value, label) {
  if (typeof value !== 'function') {
    throw new TypeError(`${label} must be a function.`);
  }
}

function requireActions(actions, names) {
  if (!actions || typeof actions !== 'object') {
    throw new TypeError('actions must be an object.');
  }
  for (const name of names) {
    requireFunction(actions[name], `actions.${name}`);
  }
}

function condition(observe, stateName) {
  return async (context) => observe(stateName, context);
}

export async function runPosterUploadBlock({
  observe,
  actions,
  context = {},
  controllerOptions = {},
} = {}) {
  requireFunction(observe, 'observe');
  requireActions(actions, ['pasteAsset']);

  return runContinuousActionSequence({
    ...controllerOptions,
    sequenceName: 'poster_upload_block',
    context,
    steps: [
      {
        name: 'page_ready',
        condition: condition(observe, 'page_ready'),
        action: async (currentContext) => actions.pasteAsset(currentContext),
        timeoutMs: POSTER_STATE_TIMEOUT_MS.pageReady,
        pollIntervalMs: POSTER_POLL_INTERVAL_MS.normal,
        actionSlaMs: POSTER_ACTION_SLA_MS.pasteAsset,
      },
      {
        name: 'asset_thumbnail_verified',
        condition: condition(observe, 'asset_thumbnail_verified'),
        timeoutMs: POSTER_STATE_TIMEOUT_MS.assetThumbnailVerified,
        pollIntervalMs: POSTER_POLL_INTERVAL_MS.normal,
      },
    ],
  });
}

export async function runPosterGenerationToDownload({
  prompt,
  downloadFileName,
  observe,
  actions,
  context = {},
  controllerOptions = {},
} = {}) {
  if (!prompt || typeof prompt !== 'string') {
    throw new TypeError('prompt must be a non-empty string.');
  }
  if (
    !downloadFileName
    || typeof downloadFileName !== 'string'
    || /[\\/]/.test(downloadFileName)
  ) {
    throw new TypeError('downloadFileName must be a plain file name.');
  }
  requireFunction(observe, 'observe');
  requireActions(actions, [
    'submitPrompt',
    'openGeneratedImage',
    'requestDownload',
    'confirmDownload',
  ]);

  return runContinuousActionSequence({
    ...controllerOptions,
    sequenceName: 'poster_generation_to_download',
    context,
    steps: [
      {
        name: 'composer_ready',
        condition: condition(observe, 'composer_ready'),
        action: async (currentContext) => actions.submitPrompt(prompt, currentContext),
        timeoutMs: POSTER_STATE_TIMEOUT_MS.composerReady,
        pollIntervalMs: POSTER_POLL_INTERVAL_MS.normal,
        actionSlaMs: POSTER_ACTION_SLA_MS.submitPrompt,
      },
      {
        name: 'generation_complete',
        condition: condition(observe, 'generation_complete'),
        action: async (currentContext) => actions.openGeneratedImage(currentContext),
        timeoutMs: POSTER_STATE_TIMEOUT_MS.generationComplete,
        pollIntervalMs: POSTER_POLL_INTERVAL_MS.generation,
        actionSlaMs: POSTER_ACTION_SLA_MS.openGeneratedImage,
      },
      {
        name: 'viewer_open',
        condition: condition(observe, 'viewer_open'),
        action: async (currentContext) => actions.requestDownload(currentContext),
        timeoutMs: POSTER_STATE_TIMEOUT_MS.viewerOpen,
        pollIntervalMs: POSTER_POLL_INTERVAL_MS.normal,
        actionSlaMs: POSTER_ACTION_SLA_MS.requestDownload,
      },
      {
        name: 'download_dialog_open',
        condition: condition(observe, 'download_dialog_open'),
        action: async (currentContext) => actions.confirmDownload(downloadFileName, currentContext),
        timeoutMs: POSTER_STATE_TIMEOUT_MS.downloadDialogOpen,
        pollIntervalMs: POSTER_POLL_INTERVAL_MS.normal,
        actionSlaMs: POSTER_ACTION_SLA_MS.confirmDownload,
      },
      {
        name: 'download_complete',
        condition: condition(observe, 'download_complete'),
        timeoutMs: POSTER_STATE_TIMEOUT_MS.downloadComplete,
        pollIntervalMs: POSTER_POLL_INTERVAL_MS.normal,
      },
    ],
  });
}
