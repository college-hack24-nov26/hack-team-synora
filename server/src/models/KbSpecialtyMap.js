const mongoose = require('mongoose');

/**
 * Disease -> ranked specialty mapping, ported from specialty_recommender.dart.
 * Recommendations are only produced for moderate+ risk (enforced in logic,
 * not here). `onlyIfFemale` reproduces the Gynecologist-for-anemia rule.
 */
const kbSpecialtyMapSchema = new mongoose.Schema({
  kbVersion: { type: String, required: true, index: true },
  disease: {
    type: String,
    required: true,
    enum: ['diabetes', 'hypertension', 'anemia'],
  },
  // Ordered primary -> supporting. Each entry: { name, rank, onlyIfFemale }
  specialties: [{
    name: { type: String, required: true },
    rank: { type: Number, required: true },       // lower = higher priority
    onlyIfFemale: { type: Boolean, default: false },
    note: { type: String, default: '' },
  }],
}, { timestamps: true });

kbSpecialtyMapSchema.index({ kbVersion: 1, disease: 1 }, { unique: true });

module.exports = mongoose.model('KbSpecialtyMap', kbSpecialtyMapSchema);
