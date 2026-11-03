const test = require('node:test');
const assert = require('node:assert');
const { reopenDecision, assembleContext } = require('../memory');

const NOW = Date.parse('2026-06-14T10:00:00Z');
const daysAgo = (d) => new Date(NOW - d * 86400000).toISOString();

test('no prior episode -> fresh', () => {
  assert.strictEqual(reopenDecision(null, { primaryDisease: 'anemia', now: NOW }), 'fresh');
});

test('recent + same disease -> reopen', () => {
  const latest = { updatedAt: daysAgo(5), currentAssessment: { primaryDisease: 'anemia' } };
  assert.strictEqual(reopenDecision(latest, { primaryDisease: 'anemia', now: NOW }), 'reopen');
});

test('old episode -> child', () => {
  const latest = { updatedAt: daysAgo(60), currentAssessment: { primaryDisease: 'anemia' } };
  assert.strictEqual(reopenDecision(latest, { primaryDisease: 'anemia', now: NOW }), 'child');
});

test('recent but different disease -> child', () => {
  const latest = { updatedAt: daysAgo(3), currentAssessment: { primaryDisease: 'diabetes' } };
  assert.strictEqual(reopenDecision(latest, { primaryDisease: 'anemia', now: NOW }), 'child');
});

test('assembleContext includes facts, summary and current observations', () => {
  const ctx = assembleContext({
    memory: {
      facts: [{ active: true, category: 'condition', key: 'anemia_history', value: 'iron-deficiency 2024' }],
      cachedSummary: 'Recurrent mild anemia.',
      riskTimeline: [{ disease: 'anemia', risk: 'moderate', score: 0.5, at: daysAgo(10) }],
    },
    currentEpisode: {
      chiefComplaint: 'tired and dizzy', status: 'open',
      currentAssessment: { summary: 'Anemia screening suggested' },
      observations: [{ modality: 'pallor', disease: 'anemia', risk: 'high', confidence: 0.45, fidelity: 'fabricated_scale' }],
    },
    relatedEpisodes: [],
  });
  assert.match(ctx, /KNOWN PATIENT FACTS/);
  assert.match(ctx, /iron-deficiency 2024/);
  assert.match(ctx, /CURRENT EPISODE/);
  assert.match(ctx, /pallor anemia: high/);
  assert.match(ctx, /tired and dizzy/);
});

test('assembleContext handles empty memory gracefully', () => {
  const ctx = assembleContext({ memory: null, currentEpisode: null, relatedEpisodes: [] });
  assert.strictEqual(typeof ctx, 'string');
});
