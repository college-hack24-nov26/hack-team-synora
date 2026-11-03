const mongoose = require('mongoose');

/**
 * Red-flag rules — the deterministic triggers that force the Aegis gate to
 * RED (hard block + synchronous clinician review). These are NEVER arbitrated
 * by the LLM; the rule table decides. Sourced from the spec §4.2 and the live
 * threshold engine (chatbot/main.py _check_alerts + vitals_analyzer.dart).
 *
 * A flag fires when the named `field` from a structured input crosses
 * `op`/`threshold`, OR (for composite/text flags) when `matchAll` keyword
 * groups are all present. `op` is one of: 'gte','gt','lte','lt','keywords'.
 */
const kbRedFlagSchema = new mongoose.Schema({
  kbVersion: { type: String, required: true, index: true },
  flagKey: { type: String, required: true },      // 'critical_hypoxemia'
  label: { type: String, required: true },        // 'Critical hypoxemia'

  // Single-threshold flags
  field: { type: String, default: null },         // 'spo2','systolic','diastolic','heart_rate','hb_estimate'
  op: {
    type: String,
    enum: ['gte', 'gt', 'lte', 'lt', 'keywords', 'composite'],
    default: 'gte',
  },
  threshold: { type: Number, default: null },

  // Composite / text flags: every inner array must have >=1 keyword present.
  // e.g. [['chest pain','chest tightness'], ['breathless','dyspnea','can\'t breathe']]
  keywordGroups: { type: [[String]], default: undefined },
  source: { type: String, default: '' },          // where the input comes from
  guideline: { type: String, default: '' },       // 'WHO' | 'AHA/ACC 2017' ...
}, { timestamps: true });

kbRedFlagSchema.index({ kbVersion: 1, flagKey: 1 }, { unique: true });

module.exports = mongoose.model('KbRedFlag', kbRedFlagSchema);
