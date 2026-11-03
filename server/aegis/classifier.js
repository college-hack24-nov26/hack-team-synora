/**
 * Aegis action-class classifier — the trust spine.
 *
 * Pure, deterministic function of (riskLevel, triggeredFlags, confidence,
 * actionType). Same inputs ALWAYS produce the same class — the demo and the
 * audit depend on this. The LLM is never consulted here.
 *
 *   GREEN  — autonomous reversible/non-prescriptive action allowed
 *   AMBER  — informational half executes; doctor notified (non-blocking);
 *            no autonomous clinical action
 *   RED    — HARD BLOCK; synchronous clinician review required; nothing
 *            consequential dispatched
 *
 * Rules (ActionClass = max severity over all that trigger):
 *   - ANY red flag                      -> RED
 *   - riskLevel == 'critical'           -> RED
 *   - riskLevel == 'high'               -> AMBER  (mirrors shouldAlertDoctor)
 *   - action is prescriptive/irreversible -> at least AMBER (never GREEN)
 *   - confidence below floor on a >=high call -> escalate one class
 *   - else                              -> GREEN
 *
 * Fail-closed: missing/garbage inputs default to RED, never GREEN.
 */

const ORDER = { GREEN: 0, AMBER: 1, RED: 2 };
const CONFIDENCE_FLOOR = 0.45; // below this, a high-risk call can't ride GREEN/AMBER unescalated

function maxClass(a, b) {
  return ORDER[a] >= ORDER[b] ? a : b;
}

const REVERSIBLE_SAFE_ACTIONS = new Set([
  'show_result', 'nudge', 'schedule_routine_followup', 'save_record', 'suggest_screening',
]);

/**
 * @param {Object} p
 * @param {('low'|'moderate'|'high'|'critical')} p.riskLevel
 * @param {Array<{flagKey:string}>|string[]} [p.triggeredFlags]
 * @param {number} [p.confidence]  0..1 trust in the evidence
 * @param {string} [p.actionType]  what the agent wants to do
 * @returns {{actionClass:'GREEN'|'AMBER'|'RED', reasons:string[]}}
 */
function classify({ riskLevel, triggeredFlags = [], confidence = 1, actionType = 'show_result' } = {}) {
  const reasons = [];

  // Fail-closed on bad input.
  const validRisk = ['low', 'moderate', 'high', 'critical'].includes(riskLevel);
  if (!validRisk) {
    return { actionClass: 'RED', reasons: ['fail_closed: invalid or missing riskLevel'] };
  }

  const flags = (triggeredFlags || []).map(f => (typeof f === 'string' ? f : f.flagKey));
  let cls = 'GREEN';

  if (flags.length > 0) {
    cls = maxClass(cls, 'RED');
    reasons.push(`red_flag: ${flags.join(', ')}`);
  }

  if (riskLevel === 'critical') {
    cls = maxClass(cls, 'RED');
    reasons.push('risk_critical');
  } else if (riskLevel === 'high') {
    cls = maxClass(cls, 'AMBER');
    reasons.push('risk_high -> doctor notified');
  }

  // Prescriptive / irreversible actions can never be GREEN.
  if (!REVERSIBLE_SAFE_ACTIONS.has(actionType)) {
    cls = maxClass(cls, 'AMBER');
    reasons.push(`action_requires_oversight: ${actionType}`);
  }

  // Low-confidence escalation on consequential risk.
  if (confidence < CONFIDENCE_FLOOR && (riskLevel === 'high' || riskLevel === 'critical')) {
    const escalated = cls === 'GREEN' ? 'AMBER' : 'RED';
    if (ORDER[escalated] > ORDER[cls]) {
      reasons.push(`low_confidence(${confidence}) on ${riskLevel} -> escalate`);
      cls = escalated;
    }
  }

  if (reasons.length === 0) reasons.push('low/moderate, no flags, reversible action');
  return { actionClass: cls, reasons };
}

module.exports = { classify, CONFIDENCE_FLOOR, REVERSIBLE_SAFE_ACTIONS };
