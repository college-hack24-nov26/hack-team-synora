const express = require('express');
const auth = require('../middleware/auth');
const VitalsAlert = require('../models/VitalsAlert');
const VitalsSession = require('../models/VitalsSession');

const router = express.Router();

/**
 * Service-to-service guard. The FastAPI chatbot (not a logged-in user) writes
 * vitals sessions/alerts during the simulator tick loop, so it authenticates
 * with a shared secret instead of a user JWT. Set SERVICE_KEY in BOTH the Node
 * server and the chatbot env. If SERVICE_KEY is unset we allow the call but
 * warn — so existing deploys keep working until the secret is configured.
 */
function serviceAuth(req, res, next) {
  const expected = process.env.SERVICE_KEY;
  if (!expected) {
    console.warn('WARNING: SERVICE_KEY not set — vitals ingest endpoints are unauthenticated. Set it in production.');
    return next();
  }
  if (req.header('X-Service-Key') === expected) return next();
  return res.status(401).json({ message: 'Invalid service key' });
}

// ── Ingest (chatbot → Node, service-authenticated) ───────────────────────────

// POST /api/vitals/sessions — record that a monitoring session started
router.post('/sessions', serviceAuth, async (req, res) => {
  try {
    const { sessionId, doctorId, patientId, patientName, location } = req.body || {};
    if (!sessionId) return res.status(400).json({ message: 'sessionId required' });
    const session = await VitalsSession.findOneAndUpdate(
      { sessionId },
      { $set: { doctorId: doctorId || '', patientId: patientId || '', patientName: patientName || '', location: location || '', status: 'active', startedAt: new Date() } },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );
    res.status(201).json({ session });
  } catch (err) {
    console.error('Vitals session create error:', err.message);
    res.status(500).json({ message: 'Failed to record session' });
  }
});

// PATCH /api/vitals/sessions/:sessionId — tick / stop a session
router.patch('/sessions/:sessionId', serviceAuth, async (req, res) => {
  try {
    const { status } = req.body || {};
    const update = { lastTickAt: new Date() };
    if (status === 'stopped') { update.status = 'stopped'; update.stoppedAt = new Date(); }
    const session = await VitalsSession.findOneAndUpdate(
      { sessionId: req.params.sessionId }, { $set: update }, { new: true }
    );
    if (!session) return res.status(404).json({ message: 'Session not found' });
    res.json({ session });
  } catch (err) {
    res.status(500).json({ message: 'Failed to update session' });
  }
});

// POST /api/vitals/alerts — persist one or more vitals alerts
router.post('/alerts', serviceAuth, async (req, res) => {
  try {
    const { doctorId, patientId, patientName, sessionId, location, alerts } = req.body || {};
    const list = Array.isArray(alerts) ? alerts : [];
    if (list.length === 0) return res.status(400).json({ message: 'alerts array required' });
    const docs = list.map((a) => ({
      alertId: a.id || a.alertId,
      doctorId: doctorId || '',
      patientId: patientId || '',
      patientName: patientName || '',
      sessionId: sessionId || '',
      location: location || '',
      type: a.type || '',
      severity: a.severity || 'moderate',
      message: a.message || '',
      vital: a.vital || '',
      currentValue: a.current_value ?? a.currentValue ?? null,
      raisedAt: a.timestamp ? new Date(a.timestamp) : new Date(),
      read: false,
    }));
    const created = await VitalsAlert.insertMany(docs);
    if (sessionId) {
      await VitalsSession.updateOne({ sessionId }, { $inc: { alertCount: docs.length } });
    }
    res.status(201).json({ count: created.length });
  } catch (err) {
    console.error('Vitals alert ingest error:', err.message);
    res.status(500).json({ message: 'Failed to persist alerts' });
  }
});

// ── Read (doctor/patient → Node, user-authenticated) ─────────────────────────

// Shape a stored alert into the field names the Flutter UI already expects
// (matching the chatbot's original alert JSON), so no client UI change is
// needed beyond pointing at this endpoint.
function toClientShape(a) {
  return {
    id: a.alertId || a._id.toString(),
    type: a.type,
    severity: a.severity,
    message: a.message,
    vital: a.vital,
    current_value: a.currentValue,
    patient_id: a.patientId,
    patient_name: a.patientName,
    doctor_id: a.doctorId,
    read: a.read,
    timestamp: a.raisedAt ? a.raisedAt.toISOString() : null,
  };
}

// GET /api/vitals/alerts/doctor/:doctorId — a doctor's own alert feed
router.get('/alerts/doctor/:doctorId', auth, async (req, res) => {
  try {
    if (req.user.role !== 'admin' && req.params.doctorId !== req.user._id.toString()) {
      return res.status(403).json({ message: 'Not authorized' });
    }
    const alerts = await VitalsAlert.find({ doctorId: req.params.doctorId })
      .sort({ raisedAt: -1 }).limit(100).lean();
    res.json({ alerts: alerts.map(toClientShape) });
  } catch (err) {
    res.status(500).json({ message: 'Failed to fetch alerts' });
  }
});

// GET /api/vitals/alerts/patient/:patientId — a patient's own alert feed
router.get('/alerts/patient/:patientId', auth, async (req, res) => {
  try {
    if (req.user.role === 'patient' && req.params.patientId !== req.user._id.toString()) {
      return res.status(403).json({ message: 'Not authorized' });
    }
    const alerts = await VitalsAlert.find({ patientId: req.params.patientId })
      .sort({ raisedAt: -1 }).limit(100).lean();
    res.json({ alerts: alerts.map(toClientShape) });
  } catch (err) {
    res.status(500).json({ message: 'Failed to fetch alerts' });
  }
});

// PUT /api/vitals/alerts/:alertId/read — mark an alert read (owner only)
router.put('/alerts/:alertId/read', auth, async (req, res) => {
  try {
    const filter = { alertId: req.params.alertId };
    if (req.user.role === 'doctor') filter.doctorId = req.user._id.toString();
    else if (req.user.role === 'patient') filter.patientId = req.user._id.toString();
    const updated = await VitalsAlert.findOneAndUpdate(filter, { read: true });
    if (!updated) return res.status(404).json({ message: 'Alert not found or not authorized' });
    res.json({ status: 'ok' });
  } catch (err) {
    res.status(500).json({ message: 'Failed to mark read' });
  }
});

module.exports = router;
