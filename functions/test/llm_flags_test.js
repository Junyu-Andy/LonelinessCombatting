/**
 * B.1 — golden-file regression for the LLM flag detector.
 *
 * Run with:  cd functions && node test/llm_flags_test.js
 *
 * Five hand-crafted M3 turns covering each flag's positive + negative case.
 * Update the fixture (and bump _version in llm_flags.js) when heuristics
 * intentionally change; never silently when a flag flips.
 */

'use strict';

const assert = require('assert');
const {computeLlmFlags} = require('../llm_flags');

const fixtures = [
  {
    name: 'F1 — empathic + open question (Siu Yan typical)',
    input: {
      userInput: '今日返到屋企，個屋好靜。',
      assistantOutput: '我聽到你話屋企好靜。今日邊個時候你最覺得個靜？',
      agentContext: null,
    },
    expect: {
      empathic_reflection: true,
      open_question: true,
      personalization_specific: false,
      memory_callback: false,
      adaptive_register: true,
    },
  },
  {
    name: 'F2 — personalization specific (named entity from input)',
    input: {
      userInput: '我尋日見咗阿明，佢仲記得我細個嘅樣。',
      assistantOutput: '阿明仲記得你細個嘅樣。嗰陣你哋傾咗啲咩？',
      agentContext: null,
    },
    expect: {
      personalization_specific: true,
      open_question: true,
      empathic_reflection: false,
    },
  },
  {
    name: 'F3 — memory callback from rolling summary',
    input: {
      userInput: '今日落咗成日雨。',
      assistantOutput: '深水埗呢個時候令你諗起邊個時期？',
      agentContext: {
        rollingSummary: '用戶細個住喺深水埗，鍾意行街市。',
        shortTermBuffer: [],
        namedEntities: {},
      },
    },
    expect: {
      memory_callback: true,
      open_question: true,
    },
  },
  {
    name: 'F4 — over-pathologized (FAIL adaptive_register)',
    input: {
      userInput: '今日落咗成日雨。',  // neutral
      assistantOutput:
        '請即刻打 999 求助，我好擔心你。',  // crisis register, no warrant
      agentContext: null,
    },
    expect: {
      adaptive_register: false,
      empathic_reflection: false,
    },
  },
  {
    name: 'F5 — yes/no closer (FAIL open_question)',
    input: {
      userInput: '我幾好。',
      assistantOutput: '係咪今日心情好啲？',
      agentContext: null,
    },
    expect: {
      open_question: false,
    },
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
