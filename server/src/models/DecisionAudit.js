const mongoose = require('mongoose');

/**
 * decision_audit — the append-only, hash-chained record of every autonomous
 * decision and every Aegis gate verdict. This is BOTH the spec's "evidence
 * ledger" and "decision audit" (merged into one collection per the spec's
 * reconciliation note).
 *
 * Tamper-evidence: each row stores `prevHash` (the hash of the prior row for
 * the same episode) and `hash` (sha256 over this row's canonical content +
 * prevHash). Any retroactive edit breaks the chain — verifiable by replay.
 *
 * Append-only discipline: rows are NEVER updated in place. A correction
 * (doctor override) writes a NEW row referencing the original via
 * `correctsSeq`, and flips the original's `overridden` flag through the one
 * sanctioned mutation path (see ledger.recordOverride).
 */
const decisionAuditSchema = new mongoose.Schema({
  episodeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Episode', default: null, index: true },
  patientId: { type: String, required: true, index: true },

  seq: { type: Number, required: true },          // monotonic per episode (or per patient if no episode)

  decisionType: {
    type: String,
    required: true,
    // what produced this row
    enum: [
      'evidence_recorded',     // a screening result was logged
      'aegis_classification',  // GREEN/AMBER/RED verdict
      'action_executed',       // a side-effecting action ran
      'action_blocked',        // RED — action withheld pending human
      'clinician_decision',    // APPROVE / MODIFY / OVERRIDE / ESCALATE
      'followup_scheduled',
    ],
  },

  // Aegis verdict fields (present when decisionType == 'aegis_classification')
  actionClass: { type: String, enum: ['GREEN', 'AMBER', 'RED', null], default: null },
  triggeredFlags: { type: [String], default: [] },
  riskLevel: { type: String, enum: ['low', 'moderate', 'high', 'critical', null], default: null },

  rationale: { type: String, default: '' },
  inputDigest: { type: String, default: '' },     // sha256 of the inputs the decision saw

  decidedBy: { type: String, default: 'rule_engine' }, // 'rule_engine' | 'clinician' | 'agent'
  autonomous: { type: Boolean, default: true },
  clinicianId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },

  model: { type: String, default: '' },           // LLM/model name if any was involved
  kbVersion: { type: String, default: '' },        // KB version stamp — reproducibility
  rulesVersion: { type: String, default: '' },

  // Correction linkage (append-only override)
  overridden: { type: Boolean, default: false },
  correctsSeq: { type: Number, default: null },

  // Hash chain
  prevHash: { type: String, default: '' },
  hash: { type: String, required: true },
}, { timestamps: true });

// Append-only chain key: one seq per episode chain.
decisionAuditSchema.index({ episodeId: 1, seq: 1 }, { unique: true, partialFilterExpression: { episodeId: { $type: 'objectId' } } });
// Patient-wide chain (episodeId: null) MUST also be unique on (patientId, seq),
// otherwise concurrent patient-wide appends could write duplicate seqs and fork
// the hash chain. Scope the uniqueness to rows where episodeId is null so it
// doesn't clash with episode-scoped rows.
decisionAuditSchema.index(
  { patientId: 1, seq: 1 },
  { unique: true, partialFilterExpression: { episodeId: null } }
);

module.exports = mongoose.model('DecisionAudit', decisionAuditSchema);
