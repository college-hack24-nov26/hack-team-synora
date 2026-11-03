const test = require('node:test');
const assert = require('node:assert');
const { canonical, computeRowHash, verifyChain, digestInputs } = require('../ledger');

function makeRow(seq, decisionType, extra = {}) {
  return {
    episodeId: null, patientId: 'p1', seq, decisionType,
    rationale: `step ${seq}`, ...extra,
  };
}

/** Build a valid chain of n rows the way append() would. */
function buildChain(n) {
  const rows = [];
  let prev = '';
  for (let i = 0; i < n; i++) {
    const row = makeRow(i, 'evidence_recorded');
    row.prevHash = prev;
    row.hash = computeRowHash(row, prev);
    rows.push(row);
    prev = row.hash;
  }
  return rows;
}

test('canonical is key-order independent', () => {
  assert.strictEqual(canonical({ a: 1, b: 2 }), canonical({ b: 2, a: 1 }));
});

test('digestInputs is deterministic and order-independent', () => {
  assert.strictEqual(digestInputs({ spo2: 84, hr: 130 }), digestInputs({ hr: 130, spo2: 84 }));
  assert.notStrictEqual(digestInputs({ spo2: 84 }), digestInputs({ spo2: 85 }));
});

test('a clean chain verifies', () => {
  const rows = buildChain(5);
  assert.deepStrictEqual(verifyChain(rows), { ok: true, brokenAtSeq: null });
});

test('tampering with a middle row breaks the chain at that seq', () => {
  const rows = buildChain(5);
  rows[2].rationale = 'TAMPERED'; // edit content without recomputing hash
  const res = verifyChain(rows);
  assert.strictEqual(res.ok, false);
  assert.strictEqual(res.brokenAtSeq, 2);
});

test('re-hashing a tampered row alone still breaks downstream (prevHash mismatch)', () => {
  const rows = buildChain(5);
  // Attacker edits row 2 AND recomputes its hash, but cannot fix row 3's prevHash
  rows[2].rationale = 'TAMPERED';
  rows[2].hash = computeRowHash(rows[2], rows[2].prevHash);
  // row 3 still chains off the OLD row-2 hash, so verification fails at 3
  const res = verifyChain(rows);
  assert.strictEqual(res.ok, false);
  assert.strictEqual(res.brokenAtSeq, 3);
});

test('the overridden flag is outside hashed content (flip does not break chain)', () => {
  const rows = buildChain(3);
  rows[1].overridden = true; // sanctioned mutation, not part of computeRowHash content
  assert.deepStrictEqual(verifyChain(rows), { ok: true, brokenAtSeq: null });
});

test('aegis_classification rows carry verdict fields into the hash', () => {
  const a = makeRow(0, 'aegis_classification', { actionClass: 'RED', triggeredFlags: ['critical_hypoxemia'], riskLevel: 'critical' });
  const b = makeRow(0, 'aegis_classification', { actionClass: 'GREEN', triggeredFlags: [], riskLevel: 'low' });
  assert.notStrictEqual(computeRowHash(a, ''), computeRowHash(b, ''));
});
