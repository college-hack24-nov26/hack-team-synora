const mongoose = require('mongoose');

/**
 * LedgerCounter — authoritative monotonic sequence allocator for the
 * decision_audit hash chain. One document per chain:
 *   _id = `ep:<episodeId>`        for an episode-scoped chain
 *   _id = `pt:<patientId>`        for a patient-wide chain (episodeId: null)
 *
 * Seq allocation MUST be atomic: `findOneAndUpdate({_id}, {$inc:{maxSeq:1}})`
 * hands every concurrent append a distinct seq, eliminating the read-then-write
 * race in the old ledger that could fork the chain and break tamper-evidence.
 */
const ledgerCounterSchema = new mongoose.Schema({
  _id: { type: String },                 // chain key (ep:<id> | pt:<id>)
  maxSeq: { type: Number, default: -1 }, // last allocated seq; first append => 0
}, { _id: false, versionKey: false });

module.exports = mongoose.model('LedgerCounter', ledgerCounterSchema);
