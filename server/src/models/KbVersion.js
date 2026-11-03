const mongoose = require('mongoose');

/**
 * KB version registry. Exactly one version is `active` at a time; the Aegis
 * gate and reasoner stamp every decision with the active kbVersion so past
 * audits remain reproducible even after the KB is updated. Updating the KB
 * means seeding a new version and flipping `active` — never mutating rows in
 * place.
 */
const kbVersionSchema = new mongoose.Schema({
  version: { type: String, required: true, unique: true }, // 'kb-2026-06'
  active: { type: Boolean, default: false, index: true },
  description: { type: String, default: '' },
  sources: { type: [String], default: [] },                // guideline citations
  seededAt: { type: Date, default: Date.now },
}, { timestamps: true });

module.exports = mongoose.model('KbVersion', kbVersionSchema);
