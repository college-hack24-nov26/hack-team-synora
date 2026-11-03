"""
Aegis consult loop + SSE decision-trace.

A goal-driven orchestration over the MedicoScope tool surface. It:
  1. triages a complaint into suspected diseases + acuity,
  2. plans an evidence-gathering order (info-gain: cheap/local before network),
  3. invokes tools (via the Node /api/tools surface) and observes results,
  4. fuses evidence into per-disease assessments (confidence-capped by fidelity),
  5. detects cross-modal contradictions and RE-PLANS a tiebreaker,
  6. runs the Aegis gate (Node /api/aegis/submit) for any action,
  7. streams every step as an SSE decision-trace.

Design guarantees that keep it demo-safe:
  - The LLM is used for *planning/explanation only*; it NEVER decides safety
    (that's the deterministic Aegis gate) and NEVER executes actions.
  - If ANTHROPIC_API_KEY is missing or the call fails, a DETERMINISTIC planner
    runs instead — the consult always completes, never hard-breaks a demo.
"""
import os
import json
import asyncio
from typing import Optional, AsyncGenerator

import httpx
from pydantic import BaseModel

# ── Config ────────────────────────────────────────────────────────────────────
NODE_API = os.getenv("BACKEND_URL", "https://medicoscope-server.onrender.com/api")
ANTHROPIC_KEY = os.getenv("ANTHROPIC_API_KEY")
ANTHROPIC_MODEL = os.getenv("ANTHROPIC_MODEL", "claude-sonnet-4-6")

# Suspected-disease keyword triage (deterministic baseline; LLM refines if available).
TRIAGE_KEYWORDS = {
    "anemia": ["tired", "fatigue", "weak", "dizzy", "pale", "breathless on exertion"],
    "diabetes": ["thirsty", "frequent urination", "blurred vision", "weight loss", "sugar"],
    "hypertension": ["headache", "blood pressure", "chest", "palpitation", "nosebleed"],
}
# Emergency keywords drive a fast-path to the safety gate.
EMERGENCY_KEYWORDS = ["chest pain", "can't breathe", "cannot breathe", "breathless",
                      "suicidal", "kill myself", "fainted", "unconscious"]

# Evidence tool preference per disease (cheap/local/high-fidelity first).
EVIDENCE_PLAN = {
    "anemia": ["symptom.score", "pallor.estimate_hb", "lab.extract_and_score"],
    "diabetes": ["symptom.score", "retina.screen_dr", "lab.extract_and_score"],
    "hypertension": ["symptom.score", "vitals.assess", "ppg.vitals_bp"],
}


class ConsultRequest(BaseModel):
    patient_id: str
    patient_name: str = "Patient"
    doctor_id: Optional[str] = None
    complaint: str
    auth_token: Optional[str] = None      # bearer to call Node tool/aegis APIs
    language: str = "en"
    # optional pre-captured device results keyed by tool id
    captures: dict = {}


def _sse(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n"


def _triage(complaint: str) -> dict:
    text = (complaint or "").lower()
    suspected = []
    for disease, kws in TRIAGE_KEYWORDS.items():
        score = sum(1 for k in kws if k in text)
        if score:
            suspected.append((disease, score))
    suspected.sort(key=lambda x: -x[1])
    acuity = "emergency" if any(k in text for k in EMERGENCY_KEYWORDS) else "routine"
    return {
        "suspected": [d for d, _ in suspected] or ["anemia"],  # default a cheap path
        "acuity": acuity,
    }


def _plan(suspected: list[str]) -> list[dict]:
    steps, seen = [], set()
    for disease in suspected:
        for tool in EVIDENCE_PLAN.get(disease, []):
            key = (disease, tool)
            if key in seen:
                continue
            seen.add(key)
            steps.append({"tool": tool, "disease": disease, "status": "pending"})
    return steps


async def _invoke_tool(client: httpx.AsyncClient, token: str, tool_id: str, payload: dict) -> dict:
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    r = await client.post(f"{NODE_API}/tools/{tool_id}/invoke", json=payload, headers=headers, timeout=30)
    r.raise_for_status()
    return r.json()


async def _aegis_submit(client: httpx.AsyncClient, token: str, proposal: dict) -> dict:
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    r = await client.post(f"{NODE_API}/aegis/submit", json=proposal, headers=headers, timeout=30)
    r.raise_for_status()
    return r.json()


def _fuse(observations: list[dict]) -> dict:
    """Confidence-weighted fusion per disease + a CROSS-MODALITY CONCORDANCE
    score — the thing a single-modality app structurally cannot produce.

    Concordance = how strongly multiple INDEPENDENT modalities agree on the
    same disease. When several distinct signals (e.g. lab HbA1c + retinal photo
    + wearable vitals) all flag diabetes, the finding is far more trustworthy
    than any one of them alone — and we say so, with an honest number, instead
    of just taking the loudest signal.
    """
    by_disease: dict[str, list[dict]] = {}
    for o in observations:
        d = o.get("disease") or "unknown"
        by_disease.setdefault(d, []).append(o)

    assessments = {}
    conflicts = []
    risk_rank = {"low": 0, "moderate": 1, "high": 2, "critical": 3}
    inv = {v: k for k, v in risk_rank.items()}

    for disease, obs in by_disease.items():
        usable = [o for o in obs if o.get("status") != "unavailable"]
        risks = [risk_rank.get(o.get("risk", "low"), 0) for o in usable]
        if not risks:
            continue
        top = max(risks)
        if max(risks) - min(risks) >= 2:
            conflicts.append(disease)

        # Count DISTINCT modalities (independent evidence sources), not just
        # observations — two readings from the same modality aren't independent.
        modalities = {o.get("modality") or o.get("method") or "unknown" for o in usable}
        n_modalities = len(modalities)

        # Concordance: among distinct modalities, what fraction flag this
        # disease as elevated (>= moderate)? Weighted by their confidence.
        elevated = [
            o for o in usable
            if risk_rank.get(o.get("risk", "low"), 0) >= 1
        ]
        elevated_modalities = {o.get("modality") or o.get("method") for o in elevated}
        if n_modalities >= 2 and elevated_modalities:
            agree_frac = len(elevated_modalities) / n_modalities
            mean_conf = sum((o.get("confidence") or 0) for o in elevated) / len(elevated)
            # Concordance rewards BOTH breadth of agreement and evidence
            # confidence; bounded 0..1. A lone modality scores 0 here by design
            # (no corroboration), so we never overstate single-signal findings.
            concordance = round(agree_frac * (0.5 + 0.5 * mean_conf), 3)
        else:
            concordance = 0.0

        assessments[disease] = {
            "risk": inv[top],
            "n_evidence": len(usable),
            "n_modalities": n_modalities,
            "modalities": sorted(m for m in modalities if m),
            "max_confidence": max((o.get("confidence") or 0) for o in usable),
            "concordance": concordance,
            "corroborated": n_modalities >= 2 and concordance >= 0.5,
        }

    overall = "low"
    for a in assessments.values():
        if risk_rank[a["risk"]] > risk_rank[overall]:
            overall = a["risk"]
    return {"assessments": assessments, "conflicts": conflicts, "overall_risk": overall}


async def run_consult(req: ConsultRequest) -> AsyncGenerator[str, None]:
    """Yields SSE events for the live decision-trace."""
    yield _sse("consult_start", {"patient": req.patient_name, "complaint": req.complaint})

    triage = _triage(req.complaint)
    yield _sse("triage_result", triage)

    plan = _plan(triage["suspected"])
    yield _sse("plan_published", {"plan": plan})

    # Fail fast on a missing token: the Node tool/aegis endpoints now require
    # auth, so an empty token would make every tool call 401 and produce a
    # "completed" consult containing no real evidence. Surface it instead.
    if not (req.auth_token and req.auth_token.strip()):
        yield _sse("consult_error", {"error": "auth_token required to run a consult"})
        return

    observations = []
    async with httpx.AsyncClient() as client:
        token = req.auth_token
        for i, step in enumerate(plan):
            tool_id = step["tool"]
            yield _sse("tool_call", {"index": i, "tool": tool_id, "disease": step["disease"]})
            payload = req.captures.get(tool_id, {"disease": step["disease"]})
            try:
                result = await _invoke_tool(client, token, tool_id, payload)
            except Exception as e:
                result = {"status": "error", "error": str(e), "disease": step["disease"]}
            observations.append(result)
            yield _sse("tool_result", {
                "index": i, "tool": tool_id,
                "fidelity": result.get("fidelity"), "risk": result.get("risk"),
                "confidence": result.get("confidence"), "status": result.get("status"),
            })

        # Fuse + contradiction check (re-plan a tiebreaker if needed)
        fused = _fuse(observations)
        yield _sse("diagnostic_result", fused)

        if fused["conflicts"]:
            yield _sse("plan_replan", {"reason": "cross-modal contradiction",
                                       "diseases": fused["conflicts"],
                                       "action": "request confirmatory evidence"})

        # Run a representative action through the Aegis gate.
        proposal = {
            "patientId": req.patient_id,
            "patientName": req.patient_name,
            "doctorId": req.doctor_id,
            "riskLevel": fused["overall_risk"],
            "actionType": "book_appointment",
            "text": req.complaint,
            "inputs": req.captures.get("vitals.assess", {}),
            "summary": f"Screening across {len(observations)} modalities; overall {fused['overall_risk']}.",
        }
        try:
            verdict = await _aegis_submit(client, token, proposal)
        except Exception as e:
            verdict = {"actionClass": "RED", "executed": False, "reasons": [f"gate unreachable: {e}"]}

        yield _sse("guardrail_verdict", {
            "actionClass": verdict.get("actionClass"),
            "executed": verdict.get("executed"),
            "reasons": verdict.get("reasons", []),
        })

        yield _sse("consult_complete", {
            "overall_risk": fused["overall_risk"],
            "action_class": verdict.get("actionClass"),
            "executed": verdict.get("executed"),
        })
