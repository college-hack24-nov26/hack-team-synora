const mongoose = require('mongoose');

const mindSpaceSessionSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
  },
  transcript: {
    type: String,
    default: '',
  },
  userMessage: {
    type: String,
    default: '',
  },
  doctorReport: {
    type: String,
    default: null,
  },
  urgency: {
    type: String,
    enum: ['low', 'moderate', 'high'],
    default: 'low',
  },
  coinsEarned: {
    type: Number,
    default: 0,
  },
  doctorId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    default: null,
  },
  // On-device voice acoustic-biomarker score (0..1), screening-only.
  voiceMarkerScore: {
    type: Number,
    default: null,
  },
}, {
  timestamps: true,
});

mindSpaceSessionSchema.index({ userId: 1, createdAt: -1 });

module.exports = mongoose.model('MindSpaceSession', mindSpaceSessionSchema);
