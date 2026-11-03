const test = require('node:test');
const assert = require('node:assert');
const gate = require('../gate');
const { lint, ensureDisclaimer } = require('../guardrail');

const KB = {
  kbVersion: 'kb-2026-06', rulesVersion: 'rules-1',
  redFlagRules: [
    { flagKey: 'critical_hypoxemia', field: 'spo2', op: 'lt', threshold: 88 },
    { flagKey: 'acute_coronary_pattern', op: 'keywords',
      keywordGroups: [['chest pain'], ['breathless', 'dyspnea']] },
  ],
};

function mockDeps(overrides = {}) {
  const ledger = [];
  const cases = [];
  const dedup = new Map();
  let notified = 0;
  let executed = 0;
  return {
    spy: { ledger, cases, get notified() { return notified; }, get executed() { return executed; }, dedup },
    deps: {
      now: () => Date.parse('2026-06-14T10:00:00Z'),
      ledgerAppend: async (e) => { const row = { ...e, seq: ledger.length }; ledger.push(row); return row; },
      execute: async () => { executed++; return { booked: true, id: 'appt1' }; },
      notifyDoctor: async () => { notified++; },
      openCase: async (proposal, verdict, meta) => { const c = { proposal, verdict, meta, status: 'AWAITING_REVIEW' }; cases.push(c); return c; },
      dedupGet: async (k) => dedup.get(k) || null,
      dedupPut: async (k, status, result) => dedup.set(k, { status, result }),
      ...overrides,
    },
  };
}

// ── evaluate (pure) ──
test('evaluate: low risk reversible -> EXECUTE/GREEN', () => {
  const v = gate.evaluate({ patientId: 'p', riskLevel: 'low', actionType: 'show_result' }, KB);
  assert.strictEqual(v.actionClass, 'GREEN');
  assert.strictEqual(v.disposition, 'EXECUTE');
});

test('evaluate: high risk -> AMBER / EXECUTE_AND_NOTIFY', () => {
  const v = gate.evaluate({ patientId: 'p', riskLevel: 'high', actionType: 'show_result' }, KB);
  assert.strictEqual(v.disposition, 'EXECUTE_AND_NOTIFY');
});

test('evaluate: red flag -> RED / BLOCK', () => {
  const v = gate.evaluate({ patientId: 'p', riskLevel: 'moderate', inputs: { spo2: 84 }, actionType: 'book_appointment' }, KB);
  assert.strictEqual(v.actionClass, 'RED');
  assert.strictEqual(v.disposition, 'BLOCK');
});

// ── process (effects) ──
test('process GREEN executes and ledgers', async () => {
  const { spy, deps } = mockDeps();
  const r = await gate.process({ patientId: 'p', riskLevel: 'low', actionType: 'show_result', inputs: {} }, KB, deps);
  assert.strictEqual(r.executed, true);
  assert.strictEqual(spy.executed, 1);
  assert.ok(spy.ledger.find(e => e.decisionType === 'aegis_classification'));
  assert.ok(spy.ledger.find(e => e.decisionType === 'action_executed'));
});

test('process AMBER executes AND notifies doctor', async () => {
  const { spy, deps } = mockDeps();
  const r = await gate.process({ patientId: 'p', riskLevel: 'high', actionType: 'book_appointment', inputs: { systolic: 135 } }, KB, deps);
  assert.strictEqual(r.executed, true);
  await new Promise(res => setImmediate(res)); // let non-blocking notify run
  assert.strictEqual(spy.notified, 1);
});

test('process RED blocks (no execute) and opens a clinician case', async () => {
  const { spy, deps } = mockDeps();
  const r = await gate.process({ patientId: 'p', riskLevel: 'moderate', actionType: 'book_appointment', inputs: { spo2: 84 } }, KB, deps);
  assert.strictEqual(r.executed, false);
  assert.strictEqual(spy.executed, 0);                 // action NEVER ran
  assert.strictEqual(spy.cases.length, 1);
  assert.ok(spy.ledger.find(e => e.decisionType === 'action_blocked'));
});

test('idempotency: replaying the same action does not double-execute', async () => {
  const { spy, deps } = mockDeps();
  const p = { patientId: 'p', riskLevel: 'low', actionType: 'book_appointment', inputs: { slot: 'tomorrow 10am' } };
  await gate.process(p, KB, deps);
  await gate.process(p, KB, deps); // replay
  assert.strictEqual(spy.executed, 1); // executed exactly once
});

test('RED chest-pain+dyspnea text blocks', async () => {
  const { spy, deps } = mockDeps();
  const r = await gate.process({ patientId: 'p', riskLevel: 'moderate', actionType: 'book_appointment', text: 'chest pain and very breathless', inputs: {} }, KB, deps);
  assert.strictEqual(r.actionClass, 'RED');
  assert.strictEqual(spy.executed, 0);
});

// ── guardrail lint ──
test('lint flags a diagnostic claim', () => {
  assert.strictEqual(lint('Based on this, you have diabetes.').ok, false);
});
test('lint flags a prescription', () => {
  assert.strictEqual(lint('Take 500 mg twice daily.').ok, false);
});
test('lint flags aspirational citation', () => {
  assert.strictEqual(lint('Trained on the APTOS dataset.').ok, false);
});
test('lint passes screening framing', () => {
  assert.strictEqual(lint('This screening signal suggests elevated risk; please see a clinician.').ok, true);
});
test('ensureDisclaimer appends once', () => {
  const out = ensureDisclaimer('Your result is elevated.');
  assert.ok(out.includes('not a diagnosis'));
  assert.strictEqual(ensureDisclaimer(out), out); // idempotent
});
