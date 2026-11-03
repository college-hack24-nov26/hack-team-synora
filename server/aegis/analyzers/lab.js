/**
 * Server-side lab analyzer — ported from lib/services/lab_report_analyzer.dart.
 * Regex marker extraction + flag logic against kb_disease_thresholds rows.
 * Heuristic fidelity (real clinical cutoffs, naive extraction; caller supplies
 * text — no OCR here, mirroring the Dart version).
 */

// Marker name patterns (ported from the Dart _MarkerSpec patterns).
const PATTERNS = {
  hba1c: [/hba1c/i, /glycated\s+h(a)?emoglobin/i, /\ba1c\b/i],
  fbs: [/fasting\s+blood\s+(sugar|glucose)/i, /\bfbs\b/i, /\bfbg\b/i, /fasting\s+plasma\s+glucose/i],
  ppbs: [/post\s*prandial/i, /\bppbs\b/i, /2\s*hr?\s*pp/i],
  rbs: [/random\s+blood\s+(sugar|glucose)/i, /\brbs\b/i],
  systolic_bp: [/systolic/i, /\bsbp\b/i],
  diastolic_bp: [/diastolic/i, /\bdbp\b/i],
  total_cholesterol: [/total\s+cholesterol/i, /cholesterol,?\s*total/i],
  ldl: [/\bldl\b/i, /low\s+density/i],
  creatinine: [/creatinine/i],
  sodium: [/sodium/i],
  hemoglobin: [/h(a)?emoglobin\s*(?!a1c)/i, /\bhgb\b/i, /\bhb\b(?!\s*a?1c)/i],
  mcv: [/\bmcv\b/i],
  mch: [/\bmch\b(?!c)/i],
  ferritin: [/ferritin/i],
  rbc: [/\brbc\b/i, /red\s+blood\s+cell/i],
  hct: [/h(a)?ematocrit/i, /\bhct\b/i, /\bpcv\b/i],
};

const FLAG_WEIGHT = { normal: 0, low: 0.55, high: 0.55, critical: 0.95 };

function extractValue(text, markerKey) {
  const pats = PATTERNS[markerKey] || [];
  for (const pat of pats) {
    const g = new RegExp(pat.source, pat.flags.includes('g') ? pat.flags : pat.flags + 'g');
    let m;
    while ((m = g.exec(text)) !== null) {
      const tail = text.slice(m.index + m[0].length, m.index + m[0].length + 160);
      const num = /([-+]?\d{1,6}(?:\.\d+)?)/.exec(tail);
      if (num) {
        const v = parseFloat(num[1]);
        if (!Number.isNaN(v) && v > 0 && v < 100000) return v;
      }
      if (!g.global) break;
    }
  }
  return null;
}

function flagFor(spec, v) {
  if (spec.highCritical != null && v >= spec.highCritical) return 'critical';
  if (spec.highWarn != null && v >= spec.highWarn) return 'high';
  if (spec.lowCritical != null && v < spec.lowCritical) return 'critical';
  if (spec.lowCutoff != null && v < spec.lowCutoff) return 'low';
  return 'normal';
}

/**
 * @param {string} disease  'diabetes'|'hypertension'|'anemia'
 * @param {string} text     raw lab-report text
 * @param {Array}  thresholds  kb_disease_thresholds rows (filtered to disease)
 */
function analyze({ disease, text, thresholds }) {
  const specs = (thresholds || []).filter(t => t.disease === disease);
  const findings = [];
  let total = 0, counted = 0, anyCritical = false;
  const contributors = [];

  for (const s of specs) {
    const v = extractValue(text || '', s.markerKey);
    if (v == null) continue;
    const flag = flagFor(s, v);
    const w = FLAG_WEIGHT[flag] ?? 0;
    total += w; counted += 1;
    if (flag === 'critical') anyCritical = true;
    if (w >= 0.5) contributors.push(`${s.display}: ${v} ${s.unit}`);
    findings.push({ name: s.display, value: String(v), unit: s.unit, referenceRange: s.referenceRange, flag });
  }

  const avg = counted === 0 ? 0 : Math.min(1, total / counted);
  const score = anyCritical ? Math.max(0.75, avg) : avg;
  let risk = 'low';
  if (counted === 0) risk = 'low';
  else if (anyCritical || score >= 0.75) risk = 'critical';
  else if (score >= 0.5) risk = 'high';
  else if (score >= 0.25) risk = 'moderate';

  // Confidence reflects extraction certainty: more markers found => higher,
  // capped later by the fidelity gate (heuristic <= 0.65).
  const confidence = counted === 0 ? 0.1 : Math.min(0.65, 0.3 + counted * 0.07);

  return {
    disease,
    risk, score, confidence,
    finding: counted === 0 ? 'No recognizable markers found' : `${counted} markers evaluated`,
    value: score,
    findings,
    contributesTo: [disease],
    topContributors: contributors.slice(0, 3),
    raw: { markersFound: counted, anyCritical },
  };
}

module.exports = { analyze, extractValue, flagFor };
