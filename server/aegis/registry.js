/**
 * Tool Registry — the only callable surface for the agent. A modality that
 * isn't registered is uncallable. Each tool registers a manifest (with a
 * MANDATORY fidelity tag) + a handler. The registry runs the handler and
 * forces the output through the fidelity gate, so honesty is enforced
 * centrally, not per-tool.
 *
 * Registration fails fast (throws) if a manifest is missing fidelity — the
 * spec's "no default real; a manifest missing fidelity fails at boot."
 */
const { gateEvidence, gateAction, FIDELITY, FidelityError } = require('./envelopes');

const _tools = new Map();

/**
 * @param {Object} manifest { id, modality, kind: 'evidence'|'action', fidelity,
 *                            execution, disclaimer?, provenance?, roadmapNote?,
 *                            inputSchema?, honesty }
 * @param {Function} handler async (input) => raw result (gated automatically)
 */
function register(manifest, handler) {
  if (!manifest || !manifest.id) throw new Error('tool manifest needs an id');
  if (!FIDELITY.includes(manifest.fidelity)) {
    throw new Error(`tool ${manifest.id} registration failed: invalid/missing fidelity "${manifest.fidelity}"`);
  }
  if (!['evidence', 'action'].includes(manifest.kind)) {
    throw new Error(`tool ${manifest.id} needs kind 'evidence' or 'action'`);
  }
  _tools.set(manifest.id, { manifest, handler });
}

function has(id) { return _tools.has(id); }
function get(id) { return _tools.get(id); }

// A payload field counts as "present" only if it carries real content. Numbers
// (including 0 — e.g. a genuine DR score of 0) and booleans count; undefined,
// null, empty strings, empty arrays and empty objects do NOT.
function _present(v) {
  if (v === undefined || v === null) return false;
  if (typeof v === 'string') return v.trim() !== '';
  if (Array.isArray(v)) return v.length > 0;
  if (typeof v === 'object') return Object.keys(v).length > 0;
  return true;
}

// Returns the name of the first unmet requirement, or null when satisfied.
// `requires` = every field must be present (AND); `requiresAny` = at least one.
function _missingRequired(manifest, input) {
  for (const f of (manifest.requires || [])) {
    if (!_present(input[f])) return f;
  }
  const any = manifest.requiresAny || [];
  if (any.length && !any.some((f) => _present(input[f]))) return any.join('|');
  return null;
}

// An honest "no data" evidence envelope (same shape gateEvidence emits) used
// when a modality is invoked without the real input it needs. Built directly so
// it never trips gateEvidence's provenance check for `real` tools.
function _unavailable(manifest, input) {
  return {
    schema: 'evidence.v1',
    toolId: manifest.id,
    modality: manifest.modality,
    fidelity: manifest.fidelity,
    execution: manifest.execution || 'server',
    disease: (input && input.disease) || null,
    finding: `No ${manifest.modality} data provided`,
    value: null,
    score: null,
    confidence: null,
    findings: [],
    contributesTo: [],
    disclaimer: '',
    provenance: {},
    raw: {},
    status: 'unavailable',
  };
}

/** Registry projection = the tool list the agent sees. */
function list() {
  return [..._tools.values()].map(({ manifest }) => ({
    id: manifest.id,
    modality: manifest.modality,
    kind: manifest.kind,
    fidelity: manifest.fidelity,
    execution: manifest.execution || 'server',
    honesty: manifest.honesty || '',
    available: manifest.fidelity !== 'roadmap',
    inputSchema: manifest.inputSchema || null,
  }));
}

/** Invoke a tool by id; output is gated by fidelity. */
async function invoke(id, input) {
  const entry = _tools.get(id);
  if (!entry) throw new Error(`unknown tool: ${id}`);
  const { manifest, handler } = entry;

  // Roadmap tools never run a handler — they always return unavailable.
  if (manifest.fidelity === 'roadmap') {
    return gateEvidence({ status: 'unavailable', value: null }, manifest);
  }

  // HONESTY GUARD: an evidence modality invoked without its real input must
  // NOT fabricate a reading from handler defaults (e.g. Hb = 12). Return an
  // explicit "no data" instead, so the agent can recommend the test rather
  // than invent a result. Actions are exempt (they carry their own args).
  if (manifest.kind === 'evidence') {
    const missing = _missingRequired(manifest, input || {});
    if (missing) return _unavailable(manifest, input || {});
  }

  const raw = await handler(input || {});
  return manifest.kind === 'action'
    ? gateAction(raw, manifest)
    : gateEvidence(raw, manifest);
}

function reset() { _tools.clear(); } // for tests

module.exports = { register, has, get, list, invoke, reset, FidelityError };
