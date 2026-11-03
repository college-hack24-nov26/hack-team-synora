const mongoose = require('mongoose');

const mentalHealthNotificationSchema = new mongoose.Schema({
  doctorId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  patientId: { type: String, required: true },
  patientName: { type: String, required: true },
  clinicalReport: { type: String, required: true },
  urgency: { type: String, enum: ['low', 'moderate', 'high'], default: 'low' },
  transcript: { type: String },
  read: { type: Boolean, default: false },
  // What raised this notification: 'mindspace' | 'disease_alert' | 'appointment_request'.
  // Lets the doctor UI categorise and the disease-alert client de-dupe by source.
  source: { type: String, default: 'mindspace' },
  // Patient-side acknowledgement (e.g. saw the doctor's appointment response).
  // Distinct from `read`, which is the doctor's read-state.
  patientAcknowledged: { type: Boolean, default: false },
}, { timestamps: true });

mentalHealthNotificationSchema.index({ doctorId: 1, createdAt: -1 });

module.exports = mongoose.model('MentalHealthNotification', mentalHealthNotificationSchema);
