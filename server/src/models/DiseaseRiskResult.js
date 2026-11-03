const mongoose = require('mongoose');

/**
 * DiseaseRiskResult — durable record of a chronic-disease screening outcome
 * (diabetes / hypertension / anemia via lab / questionnaire / vitals / retina /
 * pallor / ppg). Previously these lived ONLY in on-device SharedPreferences
 * (lib/services/disease_risk_store.dart), so a patient's entire screening
 * history was lost on uninstall/device-switch and invisible to their doctor.
 * Mirrors the Dart DiseaseRiskResult model field-for-field.
 */
const markerFindingSchema = new mongoose.Schema({
  name: String,
  value: String,
  unit: String,
  referenceRange: String,
  flag: { type: String, default: 'normal' },
  interpretation: String,
}, { _id: false });

const diseaseRiskResultSchema = new mongoose.Schema({
  patientId: { type: String, required: true, index: true },
  disease: { type: String, required: true, index: true }, // diabetes|hypertension|anemia
  method: { type: String, default: '' },                  // detection method name
  risk: { type: String, default: 'LOW' },                 // LOW|MODERATE|HIGH|CRITICAL
  score: { type: Number, default: 0 },                    // 0..1
  headline: { type: String, default: '' },
  findings: { type: [markerFindingSchema], default: [] },
  topContributors: { type: [String], default: [] },
  recommendations: { type: [String], default: [] },
  dataSource: { type: String, default: '' },
  llmExplanation: { type: String, default: null },
  measuredAt: { type: Date, default: Date.now },          // client 'timestamp'
}, { timestamps: true });

diseaseRiskResultSchema.index({ patientId: 1, disease: 1, measuredAt: -1 });

module.exports = mongoose.model('DiseaseRiskResult', diseaseRiskResultSchema);
