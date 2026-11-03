const mongoose = require('mongoose');

/**
 * Appointment — canonical record of a patient's appointment request. Previously
 * appointments existed only in on-device SharedPreferences plus a fire-and-
 * forget notification, so a request was lost if the notify POST failed or the
 * device changed, and the doctor had no structured record. Now durable in Mongo.
 */
const appointmentSchema = new mongoose.Schema({
  doctorId: { type: String, default: '', index: true },
  patientId: { type: String, required: true, index: true },
  patientName: { type: String, default: '' },
  preferredSlot: { type: Date, default: null },
  modality: { type: String, default: 'general' },     // diabetes|hypertension|anemia|general
  reason: { type: String, default: '' },
  status: { type: String, enum: ['pending', 'confirmed', 'declined', 'rescheduled'], default: 'pending', index: true },
  requestedAt: { type: Date, default: Date.now },
  resolvedAt: { type: Date, default: null },
}, { timestamps: true });

appointmentSchema.index({ doctorId: 1, status: 1, requestedAt: -1 });
appointmentSchema.index({ patientId: 1, requestedAt: -1 });

module.exports = mongoose.model('Appointment', appointmentSchema);
