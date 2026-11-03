/**
 * Aegis service — binds the pure gate to real MongoDB-backed dependencies.
 * This is what the HTTP routes call. Real action executors are injected so
 * the same gate can book appointments, fire alerts, etc.
 */
const ledger = require('./ledger');
const gate = require('./gate');
const kbLoader = require('./kb');

const ClinicianCase = require('../src/models/ClinicianCase');
const ActionDedup = require('../src/models/ActionDedup');
const MentalHealthNotification = require('../src/models/MentalHealthNotification');

/** Default real executors for known action types. Extend as tools land. */
const EXECUTORS = {
  // GREEN/AMBER reversible actions
  show_result: async (p) => ({ shown: true, summary: p.payload?.summary || '' }),
  save_record: async (p) => ({ saved: true }),
  suggest_screening: async (p) => ({ suggested: p.payload?.screening || null }),
  schedule_routine_followup: async (p) => ({ followUpDueAt: p.payload?.dueAt || null }),
  // AMBER consequential (allowed, but never GREEN)
  book_appointment: async (p) => ({ booked: true, payload: p.payload || {} }),
  // Mental-health review: the informational half (record the review intent).
  // A RED verdict blocks this and opens a ClinicianCase instead.
  mental_health_review: async (p) => ({ reviewed: true, summary: p.summary || '' }),
};

async function execute(proposal) {
  const fn = EXECUTORS[proposal.actionType];
  if (!fn) return { executed: false, note: `no executor for ${proposal.actionType}` };
  return fn(proposal);
}

async function notifyDoctor(proposal, verdict) {
  if (!proposal.doctorId) return;
  await MentalHealthNotification.create({
    doctorId: proposal.doctorId,
    patientId: proposal.patientId,
    patientName: proposal.patientName || 'Patient',
    clinicalReport:
      `[Aegis ${verdict.actionClass}] ${proposal.summary || proposal.actionType}\n` +
      `Reasons: ${verdict.reasons.join('; ')}`,
    urgency: verdict.actionClass === 'RED' ? 'high' : 'moderate',
  });
}

async function openCase(proposal, verdict, meta) {
  // Singleton per (patient, flagset, day) — upsert on dedupeKey.
  const slaDeadline = new Date(Date.now() + 15 * 60 * 1000); // 15-min SLA
  const doc = {
    patientId: proposal.patientId,
    patientName: proposal.patientName || '',
    doctorId: proposal.doctorId || null,
    episodeId: proposal.episodeId || null,
    status: 'AWAITING_REVIEW',
    triggeredFlags: verdict.triggeredFlags.map(f => f.flagKey || f),
    riskLevel: proposal.riskLevel,
    proposedAction: {
      actionType: proposal.actionType,
      payload: proposal.payload || {},
      rationale: verdict.reasons.join('; '),
      // Persist the evaluation inputs so an APPROVE/MODIFY can re-run the SAME
      // proposal back through the gate (0.2) instead of trusting a stored verdict.
      inputs: proposal.inputs || {},
      text: proposal.text || '',
      confidence: proposal.confidence,
    },
    summary: proposal.summary || 'Screening signal requires clinical review (non-diagnostic).',
    auditSeq: meta.auditSeq,
    slaDeadline,
    dedupeKey: meta.dedupeKey,
  };
  try {
    // Atomic singleton-or-fetch on the unique dedupeKey: inserts a new case or
    // returns the existing one for this (patient, flagset, day). $setOnInsert
    // means an existing case is returned UNMODIFIED — the frozen proposal is
    // never silently overwritten, which is the human-in-the-loop guarantee.
    return await ClinicianCase.findOneAndUpdate(
      { dedupeKey: meta.dedupeKey },
      { $setOnInsert: doc },
      { upsert: true, new: true }
    );
  } catch (e) {
    // Lost the insert race against a concurrent caller (duplicate-key on the
    // unique index). The winner's document exists now — fetch and return it.
    return ClinicianCase.findOne({ dedupeKey: meta.dedupeKey });
  }
}

const deps = {
  ledgerAppend: (entry) => ledger.append(entry),
  execute,
  notifyDoctor,
  openCase,
  dedupGet: (key) => ActionDedup.findOne({ idempotencyKey: key }).lean(),
  dedupPut: async (key, status, result, proposal) => {
    await ActionDedup.findOneAndUpdate(
      { idempotencyKey: key },
      { $set: { status, result, actionType: proposal.actionType, patientId: proposal.patientId } },
      { upsert: true }
    );
  },
};

/** Main entry: run a proposal through the gate with real deps. */
async function submit(proposal) {
  const kb = await kbLoader.load();
  return gate.process(proposal, kb, deps);
}

module.exports = { submit, EXECUTORS, _deps: deps };
