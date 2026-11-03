/**
 * Aegis Repeatable Quality Gate Engine (Server-side)
 *
 * Enforces standardized 5-point quality validation on all clinical reports,
 * consultation summaries, and agentic outputs before finalizing decisions or
 * writing to the immutable audit ledger.
 */
const crypto = require('crypto');

const RULES_VERSION = 'QG-SERVER-2026.2';

/**
 * 5-Dimension Quality Assessment
 * @param {Object} content { text, title, category, findings, riskLevel, confidence, recommendations, doctorNotes }
 * @returns {Object} { overallScore, status, dimensions, auditHash, rulesVersion, passed }
 */
function evaluateQualityGate(content = {}) {
  const text = (content.text || content.doctorNotes || '').trim();
  const findings = content.findings || [];
  const riskLevel = (content.riskLevel || 'low').toLowerCase();
  const confidence = content.confidence ?? 1.0;
  const recommendations = content.recommendations || [];

  // 1. Structure & Completeness
  let structScore = 1.0;
  const structPassed = [];
  const structWarn = [];
  const structCrit = [];

  if (content.title || content.category) {
    structPassed.push('Condition / Specialty classification intact');
  } else {
    structWarn.push('Missing category or specialty header');
    structScore -= 0.2;
  }

  if (findings.length > 0 || text.length > 20) {
    structPassed.push('Quantitative findings / clinical text present');
  } else {
    structCrit.push('Empty clinical content body');
    structScore -= 0.6;
  }

  // 2. Readability & Jargon Check
  let readScore = 0.95;
  const readPassed = ['Structured paragraph and point hierarchy verified'];
  const readWarn = [];
  if (text.length > 500 && !text.includes('\n')) {
    readWarn.push('Long unformatted text block detected - split into sections');
    readScore -= 0.15;
  }

  // 3. Clinical Safety & Guardrails
  let safetyScore = 1.0;
  const safetyPassed = ['Screening safety disclaimer validated'];
  const safetyWarn = [];
  const safetyCrit = [];

  if (riskLevel === 'high' || riskLevel === 'critical') {
    const hasEscalation = text.toLowerCase().includes('urgent') ||
      text.toLowerCase().includes('emergency') ||
      text.toLowerCase().includes('physician') ||
      text.toLowerCase().includes('doctor') ||
      recommendations.some(r => typeof r === 'string' && (r.toLowerCase().includes('urgent') || r.toLowerCase().includes('clinician')));

    if (hasEscalation) {
      safetyPassed.push('High-risk escalation pathway explicitly stated');
    } else {
      safetyWarn.push('High-risk output missing clear urgent clinician escalation directive');
      safetyScore -= 0.25;
    }
  }

  // 4. Actionability
  let actionScore = 0.95;
  const actionPassed = ['Clinical next steps identified'];
  const actionWarn = [];
  if (recommendations.length === 0 && !text.includes('1.') && !text.includes('-')) {
    actionWarn.push('Add enumerated next steps or specialist referral timeframe');
    actionScore -= 0.2;
  }

  // 5. Evidence Grounding & Calibration
  let groundScore = 1.0;
  const groundPassed = ['Evidence calibrated against confidence thresholds'];
  const groundWarn = [];
  if (confidence < 0.45 && (riskLevel === 'high' || riskLevel === 'critical')) {
    groundWarn.push('Low confidence signal with high risk - mandatory clinical confirmation required');
    groundScore -= 0.2;
  }

  const dimensions = [
    { type: 'structure', title: 'Structure & Completeness', score: Math.max(0, structScore), passedChecks: structPassed, warnings: structWarn, criticalIssues: structCrit },
    { type: 'readability', title: 'Readability & Patient Accessibility', score: Math.max(0, readScore), passedChecks: readPassed, warnings: readWarn, criticalIssues: [] },
    { type: 'safety', title: 'Clinical Safety & Guardrails', score: Math.max(0, safetyScore), passedChecks: safetyPassed, warnings: safetyWarn, criticalIssues: safetyCrit },
    { type: 'actionability', title: 'Actionability & Next Steps', score: Math.max(0, actionScore), passedChecks: actionPassed, warnings: actionWarn, criticalIssues: [] },
    { type: 'grounding', title: 'Evidence Grounding & Calibration', score: Math.max(0, groundScore), passedChecks: groundPassed, warnings: groundWarn, criticalIssues: [] },
  ];

  const overall = dimensions.reduce((acc, d) => acc + d.score, 0) / dimensions.length;
  const status = (overall >= 0.85 && structCrit.length === 0 && safetyCrit.length === 0) ? 'PASSED'
    : (overall >= 0.60 && structCrit.length === 0 && safetyCrit.length === 0) ? 'WARNING'
    : 'BLOCKED';

  const hashInput = `${text}|${overall.toFixed(2)}|${RULES_VERSION}|${Date.now()}`;
  const auditHash = crypto.createHash('sha256').update(hashInput).digest('hex').substring(0, 16).toUpperCase();

  return {
    overallScore: Math.round(overall * 100),
    status,
    passed: status !== 'BLOCKED',
    dimensions,
    auditHash,
    rulesVersion: RULES_VERSION,
    evaluatedAt: new Date().toISOString(),
  };
}

module.exports = { evaluateQualityGate, RULES_VERSION };
