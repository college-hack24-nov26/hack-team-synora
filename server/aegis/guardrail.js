/**
 * Output guardrail — the no-diagnosis lint. Pure + testable.
 *
 * MedicoScope is a SCREENING tool, not a diagnostic one. Patient-facing text
 * must never assert a diagnosis ("you have diabetes") or prescribe dosing.
 * This lint scans generated/LLM text and flags banned phrasing so it can be
 * rewritten to screening framing or blocked. It also blocks aspirational
 * dataset citations (APTOS/EyePACS/Emory/AIIMS) from patient-facing copy,
 * since our analyzers are heuristics, not models trained on those sets.
 */

const DIAGNOSIS_PATTERNS = [
  /\byou\s+have\b\s+(diabetes|hypertension|anemia|anaemia|cancer|a\s+tumou?r)/i,
  /\byou\s+(are|'re)\s+diagnosed\b/i,
  /\bdiagnos(is|ed)\s+(is|:)\s/i,
  /\byou\s+(are|'re)\s+(diabetic|hypertensive|anemic|anaemic)\b/i,
  /\bdefinitely\s+have\b/i,
  /\bconfirmed?\s+case\s+of\b/i,
];

const PRESCRIPTION_PATTERNS = [
  /\btake\s+\d+\s*(mg|ml|tablets?|pills?|units?)\b/i,
  /\b\d+\s*(mg|ml)\s+(daily|twice|once|per day|bd|od)\b/i,
  /\bprescrib(e|ing|ed)\b/i,
  /\bstart\s+(you\s+)?on\s+\w+\s+\d+\s*mg\b/i,
];

const ASPIRATIONAL_CITATIONS = [
  /\bAPTOS\b/, /\bEyePACS\b/, /\bMessidor\b/, /\bEmory\b/, /\bAIIMS\b/,
];

function lint(text) {
  if (!text || typeof text !== 'string') return { ok: true, violations: [] };
  const violations = [];
  for (const p of DIAGNOSIS_PATTERNS) {
    const m = text.match(p);
    if (m) violations.push({ type: 'diagnostic_claim', match: m[0] });
  }
  for (const p of PRESCRIPTION_PATTERNS) {
    const m = text.match(p);
    if (m) violations.push({ type: 'prescription', match: m[0] });
  }
  for (const p of ASPIRATIONAL_CITATIONS) {
    const m = text.match(p);
    if (m) violations.push({ type: 'aspirational_citation', match: m[0] });
  }
  return { ok: violations.length === 0, violations };
}

/** Mandatory screening disclaimer appended to every patient-facing result. */
const DISCLAIMER =
  'This is an AI screening signal, not a diagnosis. Please consult a qualified clinician for evaluation.';

function ensureDisclaimer(text) {
  if (!text) return DISCLAIMER;
  if (text.toLowerCase().includes('not a diagnosis')) return text;
  return `${text.trim()}\n\n${DISCLAIMER}`;
}

module.exports = { lint, ensureDisclaimer, DISCLAIMER };
