const express = require('express');
const auth = require('../middleware/auth');
const Appointment = require('../models/Appointment');

const router = express.Router();

// Shape an appointment into the field names the Flutter client expects.
function toClient(a) {
  return {
    id: a._id.toString(),
    doctorId: a.doctorId,
    patientId: a.patientId,
    patientName: a.patientName,
    requestedAt: a.requestedAt ? a.requestedAt.toISOString() : null,
    preferredSlot: a.preferredSlot ? a.preferredSlot.toISOString() : null,
    modality: a.modality,
    reason: a.reason,
    status: a.status,
  };
}

// POST /api/appointments — create an appointment request (patient files own).
router.post('/', auth, async (req, res) => {
  try {
    const b = req.body || {};
    const patientId = b.patientId || (req.user.role === 'patient' ? req.user._id.toString() : null);
    if (!patientId) return res.status(400).json({ message: 'patientId required' });
    if (req.user.role === 'patient' && patientId !== req.user._id.toString()) {
      return res.status(403).json({ message: 'Cannot book for another patient' });
    }
    const appt = await Appointment.create({
      doctorId: b.doctorId || '',
      patientId,
      patientName: b.patientName || req.user.name || '',
      preferredSlot: b.preferredSlot ? new Date(b.preferredSlot) : null,
      modality: b.modality || 'general',
      reason: b.reason || '',
      requestedAt: b.requestedAt ? new Date(b.requestedAt) : new Date(),
    });
    res.status(201).json({ appointment: toClient(appt) });
  } catch (err) {
    console.error('Create appointment error:', err.message);
    res.status(500).json({ message: 'Failed to create appointment' });
  }
});

// GET /api/appointments/mine — appointments scoped to the caller by role.
router.get('/mine', auth, async (req, res) => {
  try {
    let q;
    if (req.user.role === 'patient') q = { patientId: req.user._id.toString() };
    else if (req.user.role === 'doctor') q = { doctorId: req.user._id.toString() };
    else q = {}; // admin
    const appts = await Appointment.find(q).sort({ requestedAt: -1 }).limit(100).lean();
    res.json({ appointments: appts.map(toClient) });
  } catch (err) {
    res.status(500).json({ message: 'Failed to fetch appointments' });
  }
});

// PATCH /api/appointments/:id — confirm / decline / reschedule (doctor-owned).
router.patch('/:id', auth, async (req, res) => {
  try {
    const appt = await Appointment.findById(req.params.id);
    if (!appt) return res.status(404).json({ message: 'Appointment not found' });

    const isDoctorOwner = req.user.role === 'doctor' && appt.doctorId === req.user._id.toString();
    const isPatientOwner = req.user.role === 'patient' && appt.patientId === req.user._id.toString();
    if (!isDoctorOwner && !isPatientOwner && req.user.role !== 'admin') {
      return res.status(403).json({ message: 'Not authorized for this appointment' });
    }

    const { status, preferredSlot } = req.body || {};
    if (status && ['pending', 'confirmed', 'declined', 'rescheduled'].includes(status)) {
      appt.status = status;
      appt.resolvedAt = new Date();
    }
    if (preferredSlot) appt.preferredSlot = new Date(preferredSlot);
    await appt.save();
    res.json({ appointment: toClient(appt) });
  } catch (err) {
    res.status(500).json({ message: 'Failed to update appointment' });
  }
});

module.exports = router;
