const mongoose = require('mongoose');

/**
 * Episode — the working blackboard for one clinical encounter. Embeds the
 * observations gathered (each a verbatim DiseaseRiskResult), a denormalized
 * currentAssessment snapshot, lifecycle state, and follow-up linkage so the
 * agent can re-open and continue an episode without re-asking everything.
 */
const observationSchema = new mongoose.Schema({
  modality: { type: String, default: '' },          // 'lab' | 'symptom' | 'pallor' | 'heart_mfcc' ...
  disease: { type: String, default: '' },
  fidelity: { type: String, default: 'heuristic' }, // mirrors the tool fidelity tag
  risk: { type: String, enum: ['low', 'moderate', 'high', 'critical'], default: 'low' },
  score: { type: Number, default: 0 },
  confidence: { type: Number, default: 0 },
  headline: { type: String, default: '' },
  raw: { type: mongoose.Schema.Types.Mixed, default: {} }, // full DiseaseRiskResult.toJson()
  recordedAt: { type: Date, default: Date.now },
}, { _id: false });

const episodeSchema = new mongoose.Schema({
  patientId: { type: String, required: true, index: true },
  patientName: { type: String, default: '' },
  doctorId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },
  chiefComplaint: { type: String, default: '' },

  status: {
    type: String,
    enum: ['open', 'awaiting_input', 'escalated', 'closed', 'reopened'],
    default: 'open',
    index: true,
  },

  observations: { type: [observationSchema], default: [] },

  currentAssessment: {
    overallRisk: { type: String, enum: ['low', 'moderate', 'high', 'critical'], default: 'low' },
    primaryDisease: { type: String, default: '' },
    redFlagsHit: { type: [String], default: [] },
    recommendedSpecialties: { type: [String], default: [] },
    summary: { type: String, default: '' },
    plan: { type: [String], default: [] },
  },

  // Follow-up loop
  parentEpisodeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Episode', default: null },
  followUpDueAt: { type: Date, default: null, index: true },
  followUpDone: { type: Boolean, default: false },
  reopenCount: { type: Number, default: 0 },

  kbVersionRef: { type: String, default: '' },
}, { timestamps: true });

episodeSchema.index({ patientId: 1, status: 1, updatedAt: -1 });
// text index for free-text recall (Tier-2 retrieval, no vector DB)
episodeSchema.index({ 'currentAssessment.summary': 'text', chiefComplaint: 'text' });

module.exports = mongoose.model('Episode', episodeSchema);
