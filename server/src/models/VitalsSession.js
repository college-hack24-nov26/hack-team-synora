const mongoose = require('mongoose');

/**
 * VitalsSession — durable record that a live vitals-monitoring session ran.
 * The transient simulator state (scenario/drift/tick counter) stays in the
 * chatbot process by design; this is the audit-able session envelope so a
 * doctor can see that monitoring happened and when, surviving restarts.
 */
const vitalsSessionSchema = new mongoose.Schema({
  sessionId: { type: String, required: true, unique: true },
  doctorId: { type: String, default: '', index: true },
  patientId: { type: String, default: '', index: true },
  patientName: { type: String, default: '' },
  location: { type: String, default: '' },

  status: { type: String, enum: ['active', 'stopped'], default: 'active', index: true },
  startedAt: { type: Date, default: Date.now },
  lastTickAt: { type: Date, default: null },
  stoppedAt: { type: Date, default: null },
  alertCount: { type: Number, default: 0 },
}, { timestamps: true });

module.exports = mongoose.model('VitalsSession', vitalsSessionSchema);
