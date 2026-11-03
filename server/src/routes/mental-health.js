const express = require('express');
const auth = require('../middleware/auth');
const MentalHealthNotification = require('../models/MentalHealthNotification');
const aegisService = require('../../aegis/service');

const router = express.Router();

// Map a mental-health urgency to a risk level the Aegis gate understands.
const URGENCY_TO_RISK = { low: 'low', moderate: 'moderate', high: 'critical' };

// POST /api/mental-health/notifications — save notification.
// Auth REQUIRED: the chatbot forwards the signed-in user's bearer token (see
// chatbot/main.py). Without this, any unauthenticated caller could drive the
// Aegis gate and open RED suicidal-ideation cases for arbitrary patient/doctor
// pairs. Identity is bound below so a patient can only file for themselves.
router.post('/notifications', auth, async (req, res) => {
  try {
    const { doctorId, patientId, patientName, clinicalReport, urgency, transcript, source } = req.body;

    if (!doctorId || !patientId || !patientName || !clinicalReport) {
      return res.status(400).json({ message: 'Missing required fields' });
    }

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

// GET /api/mental-health/notifications/:doctorId — get notifications for doctor (auth required)
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
      read: n.read,
      created_at: n.createdAt.toISOString(),
    }));

    res.json({ notifications: mapped });
  } catch (error) {
    console.error('Get mental health notifications error:', error);
    res.status(500).json({ message: 'Failed to fetch notifications' });
  }
});

// PUT /api/mental-health/notifications/:id/read — mark notification as read.
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

// PUT /api/mental-health/notifications/:id/ack — patient acknowledges a
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

// GET /api/mental-health/notifications/unread-count/:doctorId — get unread count
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

// DELETE /api/mental-health/notifications/:id — delete a notification (doctor only)
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
