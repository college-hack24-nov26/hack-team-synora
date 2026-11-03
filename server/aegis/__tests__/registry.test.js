const test = require('node:test');
const assert = require('node:assert');
const registry = require('../registry');
const { gateEvidence, FidelityError } = require('../envelopes');

test('registration fails without valid fidelity', () => {
  assert.throws(() => registry.register({ id: 'x', modality: 'm', kind: 'evidence' }, async () => ({})), /fidelity/);
  assert.throws(() => registry.register({ id: 'x', modality: 'm', kind: 'evidence', fidelity: 'bogus' }, async () => ({})), /fidelity/);
});

test('roadmap tool cannot emit a value (gate throws)', () => {
  assert.throws(
    () => gateEvidence({ value: 0.9, status: 'ok' }, { id: 'radiology', modality: 'radiology', fidelity: 'roadmap' }),
    FidelityError
  );
});

test('roadmap tool returns unavailable + null value', () => {
  const out = gateEvidence({ status: 'unavailable', value: null }, { id: 'genomics', modality: 'genomics', fidelity: 'roadmap', roadmapNote: 'no model yet' });
  assert.strictEqual(out.status, 'unavailable');
  assert.strictEqual(out.value, null);
  assert.strictEqual(out.confidence, null);
  assert.match(out.roadmapNote, /no model yet/);
});

test('heuristic confidence is capped at 0.65', () => {
  const out = gateEvidence({ confidence: 0.95, value: 0.5 }, { id: 'retina', modality: 'retina', fidelity: 'heuristic' });
  assert.strictEqual(out.confidence, 0.65);
});

test('fabricated_scale capped at 0.45 with mandatory disclaimer', () => {
  const out = gateEvidence({ confidence: 0.9, value: 9 }, { id: 'pallor', modality: 'pallor', fidelity: 'fabricated_scale' });
  assert.strictEqual(out.confidence, 0.45);
  assert.ok(out.disclaimer.length > 0);
});

test('real tool requires provenance', () => {
  assert.throws(
    () => gateEvidence({ confidence: 0.9, value: 'normal' }, { id: 'heart', modality: 'heart', fidelity: 'real' }),
    /provenance/
  );
  const ok = gateEvidence({ confidence: 0.9, value: 'normal', provenance: { model: 'cardio-tflite' } }, { id: 'heart', modality: 'heart', fidelity: 'real' });
  assert.strictEqual(ok.confidence, 0.9);
});

test('registry invoke runs handler through the gate', async () => {
  registry.reset();
  registry.register(
    { id: 'symptom.score', modality: 'symptom', kind: 'evidence', fidelity: 'heuristic', honesty: 'weighted questionnaire' },
    async (input) => ({ disease: 'anemia', value: input.n, confidence: 0.99, score: 0.5 })
  );
  const out = await registry.invoke('symptom.score', { n: 3 });
  assert.strictEqual(out.fidelity, 'heuristic');
  assert.strictEqual(out.confidence, 0.65); // capped
  assert.strictEqual(out.value, 3);
});

test('registry invoke on roadmap tool never runs handler', async () => {
  registry.reset();
  let ran = false;
  registry.register(
    { id: 'radiology.classify', modality: 'radiology', kind: 'evidence', fidelity: 'roadmap', roadmapNote: 'CXR model not integrated' },
    async () => { ran = true; return { value: 0.8 }; }
  );
  const out = await registry.invoke('radiology.classify', {});
  assert.strictEqual(ran, false);
  assert.strictEqual(out.status, 'unavailable');
});

test('list() shows availability flag', async () => {
  registry.reset();
  registry.register({ id: 'a', modality: 'a', kind: 'evidence', fidelity: 'real' }, async () => ({ value: 1, provenance: { source: 's' } }));
  registry.register({ id: 'b', modality: 'b', kind: 'evidence', fidelity: 'roadmap' }, async () => ({}));
  const l = registry.list();
  assert.strictEqual(l.find(t => t.id === 'a').available, true);
  assert.strictEqual(l.find(t => t.id === 'b').available, false);
});
