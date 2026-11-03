/**
 * Red-flag detection — pure, deterministic evaluation of structured inputs +
 * free text against the kb_red_flags rule set. NEVER LLM-arbitrated.
 *
 * `rules` is the array of KbRedFlag docs (passed in, so this stays pure and
 * testable without a DB). `inputs` is a flat object of structured signals
 * (spo2, systolic, diastolic, heart_rate, hb_estimate, ...). `text` is any
 * free text (symptom description, MindSpace transcript).
 *
 * Returns the list of triggered flagKeys (with labels).
 */

function numericTrips(rule, inputs) {
  const v = inputs[rule.field];
  if (v === undefined || v === null || Number.isNaN(Number(v))) return false;
  const n = Number(v);
  switch (rule.op) {
    case 'gte': return n >= rule.threshold;
    case 'gt':  return n >  rule.threshold;
    case 'lte': return n <= rule.threshold;
    case 'lt':  return n <  rule.threshold;
    default:    return false;
  }
}

function keywordsTrip(rule, text) {
  if (!text || !Array.isArray(rule.keywordGroups)) return false;
  const hay = String(text).toLowerCase();
  // Every group must have at least one keyword present (AND across groups,
  // OR within a group) — e.g. (chest pain) AND (dyspnea).
  return rule.keywordGroups.every(group =>
    group.some(kw => hay.includes(String(kw).toLowerCase()))
  );
}

function detect(rules, { inputs = {}, text = '' } = {}) {
  const triggered = [];
  for (const rule of rules) {
    let trips = false;
    if (rule.op === 'keywords') trips = keywordsTrip(rule, text);
    else trips = numericTrips(rule, inputs);
    if (trips) triggered.push({ flagKey: rule.flagKey, label: rule.label });
  }
  return triggered;
}

module.exports = { detect, numericTrips, keywordsTrip };
