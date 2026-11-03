const mongoose = require('mongoose');

/**
 * PatientMemory — long-term, one doc per patient. Distilled facts the agent
 * should carry across episodes + a bounded risk timeline + a cached summary
 * (the server analog of disease_risk_store.chatbotSummary()).
 */
const factSchema = new mongoose.Schema({
  category: { type: String, default: '' },   // 'condition' | 'medication' | 'allergy' | 'lifestyle' | 'demographic'
  key: { type: String, default: '' },
  value: { type: String, default: '' },
  confidence: { type: Number, default: 0.7 },
  active: { type: Boolean, default: true },
  sourceEpisodeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Episode', default: null },
  updatedAt: { type: Date, default: Date.now },
}, { _id: false });

const timelinePointSchema = new mongoose.Schema({
  disease: { type: String, default: '' },
  risk: { type: String, default: '' },
  score: { type: Number, default: 0 },
  at: { type: Date, default: Date.now },
}, { _id: false });

const patientMemorySchema = new mongoose.Schema({
  patientId: { type: String, required: true, unique: true },
  facts: { type: [factSchema], default: [] },
  riskTimeline: { type: [timelinePointSchema], default: [] }, // capped ~40 in logic
  cachedSummary: { type: String, default: '' },
}, { timestamps: true });

module.exports = mongoose.model('PatientMemory', patientMemorySchema);
