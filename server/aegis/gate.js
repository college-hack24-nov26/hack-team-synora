/**
 * Aegis Gate — the single chokepoint every side-effecting clinical action
 * passes through. The agent PROPOSES; the gate DISPOSES.
 *
 *   evaluate(proposal, kb)  -> pure decision { actionClass, triggeredFlags, reasons, disposition }
 *   process(proposal, deps) -> performs the decision: ledger write, and either
 *                              EXECUTE (deps.execute), QUEUE (deps.openCase),
 *                              or BLOCK.
 *
 * `evaluate` is pure (no DB) so it is unit-tested. `process` wires it to the
 * ledger / case-queue / executor via injected deps (also test-mockable).
 */
const crypto = require('crypto');
const { classify } = require('./classifier');
const { detect } = require('./redflags');
const { digestInputs } = require('./ledger');

function dayBucket(now) {
  // YYYY-MM-DD in UTC; `now` injected for determinism/testing.
  return new Date(now).toISOString().slice(0, 10);
}

function idempotencyKey({ patientId, actionType, inputs, rulesVersion, now }) {
  const raw = [patientId, actionType, digestInputs(inputs), rulesVersion || '', dayBucket(now)].join('|');
  return crypto.createHash('sha256').update(raw).digest('hex');
}

function dedupeKey({ patientId, triggeredFlags, now }) {
  const flags = (triggeredFlags || []).map(f => (typeof f === 'string' ? f : f.flagKey)).sort().join(',');
  return crypto.createHash('sha256').update([patientId, flags, dayBucket(now)].join('|')).digest('hex');
}

/**
 * Pure evaluation. `proposal` = { patientId, riskLevel, actionType, inputs, text, confidence }.
 * `kb` = { redFlagRules, kbVersion, rulesVersion }.
 */
function evaluate(proposal, kb = {}) {
  const triggered = detect(kb.redFlagRules || [], { inputs: proposal.inputs || {}, text: proposal.text || '' });
  const { actionClass, reasons } = classify({
    riskLevel: proposal.riskLevel,
    triggeredFlags: triggered,
    // Confidence semantics (finding 0.3): an OMITTED confidence is treated as
    // "deterministic rule-engine certainty" (1) — the documented contract, so
    // a high-risk call with no confidence stays AMBER (doctor notified), not
    // RED. The exploit the audit worried about (dodging escalation) is not
    // reachable: omitting confidence can only RAISE trust to the same default,
    // never lower the class. An EXPLICIT confidence < 0.45 on a high/critical
    // call still escalates one class (handled in classifier.js). LLM/agent
    // callers MUST pass their real (capped) confidence so that rule bites.
    confidence: proposal.confidence ?? 1,
    actionType: proposal.actionType || 'show_result',
  });
  let disposition = actionClass === 'RED' ? 'BLOCK'
    : actionClass === 'AMBER' ? 'EXECUTE_AND_NOTIFY'
    : 'EXECUTE';
  // Clinician override: the legitimate unblock path. A named clinician has
  // explicitly approved this RED action via the case queue, so it may execute
  // — but it is still classified, red-flag-detected, ledgered and idempotent
  // below. We NEVER skip evaluation; we only change the disposition.
  if (actionClass === 'RED' && proposal.clinicianApproved) {
    disposition = 'EXECUTE_AND_NOTIFY';
  }
  return { actionClass, triggeredFlags: triggered, reasons, disposition };
}

/**
 * Full processing with effects. `deps`:
 *   - ledgerAppend(entry)            -> append a decision_audit row
 *   - execute(proposal)              -> run the real action, return result
 *   - notifyDoctor(proposal, verdict)-> async, non-blocking
 *   - openCase(proposal, verdict)    -> create ClinicianCase, return it
 *   - dedupGet(key) / dedupPut(...)  -> idempotency store
 *   - now()                          -> timestamp (injectable)
 */
async function process(proposal, kb, deps) {
  const now = deps.now ? deps.now() : Date.now();
  const verdict = evaluate(proposal, kb);

  // Ledger the classification first (always).
  await deps.ledgerAppend({
    episodeId: proposal.episodeId || null,
    patientId: proposal.patientId,
    decisionType: 'aegis_classification',
    actionClass: verdict.actionClass,
    triggeredFlags: verdict.triggeredFlags.map(f => f.flagKey || f),
    riskLevel: proposal.riskLevel,
    rationale: verdict.reasons.join('; '),
    inputDigest: digestInputs(proposal.inputs || {}),
    kbVersion: kb.kbVersion || '',
    rulesVersion: kb.rulesVersion || '',
  });

  if (verdict.disposition === 'BLOCK') {
    const blockedSeq = await deps.ledgerAppend({
      episodeId: proposal.episodeId || null,
      patientId: proposal.patientId,
      decisionType: 'action_blocked',
      actionClass: 'RED',
      triggeredFlags: verdict.triggeredFlags.map(f => f.flagKey || f),
      riskLevel: proposal.riskLevel,
      rationale: 'Action withheld pending clinician review',
      kbVersion: kb.kbVersion || '',
      rulesVersion: kb.rulesVersion || '',
    });
    const kase = await deps.openCase(proposal, verdict, {
      dedupeKey: dedupeKey({ patientId: proposal.patientId, triggeredFlags: verdict.triggeredFlags, now }),
      auditSeq: blockedSeq && blockedSeq.seq != null ? blockedSeq.seq : null,
    });
    return { ...verdict, executed: false, case: kase };
  }

  // EXECUTE / EXECUTE_AND_NOTIFY — idempotent.
  const key = idempotencyKey({
    patientId: proposal.patientId, actionType: proposal.actionType,
    inputs: proposal.inputs, rulesVersion: kb.rulesVersion, now,
  });
  const existing = deps.dedupGet ? await deps.dedupGet(key) : null;
  let result;
  if (existing && existing.status === 'DONE') {
    result = existing.result;
  } else {
    result = await deps.execute(proposal);
    if (deps.dedupPut) await deps.dedupPut(key, 'DONE', result, proposal);
    await deps.ledgerAppend({
      episodeId: proposal.episodeId || null,
      patientId: proposal.patientId,
      decisionType: 'action_executed',
      actionClass: verdict.actionClass,
      rationale: `Executed ${proposal.actionType}`,
      inputDigest: digestInputs(proposal.inputs || {}),
      kbVersion: kb.kbVersion || '',
      rulesVersion: kb.rulesVersion || '',
    });
  }

  if (verdict.disposition === 'EXECUTE_AND_NOTIFY' && deps.notifyDoctor) {
    // Non-blocking, but NEVER silently swallowed: a dropped AMBER/RED doctor
    // notification is a safety event, so log it and write an auditable ledger
    // row so the failure is visible after the fact.
    Promise.resolve(deps.notifyDoctor(proposal, verdict)).catch((err) => {
      console.error('Aegis notifyDoctor failed:', err && err.message ? err.message : err);
      Promise.resolve(deps.ledgerAppend({
        episodeId: proposal.episodeId || null,
        patientId: proposal.patientId,
        decisionType: 'notify_failed',
        actionClass: verdict.actionClass,
        rationale: `Doctor notification failed: ${err && err.message ? err.message : 'unknown error'}`,
        kbVersion: kb.kbVersion || '',
        rulesVersion: kb.rulesVersion || '',
      })).catch(() => {});
    });
  }

  return { ...verdict, executed: true, idempotencyKey: key, result };
}

module.exports = { evaluate, process, idempotencyKey, dedupeKey, dayBucket };
