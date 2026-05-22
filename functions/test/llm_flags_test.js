/**
 * B.1 — golden-file regression for the 5-flag detector (Phase A spec May 2026).
 *
 * Run:  cd functions && node test/llm_flags_test.js
 *
 * Five hand-crafted M3 turns covering each flag's positive case + a
 * sixth negative case for each.  Update the fixture AND bump _version
 * in llm_flags.js when heuristics intentionally change; never silently
 * when a flag flips.
 *
 * Phase A Gate #4 requires Cohen's κ ≥ 0.6 per flag against the
 * adjudicated 20% sample of real Phase A turns.  This file is the
 * synthetic baseline; the real-corpus calibration is a Phase A
 * deliverable.
 */

'use strict';

const assert = require('assert');
const {computeLlmFlags} = require('../llm_flags');

const fixtures = [
  // Flag 1: specific_content_engagement
  {
    name: 'F1+ — specific_content_engagement (echoes user phrase)',
    input: {
      userInput: '我細個住喺深水埗。',
      assistantOutput: '深水埗嘅生活係點樣嘅？',
      agentContext: null,
      moduleId: 'm3_reminiscence',
    },
    expect: {specific_content_engagement: true},
  },
  {
    name: 'F1- — generic response (no specific anchor)',
    input: {
      userInput: '我細個住喺深水埗。',
      assistantOutput: '聽到你咁講。可唔可以講多啲？',
      agentContext: null,
      moduleId: 'm3_reminiscence',
    },
    expect: {specific_content_engagement: false},
  },

  // Flag 2: cross_session_memory
  {
    name: 'F2+ — cross_session_memory (recalls rolling summary)',
    input: {
      userInput: '今日落咗成日雨。',
      assistantOutput: '落雨令我諗起你以前喺深水埗行街市嘅日子。',
      agentContext: {
        rollingSummary: '用戶細個住喺深水埗，鍾意行街市。',
        shortTermBuffer: [],
        namedEntities: {},
      },
      moduleId: 'm3_reminiscence',
    },
    expect: {cross_session_memory: true},
  },
  {
    name: 'F2- — empty context (no callback possible)',
    input: {
      userInput: '今日落咗成日雨。',
      assistantOutput: '今日真係落得好大。',
      agentContext: {rollingSummary: '', shortTermBuffer: [], namedEntities: {}},
      moduleId: 'm3_reminiscence',
    },
    expect: {cross_session_memory: false},
  },

  // Flag 3: honest_unfamiliarity
  {
    name: 'F3+ — honest_unfamiliarity (admits ignorance)',
    input: {
      userInput: '我以前喺西貢做菠蘿包嗰陣識咗我老婆。',
      assistantOutput:
        '我未聽過你呢段故事，可唔可以同我講多啲？',
      agentContext: null,
      moduleId: 'm3_reminiscence',
    },
    expect: {honest_unfamiliarity: true},
  },
  {
    name: 'F3- — fabricates instead of admitting ignorance',
    input: {
      userInput: '我以前喺西貢做菠蘿包。',
      assistantOutput: '我都知道西貢嘅菠蘿包真係好出名！',
      agentContext: null,
      moduleId: 'm3_reminiscence',
    },
    expect: {honest_unfamiliarity: false},
  },

  // Flag 4: mixed_content_routing
  {
    name: 'F4+ — mixed_content_routing (info + affect → cross-refer)',
    input: {
      userInput: '我想知邊度有平嘅老人中心，但係我又好驚去人多嘅地方。',
      assistantOutput:
        '你又想搵地方又有少少驚，要唔要同小欣傾下嗰份驚？',
      agentContext: null,
      moduleId: 'reflective_dialogue',
    },
    expect: {mixed_content_routing: true},
  },
  {
    name: 'F4- — pure info, no affect',
    input: {
      userInput: '邊度有平嘅老人中心？',
      assistantOutput: '我可以幫你搵下。',
      agentContext: null,
      moduleId: 'reflective_dialogue',
    },
    expect: {mixed_content_routing: false},
  },

  // Flag 5: generative_summary
  {
    name: 'F5+ — generative_summary by moduleId',
    input: {
      userInput: '完咗。',
      assistantOutput: '你今日講咗深水埗嘅故事。',
      agentContext: null,
      moduleId: 'm3_summary',
    },
    expect: {generative_summary: true},
  },
  {
    name: 'F5+ — generative_summary by structural shape',
    input: {
      userInput: '完咗。',
      assistantOutput:
        '今個禮拜你完成咗兩次散步，上個禮拜你去咗社區中心，你比以前主動咗。',
      agentContext: null,
      moduleId: 'm9_weekly_narrative',
    },
    expect: {generative_summary: true},
  },
  {
    name: 'F5- — single sentence reflection, not a summary',
    input: {
      userInput: '今日好攰。',
      assistantOutput: '聽到你話攰。',
      agentContext: null,
      moduleId: 'm2_check_in',
    },
    expect: {generative_summary: false},
  },
];

let failed = 0;
for (const f of fixtures) {
  const got = computeLlmFlags(f.input);
  const errs = [];
  for (const [k, v] of Object.entries(f.expect)) {
    if (got[k] !== v) {
      errs.push(`  ${k}: expected ${v}, got ${got[k]}`);
    }
  }
  if (errs.length === 0) {
    console.log(`PASS  ${f.name}`);
  } else {
    failed++;
    console.error(`FAIL  ${f.name}`);
    for (const e of errs) console.error(e);
    console.error('  full:', JSON.stringify(got));
  }
}

if (failed > 0) {
  console.error(`\n${failed} fixture(s) failed.`);
  process.exit(1);
} else {
  console.log(`\nAll ${fixtures.length} fixtures passed.`);
}
