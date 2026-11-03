/**
 * Aegis ledger — the ONLY sanctioned write path for decision_audit.
 *
 * Guarantees:
 *   - append-only (no in-place edits except the one override flag flip)
 *   - hash-chained per episode (tamper-evident)
 *   - monotonic seq per episode
 *
 * The hashing/canonicalization functions are pure and exported separately so
 * they can be unit-tested with NO database (see aegis/__tests__/ledger.test.js).
 */
const crypto = require('crypto');

function sha256(s) {
  return crypto.createHash('sha256').update(s, 'utf8').digest('hex');
}

/** Stable JSON: keys sorted, so the same content always hashes the same. */
function canonical(obj) {
  if (obj === null || typeof obj !== 'object') return JSON.stringify(obj);
  if (Array.isArray(obj)) return '[' + obj.map(canonical).join(',') + ']';
  const keys = Object.keys(obj).sort();
  return '{' + keys.map(k => JSON.stringify(k) + ':' + canonical(obj[k])).join(',') + '}';
}

function digestInputs(inputs) {
  return sha256(canonical(inputs ?? {}));
}

/**
 * Compute the hash for a row given its content and the previous row's hash.
 * Pure — used both at write time and at verification time.
 */
function computeRowHash(row, prevHash) {
  const content = {
    episodeId: row.episodeId ? String(row.episodeId) : null,
    patientId: row.patientId,
    seq: row.seq,
    decisionType: row.decisionType,
    actionClass: row.actionClass ?? null,
    triggeredFlags: row.triggeredFlags ?? [],
    riskLevel: row.riskLevel ?? null,
    rationale: row.rationale ?? '',
    inputDigest: row.inputDigest ?? '',
    decidedBy: row.decidedBy ?? 'rule_engine',
    autonomous: row.autonomous ?? true,
    clinicianId: row.clinicianId ? String(row.clinicianId) : null,
    model: row.model ?? '',
    kbVersion: row.kbVersion ?? '',
    rulesVersion: row.rulesVersion ?? '',
    correctsSeq: row.correctsSeq ?? null,
  };
  return sha256(prevHash + '|' + canonical(content));
}

/**
 * Verify a chain (array of rows ordered by seq) is intact. Returns
 * { ok, brokenAtSeq }.  Pure — no DB.
 */
function verifyChain(rows) {
  let prev = '';
  for (const row of rows) {
    const expected = computeRowHash(row, prev);
    if (expected !== row.hash) return { ok: false, brokenAtSeq: row.seq };
    prev = row.hash;
  }
  return { ok: true, brokenAtSeq: null };
}

// ── DB-bound append (kept thin; logic above is what's tested) ────────────────
let DecisionAudit, LedgerCounter;
function model() {
  if (!DecisionAudit) DecisionAudit = require('../src/models/DecisionAudit');
  return DecisionAudit;
}
function counter() {
  if (!LedgerCounter) LedgerCounter = require('../src/models/LedgerCounter');
  return LedgerCounter;
}

/** Stable chain key per (episode | patient-wide) chain. */
function chainKey(episodeId, patientId) {
  return episodeId ? `ep:${String(episodeId)}` : `pt:${String(patientId)}`;
}

/**
 * DEPRECATED (non-atomic). Retained for back-compat / tests only. The live
 * append() path allocates seq atomically via LedgerCounter — do NOT use this
 * to compute a seq for a real write, it races under concurrency.
 */
async function nextSeqAndPrevHash(episodeId, patientId) {
  const M = model();
  const q = episodeId ? { episodeId } : { patientId, episodeId: null };
  const last = await M.findOne(q).sort({ seq: -1 }).lean();
  return {
    seq: last ? last.seq + 1 : 0,
    prevHash: last ? last.hash : '',
  };
}

/**
 * Append one row. seq is allocated ATOMICALLY from LedgerCounter so concurrent
 * appends never collide on a seq (the root cause of forked/broken chains).
 * prevHash is the hash of seq-1 for this chain (empty for seq 0). Returns the
 * saved doc. The unique index on the chain key + seq is the final backstop.
 */
async function append(entry) {
  const M = model();
  const C = counter();
  const episodeId = entry.episodeId || null;
  const key = chainKey(episodeId, entry.patientId);

  // 0) Bootstrap the counter from any pre-existing rows (no migration needed):
  //    if no counter doc exists yet but the chain already has rows (e.g. data
  //    written before this counter was introduced), seed maxSeq from the real
  //    max so we don't reallocate seq 0 and collide. Idempotent + race-safe:
  //    $setOnInsert only seeds on the very first upsert; concurrent callers
  //    that lose the insert race fall through to the atomic $inc below.
  const existing = await C.findOne({ _id: key }).select('_id').lean();
  if (!existing) {
    const q = episodeId ? { episodeId } : { patientId: entry.patientId, episodeId: null };
    const last = await M.findOne(q).sort({ seq: -1 }).select('seq').lean();
    await C.updateOne(
      { _id: key },
      { $setOnInsert: { maxSeq: last ? last.seq : -1 } },
      { upsert: true }
    );
  }

  // 1) Atomically reserve the next seq for this chain.
  const c = await C.findOneAndUpdate(
    { _id: key },
    { $inc: { maxSeq: 1 } },
    { upsert: true, new: true, setDefaultsOnInsert: true }
  );
  const seq = c.maxSeq;

  // 2) Fetch the predecessor's hash to chain onto. For seq 0 there is none.
  let prevHash = '';
  if (seq > 0) {
    const q = episodeId ? { episodeId, seq: seq - 1 } : { patientId: entry.patientId, episodeId: null, seq: seq - 1 };
    const prev = await M.findOne(q).select('hash').lean();
    prevHash = prev ? prev.hash : '';
  }

  const row = { ...entry, episodeId, seq, prevHash };
  row.hash = computeRowHash(row, prevHash);
  return M.create(row);
}

/**
 * Record a clinician override of a prior decision. Append-only: writes a NEW
 * corrective row AND flips the original's `overridden` flag (the one
 * sanctioned mutation — the flag is outside the hashed content so it doesn't
 * break the chain).
 */
async function recordOverride({ episodeId, patientId, correctsSeq, clinicianId, rationale, kbVersion, rulesVersion }) {
  const M = model();
  const corrective = await append({
    episodeId: episodeId || null,
    patientId,
    decisionType: 'clinician_decision',
    decidedBy: 'clinician',
    autonomous: false,
    clinicianId,
    rationale,
    correctsSeq,
    kbVersion: kbVersion || '',
    rulesVersion: rulesVersion || '',
  });
  const q = episodeId ? { episodeId, seq: correctsSeq } : { patientId, episodeId: null, seq: correctsSeq };
  // The corrective row above is the chain-integrity-critical write and is now
  // durable. Flipping `overridden` is a non-hashed convenience flag; if it
  // fails we must NOT silently proceed (the audit view would mislead), so
  // surface it loudly. Use a transaction when the deployment supports one.
  const res = await M.updateOne(q, { $set: { overridden: true } });
  if (!res || res.matchedCount === 0) {
    console.error(`recordOverride: corrective row appended but original seq=${correctsSeq} not found to flag overridden (chain=${chainKey(episodeId, patientId)})`);
  }
  return corrective;
}

async function chainFor(episodeId, patientId) {
  const M = model();
  const q = episodeId ? { episodeId } : { patientId, episodeId: null };
  return M.find(q).sort({ seq: 1 }).lean();
}

module.exports = {
  sha256, canonical, digestInputs, computeRowHash, verifyChain,  // pure
  append, recordOverride, chainFor, nextSeqAndPrevHash,          // db-bound
};
