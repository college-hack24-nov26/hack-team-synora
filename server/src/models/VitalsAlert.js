const mongoose = require('mongoose');

/**
 * VitalsAlert — a durable record of a vitals threshold breach raised during a
 * live monitoring session. Previously these lived only in an in-memory dict in
 * the FastAPI chatbot (vitals_alerts) and were lost on every restart / Render
 * free-tier sleep, so a doctor's alert history vanished. Now persisted here and
 * queried from Mongo.
 */
const vitalsAlertSchema = new mongoose.Schema({
  alertId: { type: String, index: true },        // the uuid the chatbot minted
  doctorId: { type: String, default: '', index: true },
  patientId: { type: String, default: '', index: true },
  patientName: { type: String, default: '' },
  sessionId: { type: String, default: '', index: true },

  type: { type: String, default: '' },           // alert category
  severity: { type: String, default: 'moderate' },
  message: { type: String, default: '' },
  vital: { type: String, default: '' },           // which metric (HR/SpO2/BP...)
  currentValue: { type: mongoose.Schema.Types.Mixed, default: null },
  location: { type: String, default: '' },

  read: { type: Boolean, default: false },
  raisedAt: { type: Date, default: Date.now },
}, { timestamps: true });

vitalsAlertSchema.index({ doctorId: 1, read: 1, raisedAt: -1 });

module.exports = mongoose.model('VitalsAlert', vitalsAlertSchema);
