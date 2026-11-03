const mongoose = require('mongoose');

/**
 * Per-marker clinical thresholds, ported verbatim from the on-device Dart
 * analyzers (lab_report_analyzer.dart) so the server is the single, versioned
 * source of truth. Every threshold carries the guideline it came from — these
 * are real ADA / WHO / AHA / ICMR cutoffs, not invented numbers.
 *
 * Flag logic (matches the Dart engine, _flagFor):
 *   value >= highCritical  -> 'critical'
 *   value >= highWarn      -> 'high'
 *   value <  lowCritical   -> 'critical'
 *   value <  lowCutoff     -> 'low'
 *   else                   -> 'normal'
 */
const kbDiseaseThresholdSchema = new mongoose.Schema({
  kbVersion: { type: String, required: true, index: true }, // e.g. 'kb-2026-06'
  disease: {
    type: String,
    required: true,
    enum: ['diabetes', 'hypertension', 'anemia'],
  },
  markerKey: { type: String, required: true },   // canonical id e.g. 'hba1c'
  display: { type: String, required: true },      // 'HbA1c'
  unit: { type: String, default: '' },
  referenceRange: { type: String, default: '' },

  lowCritical: { type: Number, default: null },
  lowCutoff: { type: Number, default: null },
  highWarn: { type: Number, default: null },
  highCritical: { type: Number, default: null },

  // Contribution weight when this marker is flagged (mirrors _flagWeight intent).
  weight: { type: Number, default: 0.55 },

  guideline: { type: String, default: '' },       // 'ADA' | 'WHO' | 'AHA/ACC 2017' | 'ICMR' ...
}, { timestamps: true });

// One marker per disease per KB version.
kbDiseaseThresholdSchema.index(
  { kbVersion: 1, disease: 1, markerKey: 1 },
  { unique: true }
);

module.exports = mongoose.model('KbDiseaseThreshold', kbDiseaseThresholdSchema);
