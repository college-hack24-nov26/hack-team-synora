const express = require('express');
const auth = require('../middleware/auth');
const MentalHealthNotification = require('../models/MentalHealthNotification');
const aegisService = require('../../aegis/service');

const router = express.Router();

// Map a mental-health urgency to a risk level the Aegis gate understands.
const URGENCY_TO_RISK = { low: 'low', moderate: 'moderate', high: 'critical' };

function deriveModality(source = '', report = '', transcript = '') {
  const combined = `${source} ${report} ${transcript}`.toLowerCase();
  if (source === 'appointment_request' || combined.includes('appointment request')) return 'appointment';
  if (combined.includes('skin') || combined.includes('melanoma') || combined.includes('carcinoma')) return 'skin_cancer';
  if (combined.includes('heart') || combined.includes('cardio') || combined.includes('auscultation') || combined.includes('murmur') || combined.includes('arrhythmia')) return 'cardiac';
  if (combined.includes('anemia') || combined.includes('pallor') || combined.includes('hemoglobin') || combined.includes('conjunctival')) return 'anemia';
  if (combined.includes('respiratory') || combined.includes('lung') || combined.includes('wheez') || combined.includes('crackles')) return 'respiratory';
  if (combined.includes('retin') || combined.includes('fundus') || combined.includes('macular')) return 'retinopathy';
  if (combined.includes('vital') || combined.includes('blood pressure') || combined.includes('spo2') || combined.includes('heart rate')) return 'vitals';
  if (combined.includes('mindspace') || combined.includes('phq') || combined.includes('voice biomarker')) return 'mindspace';
  return 'general';
}

function formatReadableDate(d) {
  if (!d) return '';
  const dt = new Date(d);
  if (isNaN(dt.getTime())) return String(d);
  return dt.toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    second: '2-digit',
    hour12: true
  });
}

// POST /api/mental-health/notifications - save notification.
// Auth REQUIRED: the chatbot forwards the signed-in user's bearer token (see
// chatbot/main.py). Without this, any unauthenticated caller could drive the
// Aegis gate and open RED suicidal-ideation cases for arbitrary patient/doctor
// pairs. Identity is bound below so a patient can only file for themselves.
router.post('/notifications', auth, async (req, res) => {
  try {
    const { doctorId, patientId, patientName, clinicalReport, urgency, transcript, source, modality,
            latitude, longitude, locationLabel, mapsUrl,
            voiceMarkerScore, voiceMarkerHeadline } = req.body;

    if (!doctorId || !patientId || !patientName || !clinicalReport) {
      return res.status(400).json({ message: 'Missing required fields' });
    }

    const lat = typeof latitude === 'number' ? latitude : null;
    const lng = typeof longitude === 'number' ? longitude : null;
    const resolvedMapsUrl = mapsUrl || (lat != null && lng != null ? `https://www.google.com/maps?q=${lat},${lng}` : '');

    // A patient may only file a check-in for themselves. Doctors/admins (e.g.
    // filing on a patient's behalf) are allowed through.
    if (req.user.role === 'patient' && patientId !== req.user._id.toString()) {
      return res.status(403).json({ message: 'Cannot file a notification for another patient' });
    }

    const notification = await MentalHealthNotification.create({
      doctorId,
      patientId,
      patientName,
      clinicalReport,
      urgency: urgency || 'low',
      transcript: transcript || '',
      source: source || 'mindspace',
      modality: modality || deriveModality(source, clinicalReport, transcript),
      latitude: lat,
      longitude: lng,
      locationLabel: locationLabel || '',
      mapsUrl: resolvedMapsUrl,
      voiceMarkerScore: typeof voiceMarkerScore === 'number' ? voiceMarkerScore : null,
      voiceMarkerHeadline: voiceMarkerHeadline || '',
    });

    // Route the check-in through the Aegis safety gate. The deterministic
    // red-flag set (incl. suicidal ideation) decides GREEN/AMBER/RED; a RED
    // verdict opens a human-gated ClinicianCase and writes the audit ledger.
    // Best-effort: never let a gate failure drop the notification.
    let aegis = null;
    try {
      aegis = await aegisService.submit({
        patientId,
        patientName,
        doctorId,
        riskLevel: URGENCY_TO_RISK[urgency] || 'low',
        actionType: 'mental_health_review',
        text: `${clinicalReport}\n${transcript || ''}`,
        summary: `MindSpace check-in (urgency: ${urgency || 'low'})`,
        latitude: lat,
        longitude: lng,
        locationLabel: locationLabel || '',
        mapsUrl: resolvedMapsUrl,
      });
    } catch (gateErr) {
      console.error('Aegis gate (mental-health) error:', gateErr.message);
    }

    res.status(201).json({ notification, aegis });
  } catch (error) {
    console.error('Save mental health notification error:', error);
    res.status(500).json({ message: 'Failed to save notification' });
  }
});

// GET /api/mental-health/notifications/:doctorId - get notifications for doctor (auth required)
router.get('/notifications/:doctorId', auth, async (req, res) => {
  try {
    // A doctor may only read their OWN notifications (admins may read any).
    if (req.user.role !== 'admin' && req.params.doctorId !== req.user._id.toString()) {
      return res.status(403).json({ message: 'Not authorized for these notifications' });
    }
    const notifications = await MentalHealthNotification.find({
      doctorId: req.params.doctorId,
    })
      .sort({ createdAt: -1 })
      .limit(50)
      .lean();

    // Map _id to id for Flutter compatibility
    const mapped = notifications.map(n => ({
      id: n._id.toString(),
      doctor_id: n.doctorId.toString(),
      patient_id: n.patientId,
      patient_name: n.patientName,
      report: n.clinicalReport,
      urgency: n.urgency,
      transcript: n.transcript,
      source: n.source,
      modality: n.modality || deriveModality(n.source, n.clinicalReport, n.transcript),
      latitude: n.latitude ?? null,
      longitude: n.longitude ?? null,
      location: n.locationLabel || '',
      maps_url: n.mapsUrl || '',
      voice_marker_score: n.voiceMarkerScore ?? null,
      voice_marker_headline: n.voiceMarkerHeadline || '',
      read: n.read,
      created_at: n.createdAt.toISOString(),
      timestamp: n.createdAt.toISOString(),
      raw_timestamp: n.createdAt.getTime(),
      formatted_timestamp: formatReadableDate(n.createdAt),
    }));

    res.json({ notifications: mapped });
  } catch (error) {
    console.error('Get mental health notifications error:', error);
    res.status(500).json({ message: 'Failed to fetch notifications' });
  }
});

// PUT /api/mental-health/notifications/:id/read - mark notification as read.
// Ownership enforced in the query filter so a doctor can only mark their OWN
// notification read (admins may mark any).
router.put('/notifications/:id/read', auth, async (req, res) => {
  try {
    const filter = { _id: req.params.id };
    if (req.user.role !== 'admin') filter.doctorId = req.user._id;
    const updated = await MentalHealthNotification.findOneAndUpdate(filter, { read: true });
    if (!updated) {
      return res.status(404).json({ message: 'Notification not found or not authorized' });
    }
    res.json({ status: 'ok' });
  } catch (error) {
    console.error('Mark notification read error:', error);
    res.status(500).json({ message: 'Failed to mark as read' });
  }
});

// PUT /api/mental-health/notifications/:id/ack - patient acknowledges a
// notification (e.g. saw the doctor's appointment response). Owner-scoped so a
// patient can only ack their own; keeps read/ack state in Mongo, not local-only.
router.put('/notifications/:id/ack', auth, async (req, res) => {
  try {
    const filter = { _id: req.params.id };
    if (req.user.role === 'patient') filter.patientId = req.user._id.toString();
    const updated = await MentalHealthNotification.findOneAndUpdate(
      filter, { patientAcknowledged: true }
    );
    if (!updated) {
      return res.status(404).json({ message: 'Notification not found or not authorized' });
    }
    res.json({ status: 'ok' });
  } catch (error) {
    console.error('Ack notification error:', error);
    res.status(500).json({ message: 'Failed to acknowledge' });
  }
});

// GET /api/mental-health/notifications/unread-count/:doctorId - get unread count
router.get('/notifications/unread-count/:doctorId', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin' && req.params.doctorId !== req.user._id.toString()) {
      return res.status(403).json({ message: 'Not authorized' });
    }
    const count = await MentalHealthNotification.countDocuments({
      doctorId: req.params.doctorId,
      read: false,
    });
    res.json({ count });
  } catch (error) {
    res.status(500).json({ message: 'Failed to get count' });
  }
});

// DELETE /api/mental-health/notifications/:id - delete a notification (doctor only)
router.delete('/notifications/:id', auth, async (req, res) => {
  try {
    const notification = await MentalHealthNotification.findById(req.params.id);
    if (!notification) {
      return res.status(404).json({ message: 'Notification not found' });
    }
    if (notification.doctorId.toString() !== req.user._id.toString()) {
      return res.status(403).json({ message: 'Not authorized to delete this notification' });
    }
    await MentalHealthNotification.findByIdAndDelete(req.params.id);
    res.json({ status: 'deleted' });
  } catch (error) {
    console.error('Delete notification error:', error);
    res.status(500).json({ message: 'Failed to delete notification' });
  }
});

module.exports = router;
