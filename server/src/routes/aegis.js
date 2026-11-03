const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const roleCheck = require('../middleware/roleCheck');
const patientAccess = require('../middleware/patientAccess');

const aegisService = require('../../aegis/service');
const ledger = require('../../aegis/ledger');
const kbLoader = require('../../aegis/kb');
const { lint, ensureDisclaimer } = require('../../aegis/guardrail');

const ClinicianCase = require('../models/ClinicianCase');
const DecisionAudit = require('../models/DecisionAudit');

// ── Submit an action proposal through the Aegis gate ─────────────────────────
// Body: { patientId, patientName?, doctorId?, episodeId?, riskLevel,
//         actionType, inputs?, text?, confidence?, payload?, summary? }
router.post('/submit', auth, async (req, res) => {
  try {
    const p = req.body || {};
    if (!p.patientId || !p.riskLevel || !p.actionType) {
      return res.status(400).json({ message: 'patientId, riskLevel and actionType are required' });
    }
    const result = await aegisService.submit(p);
    res.json(result);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// ── Guardrail lint check (used before showing any generated text) ────────────
router.post('/guardrail/check', auth, (req, res) => {
  const { text } = req.body || {};
  const result = lint(text || '');
  res.json({ ...result, withDisclaimer: ensureDisclaimer(text || '') });
});

// ── Clinician console: list open cases for the logged-in doctor ──────────────
router.get('/cases', auth, async (req, res) => {
  try {
    // The clinician console is doctor/admin only. A patient (or any other
    // role) must never list RED cases — that would leak other patients' data.
    if (req.user.role !== 'doctor' && req.user.role !== 'admin') {
      return res.status(403).json({ message: 'Clinician role required' });
    }
    const status = req.query.status || 'AWAITING_REVIEW';
    const q = { status };
    if (req.user.role === 'doctor') q.doctorId = req.user._id;
    const cases = await ClinicianCase.find(q).sort({ createdAt: -1 }).limit(100).lean();
    res.json({ cases });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

router.get('/cases/:id', auth, async (req, res) => {
  try {
    if (req.user.role !== 'doctor' && req.user.role !== 'admin') {
      return res.status(403).json({ message: 'Clinician role required' });
    }
    const kase = await ClinicianCase.findById(req.params.id).lean();
    if (!kase) return res.status(404).json({ message: 'Case not found' });
    // A doctor may only open their own patients' cases (admins see all).
    if (req.user.role === 'doctor' && kase.doctorId?.toString() !== req.user._id.toString()) {
      return res.status(403).json({ message: 'Not authorized for this case' });
    }
    const chain = await ledger.chainFor(kase.episodeId || null, kase.patientId);
    const verify = ledger.verifyChain(chain);
    res.json({ case: kase, ledger: chain, ledgerIntegrity: verify });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// ── Clinician verbs: APPROVE / MODIFY / OVERRIDE / ESCALATE ──────────────────
const VERB_STATUS = { approve: 'APPROVED', modify: 'MODIFIED', override: 'OVERRIDDEN', escalate: 'ESCALATED' };

router.post('/cases/:id/:verb', auth, async (req, res) => {
  try {
    const verb = req.params.verb;
    const status = VERB_STATUS[verb];
    if (!status) return res.status(400).json({ message: 'Unknown verb' });
    if (req.user.role !== 'doctor' && req.user.role !== 'admin') {
      return res.status(403).json({ message: 'Clinician role required' });
    }

    const kase = await ClinicianCase.findById(req.params.id);
    if (!kase) return res.status(404).json({ message: 'Case not found' });
    if (kase.status !== 'AWAITING_REVIEW') {
      return res.status(409).json({ message: `Case already ${kase.status}` });
    }

    const reason = (req.body && req.body.reason) || '';
    if (verb === 'override' && !reason.trim()) {
      return res.status(400).json({ message: 'Override requires a reason' });
    }

    const kb = await kbLoader.load();

    // Append-only audit of the clinician decision (and override linkage).
    if (kase.auditSeq != null) {
      await ledger.recordOverride({
        episodeId: kase.episodeId || null,
        patientId: kase.patientId,
        correctsSeq: kase.auditSeq,
        clinicianId: req.user._id,
        rationale: `${verb}: ${reason}`,
        kbVersion: kb.kbVersion,
        rulesVersion: kb.rulesVersion,
      });
    } else {
      await ledger.append({
        episodeId: kase.episodeId || null,
        patientId: kase.patientId,
        decisionType: 'clinician_decision',
        decidedBy: 'clinician',
        autonomous: false,
        clinicianId: req.user._id,
        rationale: `${verb}: ${reason}`,
        kbVersion: kb.kbVersion,
        rulesVersion: kb.rulesVersion,
      });
    }

    // On APPROVE/MODIFY, the previously-blocked action may now execute — but it
    // must go BACK THROUGH THE GATE, never call the executor directly. Routing
    // via aegisService.submit({ clinicianApproved: true }) means the (possibly
    // modified) payload is still re-classified, red-flag-detected, written to
    // the audit ledger and made idempotent. The clinicianApproved flag is the
    // ONLY thing that lets the resulting RED disposition execute, and only
    // because a named clinician explicitly authorized it on this case.
    let executed = null;
    if (verb === 'approve' || verb === 'modify') {
      try {
        executed = await aegisService.submit({
          patientId: kase.patientId,
          patientName: kase.patientName,
          doctorId: kase.doctorId,
          episodeId: kase.episodeId,
          riskLevel: kase.riskLevel,
          actionType: kase.proposedAction.actionType,
          inputs: kase.proposedAction.inputs || {},
          text: kase.proposedAction.text || '',
          confidence: kase.proposedAction.confidence,
          payload: verb === 'modify'
            ? (req.body.payload || kase.proposedAction.payload)
            : kase.proposedAction.payload,
          clinicianApproved: true,
          clinicianId: req.user._id,
        });
      } catch (e) {
        executed = { executed: false, error: e.message };
      }
    }

    kase.status = status;
    kase.resolvedBy = req.user._id;
    kase.resolutionReason = reason;
    kase.resolvedAt = new Date();
    await kase.save();

    res.json({ case: kase, executed });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// ── Ledger inspection (audit + integrity proof for the demo) ─────────────────
router.get('/ledger/:patientId', auth, patientAccess(), async (req, res) => {
  try {
    const chain = await DecisionAudit.find({ patientId: req.params.patientId }).sort({ seq: 1 }).lean();
    res.json({ ledger: chain, integrity: ledger.verifyChain(chain) });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// ── KB introspection ─────────────────────────────────────────────────────────
router.get('/kb', auth, async (req, res) => {
  const kb = await kbLoader.load();
  res.json({
    kbVersion: kb.kbVersion, rulesVersion: kb.rulesVersion,
    redFlags: kb.redFlagRules.length, thresholds: kb.thresholds.length,
    specialties: Object.keys(kb.specialtyMap || {}),
  });
});

// ── KB hot-reload (admin) ────────────────────────────────────────────────────
// After seeding a new KB version, a long-running server still holds the old KB
// in its in-process cache (the seed runs in a different process). This drops
// the cache and reloads the active version with no restart.
router.post('/kb/reload', auth, roleCheck('admin'), async (req, res) => {
  try {
    kbLoader.invalidate();
    const kb = await kbLoader.load(true);
    res.json({
      reloaded: true, kbVersion: kb.kbVersion, rulesVersion: kb.rulesVersion,
      redFlags: kb.redFlagRules.length, thresholds: kb.thresholds.length,
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

module.exports = router;
