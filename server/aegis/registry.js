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

  const raw = await handler(input || {});
  return manifest.kind === 'action'
    ? gateAction(raw, manifest)
    : gateEvidence(raw, manifest);
}

function reset() { _tools.clear(); } // for tests

module.exports = { register, has, get, list, invoke, reset, FidelityError };
