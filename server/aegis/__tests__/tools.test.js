const test = require('node:test');
const assert = require('node:assert');
const tools = require('../tools');
const registry = require('../registry');
const lab = require('../analyzers/lab');

// Minimal kb thresholds for the lab analyzer (subset of the seed).
const KB = { thresholds: [
  { disease: 'anemia', markerKey: 'hemoglobin', display: 'Hemoglobin', unit: 'g/dL', referenceRange: '', lowCritical: 8, lowCutoff: 12 },
  { disease: 'diabetes', markerKey: 'hba1c', display: 'HbA1c', unit: '%', referenceRange: '', highWarn: 5.7, highCritical: 9.0 },
]};

test('lab analyzer extracts Hb and flags severe anemia', () => {
  const r = lab.analyze({ disease: 'anemia', text: 'Hemoglobin 6.5 g/dL', thresholds: KB.thresholds });
  assert.strictEqual(r.risk, 'critical');
  assert.ok(r.findings.find(f => f.name === 'Hemoglobin' && f.flag === 'critical'));
});

test('lab analyzer: normal Hb -> low risk', () => {
  const r = lab.analyze({ disease: 'anemia', text: 'Hemoglobin 14 g/dL', thresholds: KB.thresholds });
  assert.strictEqual(r.risk, 'low');
});

test('lab analyzer: HbA1c 10 -> diabetic critical', () => {
  const r = lab.analyze({ disease: 'diabetes', text: 'HbA1c: 10.2 %', thresholds: KB.thresholds });
  assert.strictEqual(r.risk, 'critical');
});

test('lab analyzer does NOT confuse HbA1c for Hb', () => {
  // Only HbA1c present; anemia analysis should find no hemoglobin value.
  const r = lab.analyze({ disease: 'anemia', text: 'HbA1c 6.1', thresholds: KB.thresholds });
  assert.strictEqual(r.findings.length, 0);
});

test('registerAll registers the full modality surface incl. roadmap slots', () => {
  tools.reset();
  const list = tools.registerAll(KB);
  const ids = list.map(t => t.id);
  // real + heuristic + partial + fabricated + action
  for (const id of ['heart_mfcc.classify', 'lab.extract_and_score', 'symptom.score', 'vitals.assess', 'ppg.vitals_bp', 'pallor.estimate_hb', 'retina.screen_dr', 'geo.find_hospitals', 'appointment.book']) {
    assert.ok(ids.includes(id), `missing ${id}`);
  }
  // roadmap slots present + flagged unavailable
  for (const id of ['radiology.classify', 'genomics.variant_risk', 'ecg.classify', 'notify.message', 'calendar.followup']) {
    const t = list.find(x => x.id === id);
    assert.ok(t, `missing roadmap ${id}`);
    assert.strictEqual(t.available, false);
  }
});

test('invoking the lab tool runs the port through the fidelity gate (capped)', async () => {
  tools.reset();
  tools.registerAll(KB);
  const out = await registry.invoke('lab.extract_and_score', { disease: 'anemia', text: 'Hemoglobin 6 g/dL' });
  assert.strictEqual(out.fidelity, 'heuristic');
  assert.ok(out.confidence <= 0.65);
  assert.strictEqual(out.disease, 'anemia');
});

test('invoking a roadmap tool returns unavailable, never a value', async () => {
  tools.reset();
  tools.registerAll(KB);
  const out = await registry.invoke('radiology.classify', { image: 'whatever' });
  assert.strictEqual(out.status, 'unavailable');
  assert.strictEqual(out.value, null);
});
