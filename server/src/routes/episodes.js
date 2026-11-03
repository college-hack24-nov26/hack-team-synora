const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const patientAccess = require('../middleware/patientAccess');
const memory = require('../../aegis/memory');
const kbLoader = require('../../aegis/kb');

// Start or reopen an episode
router.post('/start', auth, async (req, res) => {
  try {
    const { patientId, patientName, doctorId, chiefComplaint, primaryDisease } = req.body || {};
    if (!patientId) return res.status(400).json({ message: 'patientId required' });
    const kb = await kbLoader.load();
    const ep = await memory.startOrReopen({ patientId, patientName, doctorId, chiefComplaint, primaryDisease, kbVersion: kb.kbVersion });
    res.json({ episode: ep });
  } catch (err) { res.status(500).json({ message: err.message }); }
});

// Add an observation (a screening result) to an episode
router.post('/:id/observation', auth, async (req, res) => {
  try {
    const ep = await memory.addObservation(req.params.id, req.body || {});
    res.json({ episode: ep });
  } catch (err) { res.status(500).json({ message: err.message }); }
});

// Set the current assessment snapshot
router.put('/:id/assessment', auth, async (req, res) => {
  try {
    const ep = await memory.setAssessment(req.params.id, req.body || {});
    res.json({ episode: ep });
  } catch (err) { res.status(500).json({ message: err.message }); }
});

// Schedule a follow-up
router.post('/:id/followup', auth, async (req, res) => {
  try {
    const { dueAt } = req.body || {};
    const ep = await memory.scheduleFollowUp(req.params.id, dueAt ? new Date(dueAt) : null);
    res.json({ episode: ep });
  } catch (err) { res.status(500).json({ message: err.message }); }
});

// Assemble the agent/chatbot context for a patient
router.get('/:patientId/context', auth, patientAccess(), async (req, res) => {
  try {
    const ctx = await memory.getContext(req.params.patientId, { episodeId: req.query.episodeId, query: req.query.q });
    res.json(ctx);
  } catch (err) { res.status(500).json({ message: err.message }); }
});

// Long-term memory fact upsert
router.post('/:patientId/fact', auth, patientAccess(), async (req, res) => {
  try {
    const mem = await memory.upsertFact(req.params.patientId, req.body || {});
    res.json({ memory: mem });
  } catch (err) { res.status(500).json({ message: err.message }); }
});

// Due follow-ups (the sweeper / cron target)
router.get('/followups/due', auth, async (req, res) => {
  try {
    res.json({ due: await memory.dueFollowUps() });
  } catch (err) { res.status(500).json({ message: err.message }); }
});

module.exports = router;
