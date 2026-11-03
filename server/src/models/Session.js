const mongoose = require('mongoose');

/**
 * Session — server-side record of an issued auth token, enabling logout/
 * revocation and device recovery (the JWT alone is stateless and can't be
 * revoked before expiry). Stores only a HASH of the token, never the token.
 *
 * Enforcement is OPT-IN and non-breaking: the auth middleware only rejects a
 * token when SESSION_ENFORCEMENT=true AND a matching session row exists-and-is-
 * revoked. With enforcement off (default), behaviour is unchanged — so adding
 * this model doesn't lock out existing tokens that predate session tracking.
 */
const sessionSchema = new mongoose.Schema({
  userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  tokenHash: { type: String, required: true, index: true }, // sha256 of the JWT
  deviceId: { type: String, default: '' },
  createdAt: { type: Date, default: Date.now },
  lastUsedAt: { type: Date, default: Date.now },
  revoked: { type: Boolean, default: false },
}, { timestamps: true });

module.exports = mongoose.model('Session', sessionSchema);
