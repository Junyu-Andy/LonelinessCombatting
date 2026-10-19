/**
 * T27 — server-side Cantonese speech-to-text (SPEC:C18, decision 0019).
 *
 * Google Cloud Speech-to-Text v2, model `chirp_2`, region `asia-southeast1`
 * only (10/9 item 13: no fallback to the `global` region, not configurable).
 * The audio arrives base64-inline from the app, is handed to Google once
 * (retried once on a transient failure) and is never written anywhere: no
 * Cloud Storage, no Firestore, no log line.  The transcript goes back to
 * the app only; this module never logs it either.
 *
 * Data logging: the request below carries NO data-logging field
 * (`enableDataLogging` or anything like it — test/stt_test.js scans the
 * request object for it).  Google's console-level setting is checked by
 * the research team separately (docs/dev-reports/T27-stt-server-20261014.md).
 *
 * Request fields sent to Google (the complete list, see
 * buildRecognizeRequest):
 *   recognizer            projects/<id>/locations/asia-southeast1/
 *                         recognizers/_
 *   config.autoDecodingConfig           {}   (WAV header from the app)
 *   config.languageCodes                ["yue-Hant-HK"]
 *   config.model                        "chirp_2"
 *   config.features.enableAutomaticPunctuation  true
 *   content                             the audio bytes
 *
 * Failure categories returned to the app (both arms identical):
 *   timeout | server_error | no_speech | too_long | unavailable
 */
"use strict";

const STT_LOCATION = "asia-southeast1";
const STT_MODEL = "chirp_2";
const STT_API_ENDPOINT = "asia-southeast1-speech.googleapis.com";
const STT_LANGUAGE = "yue-Hant-HK";

/** Sync recognize limits (Google: 60 s / 10 MB); the app caps at 60 s. */
const MAX_AUDIO_BYTES = 10 * 1024 * 1024;

/** Per-attempt deadline; two attempts fit in the 120 s function budget. */
const ATTEMPT_TIMEOUT_MS = 30 * 1000;

const CATEGORIES = Object.freeze({
  timeout: "timeout",
  serverError: "server_error",
  noSpeech: "no_speech",
  tooLong: "too_long",
  unavailable: "unavailable",
});

/** Categories where the same audio could succeed on a second try. */
const RETRYABLE = Object.freeze([
  CATEGORIES.timeout, CATEGORIES.serverError, CATEGORIES.unavailable,
]);

/** Firebase callable error code for each category. */
const HTTPS_CODE = Object.freeze({
  timeout: "deadline-exceeded",
  server_error: "internal",
  no_speech: "not-found",
  too_long: "invalid-argument",
  unavailable: "unavailable",
});

/**
 * Categorised STT failure.  Carries no audio and no text.
 */
class SttError extends Error {
  /**
   * @param {string} category one of CATEGORIES.
   * @param {number} attempts how many Google calls were made.
   * @param {string=} grpcCode Google's status code, for ops only.
   */
  constructor(category, attempts, grpcCode) {
    super(`stt ${category}`);
    this.category = category;
    this.attempts = attempts;
    this.grpcCode = grpcCode === undefined ? null : grpcCode;
  }
}

/**
 * The exact request object sent to Google.  Pure, so the unit test can
 * inspect every field.
 * @param {{projectId: string, content: Buffer}} p
 * @return {object} RecognizeRequest
 */
function buildRecognizeRequest(p) {
  return {
    recognizer:
      `projects/${p.projectId}/locations/${STT_LOCATION}/recognizers/_`,
    config: {
      autoDecodingConfig: {},
      languageCodes: [STT_LANGUAGE],
      model: STT_MODEL,
      features: {enableAutomaticPunctuation: true},
    },
    content: p.content,
  };
}

/**
 * Map a Google / gRPC error to a failure category.  Only codes are looked
 * at; the message is used for the one INVALID_ARGUMENT case where Google
 * says the clip is too long.
 * @param {Error} err
 * @return {string} category
 */
function categoriseError(err) {
  const code = err && typeof err.code === "number" ? err.code : null;
  const msg = String((err && err.message) || "").toLowerCase();
  if (code === 4 || /deadline|timed? ?out/.test(msg)) {
    return CATEGORIES.timeout;
  }
  if (code === 14 || code === 8) return CATEGORIES.unavailable;
  if (code === 3 || code === 11) {
    if (/too long|exceed|duration|60 ?s|limit/.test(msg)) {
      return CATEGORIES.tooLong;
    }
    return CATEGORIES.serverError;
  }
  return CATEGORIES.serverError;
}

// 10/19 field test: chirp_2 returns Cantonese word-segmented with spaces
// (「我 今日 去 咗 飲茶」).  Drop whitespace that sits between two CJK
// characters or CJK punctuation; a space next to Latin letters or digits
// (「我 book 咗 3 點」) stays.
const CJK = "\u3000-\u303f\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff" +
  "\uff00-\uffef";
const CJK_GAP = new RegExp(`(?<=[${CJK}])\\s+(?=[${CJK}])`, "g");

/**
 * Remove the spaces Google puts between Chinese words.
 * @param {string} s transcript
 * @return {string}
 */
function tidyCantonese(s) {
  return s.replace(CJK_GAP, "");
}

/**
 * Join the alternatives Google returned into one transcript.
 * @param {object} resp RecognizeResponse
 * @return {{transcript: string, confidence: (number|null)}}
 */
function readResponse(resp) {
  const results = (resp && resp.results) || [];
  const transcript = tidyCantonese(results
      .map((r) => (r.alternatives && r.alternatives[0] &&
        r.alternatives[0].transcript) || "")
      .join("")
      .trim());
  const first = results[0] && results[0].alternatives &&
    results[0].alternatives[0];
  const confidence = first && typeof first.confidence === "number" ?
    first.confidence : null;
  return {transcript, confidence};
}

/**
 * Call Google once; on a retryable failure call it once more.  `recognize`
 * is injected so tests run without network.
 *
 * @param {function(object): Promise<object>} recognize (request) → response
 * @param {object} request from buildRecognizeRequest
 * @param {{maxAttempts: (number|undefined)}=} opts
 * @return {Promise<{transcript: string, confidence: (number|null),
 *   attempts: number, latencyMs: number}>}
 * @throws {SttError}
 */
async function transcribeWithRetry(recognize, request, opts) {
  const maxAttempts = (opts && opts.maxAttempts) || 2;
  const t0 = Date.now();
  let attempts = 0;
  for (;;) {
    attempts += 1;
    let resp;
    try {
      resp = await recognize(request);
    } catch (e) {
      const category = categoriseError(e);
      const retry = RETRYABLE.indexOf(category) !== -1 &&
        attempts < maxAttempts;
      if (retry) continue;
      throw new SttError(category, attempts,
          e && e.code !== undefined ? String(e.code) : undefined);
    }
    const out = readResponse(resp);
    if (out.transcript.length === 0) {
      // Google heard nothing it could write down.  A second pass over the
      // same silence would not help, so this is not retried.
      throw new SttError(CATEGORIES.noSpeech, attempts);
    }
    return {
      transcript: out.transcript,
      confidence: out.confidence,
      attempts,
      latencyMs: Date.now() - t0,
    };
  }
}

/**
 * Default `recognize`: a real SpeechClient pinned to the regional endpoint.
 * Lazy-required so other functions' cold starts are not slowed.
 * @return {function(object): Promise<object>}
 */
function googleRecognize() {
  const {SpeechClient} = require("@google-cloud/speech").v2;
  const client = new SpeechClient({apiEndpoint: STT_API_ENDPOINT});
  return async (request) => {
    const [resp] = await client.recognize(request, {
      timeout: ATTEMPT_TIMEOUT_MS,
    });
    return resp;
  };
}

/**
 * Validate the clip size.  Returns a category or null.
 * @param {Buffer} content
 * @return {(string|null)}
 */
function sizeProblem(content) {
  if (content.length > MAX_AUDIO_BYTES) return CATEGORIES.tooLong;
  return null;
}

module.exports = {
  STT_LOCATION,
  STT_MODEL,
  STT_API_ENDPOINT,
  STT_LANGUAGE,
  MAX_AUDIO_BYTES,
  ATTEMPT_TIMEOUT_MS,
  CATEGORIES,
  RETRYABLE,
  HTTPS_CODE,
  SttError,
  buildRecognizeRequest,
  categoriseError,
  readResponse,
  tidyCantonese,
  transcribeWithRetry,
  googleRecognize,
  sizeProblem,
};
