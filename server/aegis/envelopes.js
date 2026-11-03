/**
 * Uniform tool envelopes + the FIDELITY GATE — the honesty spine.
 *
 * Every diagnostic/sensing tool returns an EvidenceResult; every side-effecting
 * tool returns an ActionResult. The fidelity gate is applied to EVERY tool
 * output at the executor, regardless of the handler, so a heuristic can never
 * be narrated as a trained model and a roadmap stub can never emit a reading.
 *
 * Fidelity tiers and their confidence caps:
 *   real             -> full (must carry provenance.model or .source)
 *   partial          -> <= 0.65
 *   heuristic        -> <= 0.65
 *   fabricated_scale -> <= 0.45, disclaimer mandatory
 *   roadmap          -> value MUST be null, status 'unavailable'
 */
const FIDELITY = ['real', 'partial', 'heuristic', 'fabricated_scale', 'roadmap'];
const CONF_CAP = { real: 1.0, partial: 0.65, heuristic: 0.65, fabricated_scale: 0.45, roadmap: 0 };

class FidelityError extends Error {}

/**
 * Validate + normalize an EvidenceResult against its declared fidelity.
 * Throws FidelityError on a violation a stub/heuristic must not commit.
 */
function gateEvidence(result, manifest) {
  const fidelity = manifest.fidelity;
  if (!FIDELITY.includes(fidelity)) {
    throw new FidelityError(`tool ${manifest.id} has invalid/missing fidelity`);
  }

  const out = {
    schema: 'evidence.v1',
    toolId: manifest.id,
    modality: manifest.modality,
    fidelity,
    execution: manifest.execution || 'server',
    disease: result.disease ?? null,
    finding: result.finding ?? null,
    value: result.value ?? null,
    score: result.score ?? null,
    confidence: result.confidence ?? null,
    findings: result.findings || [],
    contributesTo: result.contributesTo || [],
    disclaimer: result.disclaimer || manifest.disclaimer || '',
    provenance: result.provenance || manifest.provenance || {},
    raw: result.raw || {},
    status: result.status || 'ok',
  };

  if (fidelity === 'roadmap') {
    // A stub cannot masquerade. Force unavailable + null value.
    if (out.value !== null || (result.status && result.status !== 'unavailable')) {
      throw new FidelityError(`roadmap tool ${manifest.id} attempted to emit a value`);
    }
    out.status = 'unavailable';
    out.confidence = null;
    out.roadmapNote = manifest.roadmapNote || 'Modality registered; model not yet integrated.';
    return out;
  }

  if (fidelity === 'real' && !out.provenance.model && !out.provenance.source) {
    throw new FidelityError(`real tool ${manifest.id} must declare provenance.model or .source`);
  }

  // Clamp confidence to the fidelity cap.
  const cap = CONF_CAP[fidelity];
  if (out.confidence != null && out.confidence > cap) out.confidence = cap;

  if (fidelity === 'fabricated_scale' && !out.disclaimer) {
    out.disclaimer = 'Estimated by a hand-tuned formula, not a validated model — screening signal only.';
  }
  return out;
}

/** Validate an ActionResult shape; idempotencyKey is mandatory. */
function gateAction(result, manifest) {
  if (!result || !result.idempotencyKey) {
    throw new FidelityError(`action tool ${manifest.id} must return an idempotencyKey`);
  }
  return {
    schema: 'action.v1',
    toolId: manifest.id,
    status: result.status || 'done',
    effects: result.effects || [],
    idempotencyKey: result.idempotencyKey,
    reversible: result.reversible ?? false,
    undo: result.undo ?? null,
    requiresConfirmation: result.requiresConfirmation ?? false,
  };
}

/** Risk fusion weights — roadmap contributes nothing; real outweighs heuristic. */
const FUSION_WEIGHT = { real: 1.0, partial: 0.6, heuristic: 0.55, fabricated_scale: 0.35, roadmap: 0 };

module.exports = { FIDELITY, CONF_CAP, FUSION_WEIGHT, gateEvidence, gateAction, FidelityError };
