const mongoose = require('mongoose');

/**
 * ClinicianCase — opened when Aegis classifies an action RED. The proposed
 * action is FROZEN (snapshot) and never dispatched until a clinician acts.
 * No autonomous timeout-to-execute: an SLA breach escalates, never
 * auto-approves (fail-closed). Extends the role of MentalHealthNotification
 * into a general human-in-the-loop queue.
 */
const clinicianCaseSchema = new mongoose.Schema({
  patientId: { type: String, required: true, index: true },
  patientName: { type: String, default: '' },
  doctorId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null, index: true },
  episodeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Episode', default: null },

  status: {
    type: String,
    enum: ['AWAITING_REVIEW', 'APPROVED', 'MODIFIED', 'OVERRIDDEN', 'ESCALATED'],
    default: 'AWAITING_REVIEW',
    index: true,
  },

  triggeredFlags: { type: [String], default: [] },
  riskLevel: { type: String, enum: ['low', 'moderate', 'high', 'critical'], default: 'critical' },

  // The frozen proposal — exactly what would have run if not blocked.
  // inputs/text/confidence are persisted so an APPROVE/MODIFY can re-run the
  // identical proposal back through the Aegis gate (no trust-the-verdict path).
  proposedAction: {
    actionType: { type: String, default: '' },
    payload: { type: mongoose.Schema.Types.Mixed, default: {} },
    rationale: { type: String, default: '' },
    inputs: { type: mongoose.Schema.Types.Mixed, default: {} },
    text: { type: String, default: '' },
    confidence: { type: Number, default: null },
  },

  // Non-diagnostic framing shown to the clinician (never "patient has X").
  summary: { type: String, default: '' },
  evidenceRefs: { type: [String], default: [] },   // ledger seqs / record ids
  auditSeq: { type: Number, default: null },         // the action_blocked ledger row

  slaDeadline: { type: Date, default: null },

  // Resolution
  resolvedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },
  resolutionReason: { type: String, default: '' },
  resolvedAt: { type: Date, default: null },

  // Singleton guard: one open RED case per (patient, flagset, day).
  dedupeKey: { type: String, required: true, unique: true },
}, { timestamps: true });

clinicianCaseSchema.index({ doctorId: 1, status: 1, createdAt: -1 });

module.exports = mongoose.model('ClinicianCase', clinicianCaseSchema);
