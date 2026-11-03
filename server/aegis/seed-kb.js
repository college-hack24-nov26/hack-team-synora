#!/usr/bin/env node
/**
 * Seed the Aegis knowledge base (kb_* collections) for version kb-2026-06.
 *
 * Every threshold here is ported verbatim from the on-device Dart analyzers
 * (lib/services/lab_report_analyzer.dart, vitals_analyzer.dart,
 * specialty_recommender.dart) so the server is the single, versioned source
 * of truth. Numbers are real clinical cutoffs (ADA / WHO / AHA-ACC / ICMR).
 *
 *   node server/aegis/seed-kb.js              # seed/refresh kb-2026-06, set active
 *   node server/aegis/seed-kb.js --dry        # validate against schema, no DB write
 *
 * --dry runs the full build + Mongoose document validation WITHOUT a database,
 * so it can be verified offline. A real run requires MONGODB_URI.
 */

require('dotenv').config();
const mongoose = require('mongoose');

const KbVersion = require('../src/models/KbVersion');
const KbDiseaseThreshold = require('../src/models/KbDiseaseThreshold');
const KbRedFlag = require('../src/models/KbRedFlag');
const KbSpecialtyMap = require('../src/models/KbSpecialtyMap');

const KB_VERSION = 'kb-2026-06';
const DRY = process.argv.includes('--dry');

// ── Disease marker thresholds (from lab_report_analyzer.dart) ────────────────
const thresholds = [
  // Diabetes
  { disease: 'diabetes', markerKey: 'hba1c', display: 'HbA1c', unit: '%', referenceRange: '< 5.7% normal • 5.7–6.4% prediabetes • ≥ 6.5% diabetes', highWarn: 5.7, highCritical: 9.0, weight: 0.55, guideline: 'ADA/ICMR' },
  { disease: 'diabetes', markerKey: 'fbs', display: 'Fasting Blood Sugar', unit: 'mg/dL', referenceRange: '70–99 normal • 100–125 prediabetes • ≥ 126 diabetes', lowCutoff: 70, highWarn: 100, highCritical: 200, weight: 0.55, guideline: 'ADA' },
  { disease: 'diabetes', markerKey: 'ppbs', display: 'Postprandial Blood Sugar', unit: 'mg/dL', referenceRange: '< 140 normal • 140–199 prediabetes • ≥ 200 diabetes', highWarn: 140, highCritical: 200, weight: 0.55, guideline: 'ADA' },
  { disease: 'diabetes', markerKey: 'rbs', display: 'Random Blood Sugar', unit: 'mg/dL', referenceRange: '< 200 mg/dL', highWarn: 140, highCritical: 200, weight: 0.55, guideline: 'ADA' },
  // Hypertension
  { disease: 'hypertension', markerKey: 'systolic_bp', display: 'Systolic BP', unit: 'mmHg', referenceRange: '< 120 normal • 120–129 elevated • 130–139 stage 1 • ≥ 140 stage 2', lowCutoff: 90, highWarn: 130, highCritical: 180, weight: 0.55, guideline: 'AHA/ACC 2017' },
  { disease: 'hypertension', markerKey: 'diastolic_bp', display: 'Diastolic BP', unit: 'mmHg', referenceRange: '< 80 normal • 80–89 stage 1 • ≥ 90 stage 2', lowCutoff: 60, highWarn: 80, highCritical: 120, weight: 0.55, guideline: 'AHA/ACC 2017' },
  { disease: 'hypertension', markerKey: 'total_cholesterol', display: 'Total Cholesterol', unit: 'mg/dL', referenceRange: '< 200 desirable • 200–239 borderline • ≥ 240 high', highWarn: 200, highCritical: 240, weight: 0.55, guideline: 'AHA/ACC' },
  { disease: 'hypertension', markerKey: 'ldl', display: 'LDL Cholesterol', unit: 'mg/dL', referenceRange: '< 100 optimal • 100–129 near optimal • ≥ 160 high', highWarn: 130, highCritical: 160, weight: 0.55, guideline: 'AHA/ACC' },
  { disease: 'hypertension', markerKey: 'creatinine', display: 'Serum Creatinine', unit: 'mg/dL', referenceRange: '0.6–1.3 mg/dL (adults)', highWarn: 1.3, highCritical: 2.0, weight: 0.55, guideline: 'KDIGO' },
  { disease: 'hypertension', markerKey: 'sodium', display: 'Sodium', unit: 'mmol/L', referenceRange: '135–145 mmol/L', lowCutoff: 135, highWarn: 145, highCritical: 160, weight: 0.55, guideline: 'reference' },
  // Anemia
  { disease: 'anemia', markerKey: 'hemoglobin', display: 'Hemoglobin', unit: 'g/dL', referenceRange: 'Men ≥ 13 • Women ≥ 12 • Severe < 8 g/dL (WHO)', lowCritical: 8.0, lowCutoff: 12.0, weight: 0.55, guideline: 'WHO' },
  { disease: 'anemia', markerKey: 'mcv', display: 'MCV', unit: 'fL', referenceRange: '80–100 fL', lowCutoff: 80, highWarn: 100, weight: 0.55, guideline: 'reference' },
  { disease: 'anemia', markerKey: 'mch', display: 'MCH', unit: 'pg', referenceRange: '27–33 pg', lowCutoff: 27, highWarn: 33, weight: 0.55, guideline: 'reference' },
  { disease: 'anemia', markerKey: 'ferritin', display: 'Ferritin', unit: 'ng/mL', referenceRange: 'Men 24–336 • Women 11–307 ng/mL', lowCritical: 10, lowCutoff: 15, highWarn: 300, weight: 0.55, guideline: 'WHO' },
  { disease: 'anemia', markerKey: 'rbc', display: 'RBC Count', unit: 'million/µL', referenceRange: 'Men 4.7–6.1 • Women 4.2–5.4', lowCritical: 3.5, lowCutoff: 4.2, weight: 0.55, guideline: 'reference' },
  { disease: 'anemia', markerKey: 'hct', display: 'Hematocrit', unit: '%', referenceRange: 'Men 41–50 • Women 36–44 %', lowCritical: 30, lowCutoff: 36, weight: 0.55, guideline: 'reference' },
];

// ── Red-flag rules (spec §4.2 + vitals_analyzer.dart + main.py _check_alerts) ─
const redFlags = [
  { flagKey: 'critical_hypoxemia', label: 'Critical hypoxemia', field: 'spo2', op: 'lt', threshold: 88, source: 'wearable/PPG snapshot', guideline: 'WHO' },
  { flagKey: 'hypertensive_crisis_sbp', label: 'Hypertensive crisis (systolic)', field: 'systolic', op: 'gte', threshold: 180, source: 'vitals/lab', guideline: 'AHA/ACC 2017' },
  { flagKey: 'hypertensive_crisis_dbp', label: 'Hypertensive crisis (diastolic)', field: 'diastolic', op: 'gte', threshold: 120, source: 'vitals/lab', guideline: 'AHA/ACC 2017' },
  { flagKey: 'severe_tachycardia', label: 'Severe tachycardia', field: 'heart_rate', op: 'gte', threshold: 130, source: 'vitals snapshot', guideline: 'composite' },
  { flagKey: 'severe_bradycardia', label: 'Severe bradycardia', field: 'heart_rate', op: 'lt', threshold: 50, source: 'vitals snapshot', guideline: 'composite' },
  { flagKey: 'severe_anemia_hb', label: 'Severe anemia (Hb)', field: 'hb_estimate', op: 'lt', threshold: 7, source: 'pallor/lab', guideline: 'WHO' },
  { flagKey: 'acute_coronary_pattern', label: 'Acute coronary pattern (chest pain + dyspnea)', op: 'keywords', keywordGroups: [['chest pain', 'chest tightness', 'chest pressure'], ['shortness of breath', 'breathless', 'dyspnea', "can't breathe", 'cannot breathe']], source: 'symptom questionnaire', guideline: 'composite' },
  { flagKey: 'suicidal_ideation', label: 'Suicidal ideation', op: 'keywords', keywordGroups: [['suicidal', 'kill myself', 'end my life', 'self-harm', 'self harm', "don't want to live", 'want to die']], source: 'MindSpace transcript', guideline: 'crisis-screening' },
];

// ── Specialty map (from specialty_recommender.dart) ──────────────────────────
const specialtyMaps = [
  { disease: 'diabetes', specialties: [
    { name: 'Endocrinologist', rank: 1 },
    { name: 'Diabetologist', rank: 2 },
    { name: 'Ophthalmologist', rank: 3, note: 'retinopathy follow-up' },
    { name: 'General Physician', rank: 4 },
  ]},
  { disease: 'hypertension', specialties: [
    { name: 'Cardiologist', rank: 1 },
    { name: 'Nephrologist', rank: 2 },
    { name: 'General Physician', rank: 3 },
  ]},
  { disease: 'anemia', specialties: [
    { name: 'Hematologist', rank: 1 },
    { name: 'Gynecologist', rank: 2, onlyIfFemale: true, note: 'menstrual iron-loss is a major cause in women' },
    { name: 'General Physician', rank: 3 },
  ]},
];

const versionDoc = {
  version: KB_VERSION,
  active: true,
  description: 'Initial Aegis KB — ported from on-device Dart analyzers.',
  sources: ['ADA Standards of Care', 'ICMR-INDIAB', 'AHA/ACC 2017', 'WHO Anemia Thresholds', 'NFHS-5', 'KDIGO'],
};

function buildDocs() {
  return {
    version: new KbVersion(versionDoc),
    thresholds: thresholds.map(t => new KbDiseaseThreshold({ ...t, kbVersion: KB_VERSION })),
    redFlags: redFlags.map(r => new KbRedFlag({ ...r, kbVersion: KB_VERSION })),
    specialtyMaps: specialtyMaps.map(s => new KbSpecialtyMap({ ...s, kbVersion: KB_VERSION })),
  };
}

async function validateAll(docs) {
  const all = [docs.version, ...docs.thresholds, ...docs.redFlags, ...docs.specialtyMaps];
  for (const d of all) {
    await d.validate(); // throws on schema violation
  }
  return all.length;
}

(async () => {
  const docs = buildDocs();

  if (DRY) {
    try {
      const n = await validateAll(docs);
      console.log(`DRY RUN — built and schema-validated ${n} documents for ${KB_VERSION}:`);
      console.log(`  • 1 version  • ${docs.thresholds.length} thresholds  • ${docs.redFlags.length} red-flags  • ${docs.specialtyMaps.length} specialty maps`);
      console.log('All documents valid. No database write performed.');
      process.exit(0);
    } catch (err) {
      console.error('VALIDATION FAILED:', err.message);
      process.exit(1);
    }
  }

  const uri = process.env.MONGODB_URI;
  if (!uri) {
    console.error('MONGODB_URI not set. Use --dry to validate without a database.');
    process.exit(1);
  }

  await mongoose.connect(uri, { serverSelectionTimeoutMS: 10000 });
  console.log(`Connected. Seeding ${KB_VERSION} ...`);

  // Idempotent: clear this version's rows, deactivate others, re-insert.
  await KbDiseaseThreshold.deleteMany({ kbVersion: KB_VERSION });
  await KbRedFlag.deleteMany({ kbVersion: KB_VERSION });
  await KbSpecialtyMap.deleteMany({ kbVersion: KB_VERSION });
  await KbVersion.updateMany({}, { $set: { active: false } });
  await KbVersion.deleteOne({ version: KB_VERSION });

  await KbVersion.create(versionDoc);
  await KbDiseaseThreshold.insertMany(thresholds.map(t => ({ ...t, kbVersion: KB_VERSION })));
  await KbRedFlag.insertMany(redFlags.map(r => ({ ...r, kbVersion: KB_VERSION })));
  await KbSpecialtyMap.insertMany(specialtyMaps.map(s => ({ ...s, kbVersion: KB_VERSION })));

  // Invalidate the in-process KB cache so any loader sharing this process sees
  // the new version immediately. A SEPARATELY running API server must reload
  // via POST /api/aegis/kb/reload (admin) or a restart — the cache there is in
  // a different process and cannot be invalidated from here.
  try { require('./kb').invalidate(); } catch (_) {}

  console.log(`Seeded ${KB_VERSION}: ${thresholds.length} thresholds, ${redFlags.length} red-flags, ${specialtyMaps.length} specialty maps. Marked active.`);
  console.log('NOTE: if an API server is already running, call POST /api/aegis/kb/reload (admin) or restart it to pick up this KB.');
  await mongoose.disconnect();
  process.exit(0);
})().catch(err => {
  console.error('Seed failed:', err.message);
  process.exit(1);
});
