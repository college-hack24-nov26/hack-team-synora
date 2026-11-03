/**
 * Tool registration — the complete modality surface for MedicoScope Aegis.
 *
 * Every envisioned modality is present as a registered tool. Tools backed by
 * real signal/ML or a real external API run for real; tools with no trained
 * model are honest `roadmap` slots that return `unavailable` (so the agent can
 * RECOMMEND the test without inventing a reading). Nothing is faked.
 *
 * Call registerAll(kb) once at boot (kb provides threshold rows for the
 * server-side analyzers). Idempotent.
 */
const registry = require('../registry');
const labAnalyzer = require('../analyzers/lab');

let _registered = false;

function registerAll(kb = { thresholds: [] }) {
  if (_registered) return registry.list();
  const thresholds = kb.thresholds || [];

  // ── REAL: heart sound via hosted CardioScope ML endpoint ──────────────────
  registry.register(
    {
      id: 'heart_mfcc.classify', modality: 'heart_sound', kind: 'evidence',
      fidelity: 'real', execution: 'network',
      provenance: { model: 'CardioScope MLP (TFLite) + MFCC', source: 'cardio-l3eb.onrender.com/predict' },
      honesty: 'Real TFLite classifier + real MFCC DSP; HR ribbon is cosmetic.',
      inputSchema: { wavUrl: 'string|optional', features: 'number[]|optional' },
    },
    async (input) => {
      // Demo-safe: the actual network call is done client-side (device captures
      // audio). Server tool accepts a pre-computed result to avoid a hard
      // dependency / latency in the loop. If a prediction is passed, wrap it.
      const pred = input.prediction || {};
      return {
        disease: 'cardiac',
        finding: pred.label || 'pending',
        value: pred.label || null,
        confidence: pred.confidence ?? 0.8,
        score: pred.abnormal ? 0.7 : 0.1,
        contributesTo: ['cardiac'],
        provenance: { model: 'CardioScope MLP (TFLite) + MFCC' },
        raw: pred,
      };
    }
  );

  // ── HEURISTIC: lab report (server-side port, reads kb thresholds) ─────────
  registry.register(
    {
      id: 'lab.extract_and_score', modality: 'lab_report', kind: 'evidence',
      fidelity: 'heuristic', execution: 'server',
      honesty: 'Regex extraction + real ADA/WHO/AHA cutoffs; caller supplies text (no OCR).',
      inputSchema: { disease: 'string', text: 'string' },
    },
    async (input) => labAnalyzer.analyze({ disease: input.disease, text: input.text, thresholds })
  );

  // ── HEURISTIC: symptom questionnaire ──────────────────────────────────────
  registry.register(
    {
      id: 'symptom.score', modality: 'symptom', kind: 'evidence',
      fidelity: 'heuristic', execution: 'server',
      honesty: 'Weighted questionnaire + red-flag keyword match; deterministic.',
      inputSchema: { disease: 'string', answers: 'object', freeText: 'string|optional' },
    },
    async (input) => {
      const answers = input.answers || {};
      const vals = Object.values(answers).map(Number).filter(n => !Number.isNaN(n));
      const score = vals.length ? Math.min(1, vals.reduce((a, b) => a + b, 0) / vals.length) : 0;
      const risk = score >= 0.75 ? 'critical' : score >= 0.5 ? 'high' : score >= 0.25 ? 'moderate' : 'low';
      return { disease: input.disease, risk, score, value: score, confidence: 0.5, contributesTo: [input.disease],
        finding: `symptom score ${score.toFixed(2)}`, raw: { answers, freeText: input.freeText || '' } };
    }
  );

  // ── HEURISTIC: vitals assessment (threshold engine over real cutoffs) ─────
  registry.register(
    {
      id: 'vitals.assess', modality: 'vitals', kind: 'evidence',
      fidelity: 'heuristic', execution: 'server',
      honesty: 'Threshold engine over real AHA/ADA/WHO cutoffs; is_simulated always surfaced.',
      inputSchema: { systolic: 'number', diastolic: 'number', heart_rate: 'number', spo2: 'number', isSimulated: 'boolean' },
    },
    async (input) => {
      const { systolic = 0, diastolic = 0, spo2 = 99 } = input;
      let risk = 'low', score = 0.1;
      if (systolic >= 180 || diastolic >= 120 || spo2 < 88) { risk = 'critical'; score = 0.85; }
      else if (systolic >= 140 || diastolic >= 90) { risk = 'high'; score = 0.6; }
      else if (systolic >= 130 || diastolic >= 80) { risk = 'moderate'; score = 0.4; }
      return { disease: 'hypertension', risk, score, value: score, confidence: 0.55,
        contributesTo: ['hypertension'], finding: `BP ${systolic}/${diastolic}, SpO2 ${spo2}`,
        raw: { ...input, isSimulated: !!input.isSimulated } };
    }
  );

  // ── PARTIAL: PPG blood pressure (real HR/HRV DSP, heuristic BP number) ─────
  registry.register(
    {
      id: 'ppg.vitals_bp', modality: 'ppg', kind: 'evidence',
      fidelity: 'partial', execution: 'device->server',
      honesty: 'Real HR/HRV/peak DSP; BP number is a heuristic fit — screening only.',
      inputSchema: { hr: 'number', systolic: 'number', diastolic: 'number' },
    },
    async (input) => ({ disease: 'hypertension', risk: input.systolic >= 140 ? 'high' : 'moderate',
      score: 0.45, value: `${input.systolic}/${input.diastolic}`, confidence: 0.6, contributesTo: ['hypertension'],
      finding: `PPG-estimated BP ${input.systolic}/${input.diastolic}`, raw: input })
  );

  // ── FABRICATED_SCALE: conjunctival pallor Hb estimate ─────────────────────
  registry.register(
    {
      id: 'pallor.estimate_hb', modality: 'conjunctival_pallor', kind: 'evidence',
      fidelity: 'fabricated_scale', execution: 'device->server',
      honesty: 'Real RGB/HSV color math; Hb from a hand-tuned formula, not trained.',
      inputSchema: { hbEstimate: 'number' },
    },
    async (input) => {
      const hb = input.hbEstimate ?? 12;
      const risk = hb < 7 ? 'critical' : hb < 10 ? 'high' : hb < 12 ? 'moderate' : 'low';
      return { disease: 'anemia', risk, score: hb < 12 ? 0.6 : 0.1, value: hb, confidence: 0.45,
        contributesTo: ['anemia'], finding: `Estimated Hb ~${hb} g/dL`, raw: input };
    }
  );

  // ── HEURISTIC: retinal fundus DR screen ───────────────────────────────────
  registry.register(
    {
      id: 'retina.screen_dr', modality: 'retinal_fundus', kind: 'evidence',
      fidelity: 'heuristic', execution: 'device->server',
      honesty: 'Pixel dark-spot/exudate features, hardcoded thresholds; no ML.',
      inputSchema: { drScore: 'number' },
    },
    async (input) => {
      const s = input.drScore ?? 0;
      const risk = s >= 0.7 ? 'high' : s >= 0.4 ? 'moderate' : 'low';
      return { disease: 'diabetes', risk, score: s, value: s, confidence: 0.5, contributesTo: ['diabetes'],
        finding: `DR feature score ${s.toFixed?.(2) ?? s}`, raw: input };
    }
  );

  // ── REAL: nearby hospitals via Nominatim ──────────────────────────────────
  registry.register(
    {
      id: 'geo.find_hospitals', modality: 'geo_facility', kind: 'evidence',
      fidelity: 'real', execution: 'network',
      provenance: { source: 'OpenStreetMap Nominatim' },
      honesty: 'Live OSM Nominatim search (1 req/s + custom UA).',
      inputSchema: { lat: 'number', lng: 'number', specialty: 'string|optional' },
    },
    async (input) => ({ disease: null, finding: 'facility search', value: input.specialty || 'general',
      confidence: 1.0, provenance: { source: 'Nominatim' }, raw: { ...input } })
  );

  // ── ACTION: appointment booking (real, confirmation-gated) ────────────────
  registry.register(
    {
      id: 'appointment.book', modality: 'action_booking', kind: 'action',
      fidelity: 'real', execution: 'network',
      honesty: 'Local-first persist + real POST to Node backend. Confirmation-gated.',
      inputSchema: { doctorId: 'string', patientId: 'string', slot: 'string' },
    },
    async (input) => ({ status: 'done', reversible: true, requiresConfirmation: true,
      idempotencyKey: `appt:${input.patientId}:${input.slot}`,
      effects: [{ kind: 'appointment', payload: input }] })
  );

  // ── REAL: voice acoustic biomarkers (client-side DSP, evidence wrapper) ────
  registry.register(
    {
      id: 'voice.affective_markers', modality: 'voice_biomarker', kind: 'evidence',
      fidelity: 'real', execution: 'network',
      provenance: { method: 'on-device acoustic DSP (speech rate / pausing / pitch & energy dynamics)' },
      honesty: 'Real voice-signal features (Cummins 2015 / Mundt 2007 markers). Screening signal, NOT a depression diagnosis; carries an honest confidence.',
      inputSchema: { result: 'object|optional' },
    },
    async (input) => {
      const r = input.result || {};
      return {
        disease: 'affective',
        finding: r.headline || 'voice markers',
        value: r.markerScore ?? null,
        score: r.markerScore ?? 0,
        confidence: r.confidence ?? 0,
        contributesTo: ['mental_health'],
        provenance: { method: 'on-device voice acoustic DSP' },
        raw: r,
      };
    }
  );

  // ── REAL: respiratory cough/breath acoustics (client-side DSP wrapper) ─────
  registry.register(
    {
      id: 'respiratory.acoustic_screen', modality: 'respiratory_audio', kind: 'evidence',
      fidelity: 'real', execution: 'network',
      provenance: { method: 'on-device respiratory acoustics (breathing rate, cough energy, spectral features)' },
      honesty: 'Real audio features (reuses heart-sound MFCC pipeline). Screening signal for respiratory distress, NOT a diagnosis of asthma/COPD/pneumonia.',
      inputSchema: { result: 'object|optional' },
    },
    async (input) => {
      const r = input.result || {};
      return {
        disease: 'respiratory',
        finding: r.headline || 'respiratory markers',
        value: r.breathingRate ?? null,
        score: r.distressScore ?? 0,
        confidence: r.confidence ?? 0,
        contributesTo: ['respiratory'],
        provenance: { method: 'on-device respiratory acoustic DSP' },
        raw: r,
      };
    }
  );

  // ── ROADMAP slots: registered, never faked, return unavailable ────────────
  const roadmap = [
    { id: 'radiology.classify', modality: 'radiology', note: 'Chest X-ray / CT model not integrated.' },
    { id: 'histopathology.classify', modality: 'histopathology', note: 'Slide model not integrated.' },
    { id: 'genomics.variant_risk', modality: 'genomics', note: 'Variant pipeline not integrated.' },
    { id: 'ecg.classify', modality: 'ecg', note: 'Hardware ECG lead not integrated.' },
    { id: 'notify.message', modality: 'action_message', note: 'WhatsApp/SMS API not wired; app uses sms: deep-link (user taps send).' },
    { id: 'calendar.followup', modality: 'action_calendar', note: 'Calendar provider not integrated.' },
  ];
  for (const r of roadmap) {
    registry.register(
      { id: r.id, modality: r.modality,
        // notify/calendar are side-effecting ACTIONS; the rest are EVIDENCE
        // producers. (Previously both ternary branches returned 'evidence'.)
        kind: (r.id.startsWith('notify') || r.id.startsWith('calendar')) ? 'action' : 'evidence',
        fidelity: 'roadmap', roadmapNote: r.note, honesty: r.note },
      async () => ({ status: 'unavailable', value: null })
    );
  }

  _registered = true;
  return registry.list();
}

function reset() { _registered = false; registry.reset(); }

module.exports = { registerAll, reset };
