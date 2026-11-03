const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const registry = require('../../aegis/registry');
const tools = require('../../aegis/tools');
const kbLoader = require('../../aegis/kb');

let _booted = false;
async function ensureBooted() {
  if (_booted) return;
  const kb = await kbLoader.load();
  tools.registerAll(kb);
  _booted = true;
}

// The modality surface the agent (and judges) can see — incl. honest roadmap slots.
router.get('/', auth, async (req, res) => {
  await ensureBooted();
  res.json({ tools: registry.list() });
});

// Invoke a tool by id (output is fidelity-gated).
router.post('/:id/invoke', auth, async (req, res) => {
  try {
    await ensureBooted();
    if (!registry.has(req.params.id)) return res.status(404).json({ message: 'unknown tool' });
    const out = await registry.invoke(req.params.id, req.body || {});
    res.json(out);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

module.exports = router;
