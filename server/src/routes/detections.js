const express = require('express');
const { body, validationResult } = require('express-validator');
const auth = require('../middleware/auth');
const patientAccess = require('../middleware/patientAccess');
const DetectionRecord = require('../models/DetectionRecord');
const DiseaseRiskResult = require('../models/DiseaseRiskResult');
const aegisService = require('../../aegis/service');

const router = express.Router();

// Map an image-classifier output to an Aegis risk level. We DON'T trust the
// label alone — a "normal" class is low, known serious classes are high, and a
// low classifier confidence on a serious-looking class keeps it elevated so the
// gate can require oversight. Conservative by design (fail toward review).
const SERIOUS_CLASS_RE = /melanoma|carcinoma|malignan|tumou?r|glioma|pneumonia|nodule|cardiomeg|effusion|mass|lesion|stenosis|regurgitation/i;
const NORMAL_CLASS_RE = /normal|benign|healthy|no finding|clear/i;
function detectionRiskLevel(className, confidence) {
  const name = String(className || '');
  if (NORMAL_CLASS_RE.test(name)) return 'low';
  if (SERIOUS_CLASS_RE.test(name)) {
    // Confidence here is 0..1 for image models (heart_sound passes BPM, handled
    // by caller). High-confidence serious finding => high; otherwise moderate.
    return (typeof confidence === 'number' && confidence >= 0.6) ? 'high' : 'moderate';
  }
  return 'moderate'; // unknown/abnormal-ish label → needs a human glance
}

// ── Disease risk results (chronic-disease screening) ─────────────────────────

// POST /api/detections/risk-result — persist a screening outcome to MongoDB.
// Patients file for themselves; doctors/admins may file on a patient's behalf.
router.post('/risk-result', auth, async (req, res) => {
  try {
    const b = req.body || {};
    const patientId = b.patientId || (req.user.role === 'patient' ? req.user._id.toString() : null);
    if (!patientId) return res.status(400).json({ message: 'patientId required' });
    if (req.user.role === 'patient' && patientId !== req.user._id.toString()) {
      return res.status(403).json({ message: 'Cannot file a result for another patient' });
    }
    if (!b.disease) return res.status(400).json({ message: 'disease required' });

    const result = await DiseaseRiskResult.create({
      patientId,
      disease: b.disease,
      method: b.method || '',
      risk: b.risk || 'LOW',
      score: typeof b.score === 'number' ? b.score : 0,
      headline: b.headline || '',
      findings: Array.isArray(b.findings) ? b.findings : [],
      topContributors: Array.isArray(b.topContributors) ? b.topContributors : [],
      recommendations: Array.isArray(b.recommendations) ? b.recommendations : [],
      dataSource: b.dataSource || '',
      llmExplanation: b.llmExplanation || null,
      measuredAt: b.timestamp ? new Date(b.timestamp) : new Date(),
    });
    res.status(201).json({ result });
  } catch (error) {
    console.error('Save disease risk result error:', error);
    res.status(500).json({ message: 'Server error saving risk result' });
  }
});

// GET /api/detections/risk-results/:patientId — screening history (most recent
// first). Guarded so only the patient, their linked doctor, or an admin reads.
router.get('/risk-results/:patientId', auth, patientAccess(), async (req, res) => {
  try {
    const q = { patientId: req.params.patientId };
    if (req.query.disease) q.disease = req.query.disease;
    const results = await DiseaseRiskResult.find(q)
      .sort({ measuredAt: -1 })
      .limit(Number(req.query.limit) || 100)
      .lean();
    res.json({ results });
  } catch (error) {
    console.error('Fetch risk results error:', error);
    res.status(500).json({ message: 'Server error fetching risk results' });
  }
});

// POST /api/detections - save a detection result (no image, metadata only)
router.post('/', auth, [
  body('className').notEmpty().withMessage('Class name is required'),
  body('confidence').isFloat({ min: 0 }).withMessage('Confidence must be a positive number'),
  body('category').isIn(['skin', 'chest', 'brain', 'heart_sound']).withMessage('Invalid category'),
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ message: errors.array()[0].msg });
    }

    const { className, confidence, category, description, patientId } = req.body;

    const resolvedPatientId = patientId || (req.user.role === 'patient' ? req.user._id.toString() : null);
    const record = await DetectionRecord.create({
      className,
      confidence,
      category,
      description: description || '',
      patientId: resolvedPatientId,
      doctorId: req.user.role === 'doctor' ? req.user._id : null,
      performedBy: req.user._id,
    });

    // Route image/heart-sound detections through the Aegis safety gate so they
    // get the same treatment as the chronic-disease deck: classification,
    // red-flag detection on the class label, audit-ledger entry, and (for a
    // serious finding) doctor notification or a human-gated RED case. The
    // detection itself is already saved above — gating never blocks the record.
    let aegis = null;
    if (resolvedPatientId) {
      try {
        // heart_sound passes BPM as confidence; image models pass 0..1. Only
        // pass a 0..1 confidence to the gate so its confidence rule behaves.
        const conf = (category === 'heart_sound')
          ? undefined
          : (typeof confidence === 'number' && confidence <= 1 ? confidence : undefined);
        aegis = await aegisService.submit({
          patientId: resolvedPatientId,
          patientName: '',
          doctorId: req.user.role === 'doctor' ? req.user._id : undefined,
          riskLevel: detectionRiskLevel(className, conf),
          actionType: 'show_result',
          confidence: conf,
          text: `${category} finding: ${className}. ${description || ''}`,
          summary: `${category} screening: ${className}`,
        });
      } catch (gateErr) {
        console.error('Aegis gate (detection) error:', gateErr.message);
      }
    }

    res.status(201).json({ record, aegis });
  } catch (error) {
    console.error('Save detection error:', error);
    res.status(500).json({ message: 'Server error saving detection' });
  }
});

// GET /api/detections/:patientId - get detections for a patient (used by doctors)
router.get('/:patientId', auth, patientAccess(), async (req, res) => {
  try {
    const records = await DetectionRecord.find({ patientId: req.params.patientId })
      .sort({ createdAt: -1 })
      .populate('performedBy', 'name role');

    res.json({ records });
  } catch (error) {
    console.error('Fetch detections error:', error);
    res.status(500).json({ message: 'Server error fetching detections' });
  }
});

module.exports = router;
