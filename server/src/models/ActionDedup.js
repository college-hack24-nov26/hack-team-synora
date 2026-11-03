const mongoose = require('mongoose');

/**
 * Idempotency store for side-effecting actions. Prevents double-booking /
 * duplicate alerts when the agent self-corrects or a request is replayed.
 *
 * idempotencyKey = sha256(patientId + actionType + inputDigest + rulesVersion + dayBucket)
 * On replay, the stored result is returned instead of re-executing.
 */
const actionDedupSchema = new mongoose.Schema({
  idempotencyKey: { type: String, required: true, unique: true },
  status: { type: String, enum: ['PENDING', 'DONE', 'FAILED'], default: 'PENDING' },
  actionType: { type: String, default: '' },
  patientId: { type: String, default: '' },
  result: { type: mongoose.Schema.Types.Mixed, default: null },
}, { timestamps: true });

module.exports = mongoose.model('ActionDedup', actionDedupSchema);
