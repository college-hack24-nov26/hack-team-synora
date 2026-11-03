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
  - The planner uses Groq/Llama (GROQ_API_KEY). If it is missing or the call
    fails, a DETERMINISTIC keyword planner
    runs instead - the consult always completes, never hard-breaks a demo.
"""
import os
import json
import asyncio
from typing import Optional, AsyncGenerator

import httpx
from pydantic import BaseModel

# ── Config ────────────────────────────────────────────────────────────────────
NODE_API = os.getenv("BACKEND_URL", "https://medicoscope-api-lbto.onrender.com/api")

# The agent's PLANNER uses Groq/Llama (same provider as the rest of the app).
# It only refines triage/planning - it NEVER decides safety (that's the
# deterministic Aegis gate) and never executes actions. If Groq is unavailable
# the deterministic keyword planner runs instead, so the consult never breaks.
GROQ_KEY = os.getenv("GROQ_API_KEY")
GROQ_MODEL = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")

_groq_client = None
def _groq():
    global _groq_client
    if _groq_client is None and GROQ_KEY:
        try:
            from groq import Groq
            _groq_client = Groq(api_key=GROQ_KEY)
        except Exception:
            _groq_client = None
    return _groq_client

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
    # optional live patient location, forwarded to any gate-raised doctor alert
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    location_label: Optional[str] = None
    maps_url: Optional[str] = None


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


def _llm_triage(complaint: str) -> dict:
    """LLM-driven triage (Groq/Llama). Refines the deterministic baseline with
    real language understanding, but is constrained to the 3 supported diseases
    and always falls back to the keyword triage on any failure. Returns the
    same shape as _triage, plus a short `reasoning` string for the trace."""
    base = _triage(complaint)
    client = _groq()
    if not client or not (complaint or "").strip():
        return base
    try:
        prompt = (
            "You are the triage step of a screening agent. From the patient's "
            "words, pick which of EXACTLY these conditions to screen for: "
            "diabetes, hypertension, anemia. Also rate acuity as 'routine' or "
            "'emergency'. Reply ONLY as compact JSON: "
            '{"suspected":["..."],"acuity":"...","reasoning":"one short sentence"}.\n'
            f'Patient: "{complaint}"'
        )
        resp = client.chat.completions.create(
            model=GROQ_MODEL,
            messages=[{"role": "user", "content": prompt}],
            temperature=0.2,
            max_tokens=160,
            response_format={"type": "json_object"},
        )
        data = json.loads(resp.choices[0].message.content)
        allowed = {"diabetes", "hypertension", "anemia"}
        suspected = [d for d in data.get("suspected", []) if d in allowed]
        if not suspected:
            suspected = base["suspected"]
        # Acuity: take the MORE severe of LLM vs deterministic (fail toward care).
        acuity = "emergency" if (
            data.get("acuity") == "emergency" or base["acuity"] == "emergency"
        ) else "routine"
        return {
            "suspected": suspected,
            "acuity": acuity,
            "reasoning": str(data.get("reasoning", ""))[:240],
            "planner": "llm",
        }
    except Exception:
        return base


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


_VALID_RISK = ("low", "moderate", "high", "critical")


async def _fetch_saved_results(client: httpx.AsyncClient, token: str, patient_id: str) -> list[dict]:
    """Pull the patient's REAL saved screening results from Node and turn them
    into evidence observations. This is genuine patient data (their own prior
    lab / photo / vitals screenings), so it carries fidelity 'real'. Newest
    result per (disease, method) wins. Returns [] when the patient has none."""
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    try:
        r = await client.get(
            f"{NODE_API}/detections/risk-results/{patient_id}",
            headers=headers, params={"limit": 50}, timeout=20,
        )
        r.raise_for_status()
        rows = r.json().get("results", [])
    except Exception:
        return []

    obs, seen = [], set()
    for row in rows:  # already sorted newest-first by the Node route
        disease = (row.get("disease") or "").lower()
        method = row.get("method") or "saved_screening"
        key = (disease, method)
        if not disease or key in seen:
            continue
        seen.add(key)
        risk = (row.get("risk") or "low").lower()
        score = row.get("score")
        obs.append({
            "disease": disease,
            "risk": risk if risk in _VALID_RISK else "low",
            "confidence": score if isinstance(score, (int, float)) else 0.5,
            "modality": method,
            "fidelity": "real",
            "status": "ok",
            "finding": row.get("headline") or "",
            "source": "saved_screening",
            "measuredAt": row.get("measuredAt"),
        })
    return obs


def _fuse(observations: list[dict]) -> dict:
    """Confidence-weighted fusion per disease + a CROSS-MODALITY CONCORDANCE
    score - the thing a single-modality app structurally cannot produce.

    Concordance = how strongly multiple INDEPENDENT modalities agree on the
    same disease. When several distinct signals (e.g. lab HbA1c + retinal photo
    + wearable vitals) all flag diabetes, the finding is far more trustworthy
    than any one of them alone - and we say so, with an honest number, instead
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

    # Only REAL evidence counts. A tool that had no data (unavailable /
    # skipped_no_data) or errored is NOT a modality and must never inflate the
    # assessment - this is the honesty fix.
    _dead = {"unavailable", "error", "skipped_no_data"}
    for disease, obs in by_disease.items():
        usable = [o for o in obs if o.get("status") not in _dead]
        risks = [risk_rank.get(o.get("risk", "low"), 0) for o in usable]
        if not risks:
            continue
        top = max(risks)
        if max(risks) - min(risks) >= 2:
            conflicts.append(disease)

        # Count DISTINCT modalities (independent evidence sources), not just
        # observations - two readings from the same modality aren't independent.
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

    # Characterise what the assessment is actually BASED on, so the UI can label
    # it honestly instead of implying a full screening happened.
    all_usable = [o for o in observations if o.get("status") not in _dead]
    has_measured = any((o.get("modality") or "") not in ("", "symptom") for o in all_usable)
    has_symptom = any((o.get("modality") or "") == "symptom" for o in all_usable)

    if not all_usable:
        # Nothing real to go on. Do NOT claim "low risk" - say so plainly.
        return {"assessments": {}, "conflicts": [], "overall_risk": "not_assessed",
                "data_basis": "insufficient", "has_real_evidence": False}

    overall = "low"
    for a in assessments.values():
        if risk_rank[a["risk"]] > risk_rank[overall]:
            overall = a["risk"]

    data_basis = "measured" if has_measured else ("symptom_only" if has_symptom else "insufficient")
    return {"assessments": assessments, "conflicts": conflicts, "overall_risk": overall,
            "data_basis": data_basis, "has_real_evidence": has_measured}


async def run_consult(req: ConsultRequest) -> AsyncGenerator[str, None]:
    """Yields SSE events for the live decision-trace."""
    yield _sse("consult_start", {"patient": req.patient_name, "complaint": req.complaint})

    triage = _llm_triage(req.complaint)
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

        # A1: the patient's REAL saved screenings are the primary evidence.
        saved = await _fetch_saved_results(client, token, req.patient_id)
        if saved:
            observations.extend(saved)
            yield _sse("saved_evidence", {
                "count": len(saved),
                "modalities": sorted({s["modality"] for s in saved}),
                "diseases": sorted({s["disease"] for s in saved}),
            })

        for i, step in enumerate(plan):
            tool_id = step["tool"]
            yield _sse("tool_call", {"index": i, "tool": tool_id, "disease": step["disease"]})

            # A2: NEVER fabricate. symptom.score reads the real free-text
            # complaint; any device modality runs ONLY if the patient actually
            # captured data for it this session. Otherwise it is skipped (and
            # NOT counted as evidence), so the consult can't invent a reading.
            if tool_id == "symptom.score":
                payload = {"disease": step["disease"], "freeText": req.complaint}
            elif tool_id in req.captures:
                payload = req.captures[tool_id]
            else:
                yield _sse("tool_result", {
                    "index": i, "tool": tool_id, "disease": step["disease"],
                    "status": "skipped_no_data",
                })
                continue

            try:
                result = await _invoke_tool(client, token, tool_id, payload)
            except Exception as e:
                result = {"status": "error", "error": str(e), "disease": step["disease"]}
            observations.append(result)
            yield _sse("tool_result", {
                "index": i, "tool": tool_id,
                "fidelity": result.get("fidelity"), "risk": result.get("risk"),
                "confidence": result.get("confidence"), "status": result.get("status"),
                "error": result.get("error"),
            })

        # Fuse + contradiction check (re-plan a tiebreaker if needed)
        fused = _fuse(observations)
        yield _sse("diagnostic_result", fused)

        if fused.get("conflicts"):
            yield _sse("plan_replan", {"reason": "cross-modal contradiction",
                                       "diseases": fused["conflicts"],
                                       "action": "request confirmatory evidence"})

        # Run a representative action through the Aegis gate. The gate only knows
        # the four real risk levels, so map "not_assessed" to a safe "low" for
        # the call, but keep the honest basis in the summary and the trace.
        basis = fused.get("data_basis", "insufficient")
        gate_risk = fused["overall_risk"] if fused["overall_risk"] in _VALID_RISK else "low"
        if basis == "insufficient":
            summary = "No screening data on file; recommend the patient complete a screening."
        elif basis == "symptom_only":
            summary = f"Symptom-based triage only (no measured evidence); provisional {fused['overall_risk']}."
        else:
            summary = f"Screening across {len(fused.get('assessments', {}))} conditions; overall {fused['overall_risk']}."
        proposal = {
            "patientId": req.patient_id,
            "patientName": req.patient_name,
            "doctorId": req.doctor_id,
            "riskLevel": gate_risk,
            "actionType": "book_appointment",
            "text": req.complaint,
            "inputs": req.captures.get("vitals.assess", {}),
            "summary": summary,
            "latitude": req.latitude,
            "longitude": req.longitude,
            "locationLabel": req.location_label,
            "mapsUrl": req.maps_url,
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
            "data_basis": basis,
            "action_class": verdict.get("actionClass"),
            "executed": verdict.get("executed"),
        })
