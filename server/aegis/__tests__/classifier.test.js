const test = require('node:test');
const assert = require('node:assert');
const { classify } = require('../classifier');
const { detect } = require('../redflags');

// Mirror of seeded kb_red_flags (subset) for pure testing.
const RULES = [
  { flagKey: 'critical_hypoxemia', label: 'Critical hypoxemia', field: 'spo2', op: 'lt', threshold: 88 },
  { flagKey: 'hypertensive_crisis_sbp', label: 'HTN crisis sys', field: 'systolic', op: 'gte', threshold: 180 },
  { flagKey: 'severe_tachycardia', label: 'Severe tachycardia', field: 'heart_rate', op: 'gte', threshold: 130 },
  { flagKey: 'severe_anemia_hb', label: 'Severe anemia', field: 'hb_estimate', op: 'lt', threshold: 7 },
  { flagKey: 'acute_coronary_pattern', label: 'ACS pattern', op: 'keywords',
    keywordGroups: [['chest pain', 'chest tightness'], ['breathless', 'dyspnea', "can't breathe"]] },
  { flagKey: 'suicidal_ideation', label: 'Suicidal ideation', op: 'keywords',
    keywordGroups: [['kill myself', 'end my life', 'suicidal']] },
];

// ── classifier ──────────────────────────────────────────────────────────────
test('low risk, no flags, reversible -> GREEN', () => {
  assert.strictEqual(classify({ riskLevel: 'low', actionType: 'show_result' }).actionClass, 'GREEN');
});

test('high risk, no flags -> AMBER', () => {
  assert.strictEqual(classify({ riskLevel: 'high', actionType: 'show_result' }).actionClass, 'AMBER');
});

test('critical risk -> RED', () => {
  assert.strictEqual(classify({ riskLevel: 'critical', actionType: 'show_result' }).actionClass, 'RED');
});

test('any red flag forces RED even at low risk', () => {
  const r = classify({ riskLevel: 'low', triggeredFlags: ['critical_hypoxemia'] });
  assert.strictEqual(r.actionClass, 'RED');
});

test('prescriptive action can never be GREEN', () => {
  assert.strictEqual(classify({ riskLevel: 'low', actionType: 'book_appointment' }).actionClass, 'AMBER');
});

test('low confidence on high risk escalates AMBER->RED', () => {
  const r = classify({ riskLevel: 'high', confidence: 0.3, actionType: 'show_result' });
  assert.strictEqual(r.actionClass, 'RED');
});

test('fail-closed: invalid riskLevel -> RED', () => {
  assert.strictEqual(classify({ riskLevel: undefined }).actionClass, 'RED');
  assert.strictEqual(classify({}).actionClass, 'RED');
  assert.strictEqual(classify({ riskLevel: 'bogus' }).actionClass, 'RED');
});

test('classifier is deterministic (same inputs -> same output, 1000x)', () => {
  const input = { riskLevel: 'high', triggeredFlags: [], confidence: 0.9, actionType: 'show_result' };
  const first = classify(input).actionClass;
  for (let i = 0; i < 1000; i++) {
    assert.strictEqual(classify(input).actionClass, first);
  }
});

test('flags accept both string and {flagKey} forms', () => {
  assert.strictEqual(classify({ riskLevel: 'low', triggeredFlags: [{ flagKey: 'severe_anemia_hb' }] }).actionClass, 'RED');
});

// ── red-flag detection ────────────────────────────────────────────────────────
test('SpO2 84 trips critical hypoxemia', () => {
  const t = detect(RULES, { inputs: { spo2: 84 } });
  assert.ok(t.find(f => f.flagKey === 'critical_hypoxemia'));
});

test('SpO2 96 trips nothing', () => {
  assert.strictEqual(detect(RULES, { inputs: { spo2: 96 } }).length, 0);
});

test('chest pain alone does NOT trip ACS (needs both groups)', () => {
  const t = detect(RULES, { text: 'I have chest pain' });
  assert.ok(!t.find(f => f.flagKey === 'acute_coronary_pattern'));
});

test('chest pain + breathless trips ACS', () => {
  const t = detect(RULES, { text: 'bad chest pain and I am breathless' });
  assert.ok(t.find(f => f.flagKey === 'acute_coronary_pattern'));
});

test('suicidal ideation phrase trips crisis flag', () => {
  const t = detect(RULES, { text: 'sometimes I want to kill myself' });
  assert.ok(t.find(f => f.flagKey === 'suicidal_ideation'));
});

test('end-to-end: SpO2 84 -> detect -> classify -> RED', () => {
  const flags = detect(RULES, { inputs: { spo2: 84 } });
  assert.strictEqual(classify({ riskLevel: 'moderate', triggeredFlags: flags }).actionClass, 'RED');
});
