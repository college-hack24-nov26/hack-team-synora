import os
import json
import uuid
import random
import asyncio
from datetime import datetime, timedelta
from typing import Optional

import httpx
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from dotenv import load_dotenv
from groq import Groq
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langchain_core.messages import HumanMessage, AIMessage
from langchain_groq import ChatGroq

load_dotenv()

app = FastAPI(title="HearMe Chatbot", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Clients ──────────────────────────────────────────────────────────────────
groq_client = Groq(api_key=os.getenv("GROQ_API_KEY"))

llm = ChatGroq(
    model="llama-3.3-70b-versatile",
    api_key=os.getenv("GROQ_API_KEY"),
    temperature=0.7,
    max_tokens=1024,
)

llm_streaming = ChatGroq(
    model="llama-3.1-8b-instant",
    api_key=os.getenv("GROQ_API_KEY"),
    temperature=0.7,
    max_tokens=1024,
    streaming=True,
)

# ── Config ─────────────────────────────────────────────────────────────────
BACKEND_URL = os.getenv("BACKEND_URL", "https://medicoscope-server.onrender.com/api")

# ── In-memory stores ────────────────────────────────────────────────────────
session_histories: dict[str, list] = {}

# ── Vitals in-memory stores ─────────────────────────────────────────────────
vitals_sessions: dict[str, dict] = {}   # session_id -> session data
vitals_alerts: dict[str, list] = {}     # doctor_id / patient_id -> [alerts]

# ── Medical Knowledge Base ──────────────────────────────────────────────────
MEDICAL_DATA = {
    "skin_diseases": {
        "eczema": {"symptoms": ["itchy skin", "red patches", "dry skin", "inflammation"], "severity": "moderate", "advice": "Use moisturizers, avoid triggers, consider topical corticosteroids"},
        "psoriasis": {"symptoms": ["scaly patches", "red skin", "itching", "thick silvery scales"], "severity": "moderate", "advice": "Phototherapy, topical treatments, systemic medications for severe cases"},
        "acne": {"symptoms": ["pimples", "blackheads", "whiteheads", "oily skin"], "severity": "mild", "advice": "Gentle cleansing, benzoyl peroxide, retinoids, consult dermatologist if severe"},
        "dermatitis": {"symptoms": ["skin rash", "blisters", "itching", "swelling"], "severity": "mild-moderate", "advice": "Identify and avoid allergens, use antihistamines and topical steroids"},
    },
    "chest_diseases": {
        "asthma": {"symptoms": ["wheezing", "shortness of breath", "chest tightness", "coughing"], "severity": "moderate-severe", "advice": "Use inhaler, avoid triggers, seek emergency care for severe attacks"},
        "pneumonia": {"symptoms": ["fever", "cough with phlegm", "chest pain", "difficulty breathing"], "severity": "severe", "advice": "Seek immediate medical care, antibiotics may be needed, rest and fluids"},
        "bronchitis": {"symptoms": ["persistent cough", "mucus production", "fatigue", "chest discomfort"], "severity": "moderate", "advice": "Rest, fluids, humidifier, see doctor if symptoms last >3 weeks"},
        "copd": {"symptoms": ["chronic cough", "shortness of breath", "wheezing", "frequent respiratory infections"], "severity": "severe", "advice": "Quit smoking, bronchodilators, pulmonary rehabilitation, see pulmonologist"},
    },
    "brain_diseases": {
        "migraine": {"symptoms": ["severe headache", "nausea", "sensitivity to light", "visual disturbances"], "severity": "moderate", "advice": "Rest in dark room, OTC pain relievers, preventive medications for frequent migraines"},
        "tension_headache": {"symptoms": ["dull aching head pain", "tightness around forehead", "tenderness in scalp"], "severity": "mild", "advice": "Stress management, OTC pain relievers, adequate sleep, regular exercise"},
        "concussion": {"symptoms": ["headache", "confusion", "dizziness", "nausea", "memory problems"], "severity": "severe", "advice": "Seek immediate medical attention, rest, avoid screens, gradual return to activities"},
        "meningitis": {"symptoms": ["severe headache", "stiff neck", "high fever", "sensitivity to light", "nausea"], "severity": "critical", "advice": "EMERGENCY: Seek immediate medical care. This is potentially life-threatening."},
    },
}

# ── Language Instructions ───────────────────────────────────────────────────
LANGUAGE_INSTRUCTIONS = {
    "en": "Respond in English.",
    "hi": "Respond in Hindi (हिंदी में उत्तर दें).",
    "ta": "Respond in Tamil (தமிழில் பதிலளிக்கவும்).",
    "te": "Respond in Telugu (తెలుగులో సమాధానం ఇవ్వండి).",
    "mr": "Respond in Marathi (मराठीत उत्तर द्या).",
    "bn": "Respond in Bengali (বাংলায় উত্তর দিন).",
    "kn": "Respond in Kannada (ಕನ್ನಡದಲ್ಲಿ ಉತ್ತರಿಸಿ).",
}

# ── Pydantic Models ─────────────────────────────────────────────────────────

class ChatRequest(BaseModel):
    message: str
    session_id: str = "default"
    language: str = "en"
    medical_context: Optional[str] = None
    patient_profile: Optional[str] = None

class RewardRedeemRequest(BaseModel):
    reward_type: str
    language: str = "en"


# ── Helper Functions ────────────────────────────────────────────────────────

def get_session_history(session_id: str) -> list:
    if session_id not in session_histories:
        session_histories[session_id] = []
    return session_histories[session_id]


def _build_system_prompt(
    lang_instruction: str,
    medical_json: str,
    medical_context: Optional[str],
    patient_profile: Optional[str],
) -> str:
    """Build the full system prompt with all available patient context."""
    system_template = f"""You are a highly capable, conversational medical assistant for MedicoScope.
Your role is to help users understand their symptoms, provide general health guidance, and advise when to see a doctor.
You have FULL access to all the patient's data from the MedicoScope app, including their vitals readings (BP, heart rate, SpO2),
AI detection scan results (skin, chest X-ray, brain MRI), MindSpace mental health check-in transcripts,
medical conditions, medications, and health history.

IMPORTANT RULES:
1. Always be empathetic and supportive.
2. Never diagnose — only provide general information.
3. For severe symptoms, always advise seeking immediate medical attention.
4. When the patient asks about their health data (BP, vitals, scans, MindSpace sessions), refer to the PATIENT DATA below.
5. You can correlate data across different sources — e.g., if vitals show high BP and MindSpace shows stress, mention the connection.
6. If the patient mentions something they told MindSpace, you should know about it from their MindSpace transcripts.
7. {lang_instruction}

MEDICAL KNOWLEDGE BASE:
{medical_json}
"""
    if patient_profile:
        escaped_profile = patient_profile.replace("{", "{{").replace("}", "}}")
        system_template += f"\n\nPATIENT PROFILE:\n{escaped_profile}"

    if medical_context:
        escaped_context = medical_context.replace("{", "{{").replace("}", "}}")
        system_template += f"\n\nPATIENT DATA (from MedicoScope app — use this to answer patient questions):\n{escaped_context}"

    return system_template


# ── Routes ──────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok", "service": "hearme-chatbot"}


# ── Chat (non-streaming) ───────────────────────────────────────────────────

@app.post("/chat")
async def chat(req: ChatRequest):
    try:
        history = get_session_history(req.session_id)
        lang_instruction = LANGUAGE_INSTRUCTIONS.get(req.language, LANGUAGE_INSTRUCTIONS["en"])

        # Escape curly braces in JSON so LangChain doesn't treat them as template vars
        medical_json = json.dumps(MEDICAL_DATA, indent=2).replace("{", "{{").replace("}", "}}")

        system_template = _build_system_prompt(lang_instruction, medical_json, req.medical_context, req.patient_profile)

        prompt = ChatPromptTemplate.from_messages([
            ("system", system_template),
            MessagesPlaceholder(variable_name="history"),
            ("human", "{input}"),
        ])

        chain = prompt | llm
        response = chain.invoke({"input": req.message, "history": history})

        history.append(HumanMessage(content=req.message))
        history.append(AIMessage(content=response.content))

        # Keep history manageable
        if len(history) > 20:
            session_histories[req.session_id] = history[-20:]

        return {"response": response.content, "session_id": req.session_id}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Chat (streaming SSE) ───────────────────────────────────────────────────

@app.post("/chat/stream")
async def chat_stream(req: ChatRequest):
    async def event_generator():
        try:
            history = get_session_history(req.session_id)
            lang_instruction = LANGUAGE_INSTRUCTIONS.get(req.language, LANGUAGE_INSTRUCTIONS["en"])

            medical_json = json.dumps(MEDICAL_DATA, indent=2).replace("{", "{{").replace("}", "}}")

            system_template = _build_system_prompt(lang_instruction, medical_json, req.medical_context, req.patient_profile)

            prompt = ChatPromptTemplate.from_messages([
                ("system", system_template),
                MessagesPlaceholder(variable_name="history"),
                ("human", "{input}"),
            ])

            chain = prompt | llm_streaming
            full_response = ""

            async for chunk in chain.astream({"input": req.message, "history": history}):
                token = chunk.content
                if token:
                    full_response += token
                    yield f"data: {json.dumps({'token': token})}\n\n"

            history.append(HumanMessage(content=req.message))
            history.append(AIMessage(content=full_response))

            if len(history) > 20:
                session_histories[req.session_id] = history[-20:]

            yield "data: [DONE]\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")


# ── Mental Health Analysis ──────────────────────────────────────────────────

@app.post("/mental-health/analyze")
async def analyze_mental_health(
    audio: UploadFile = File(...),
    patient_id: str = Form(...),
    patient_name: str = Form(...),
    doctor_id: Optional[str] = Form(None),
    language: str = Form("en"),
):
    try:
        # Save audio temporarily
        audio_bytes = await audio.read()
        temp_path = f"/tmp/mental_health_{uuid.uuid4()}.m4a"
        with open(temp_path, "wb") as f:
            f.write(audio_bytes)

        # Transcribe with Groq Whisper
        with open(temp_path, "rb") as audio_file:
            transcription = groq_client.audio.transcriptions.create(
                file=("audio.m4a", audio_file),
                model="whisper-large-v3-turbo",
                language=language if language != "en" else None,
            )

        transcript = transcription.text
        lang_instruction = LANGUAGE_INSTRUCTIONS.get(language, LANGUAGE_INSTRUCTIONS["en"])

        # Clean up temp file
        try:
            os.remove(temp_path)
        except:
            pass

        # User-facing empathetic response
        user_prompt = f"""You are a compassionate mental health companion for MedicoScope MindSpace.
A user just shared their feelings through a voice check-in. Here's their transcription:

"{transcript}"

Provide a warm, empathetic, and detailed response that:
1. Acknowledges and validates their specific feelings with genuine empathy
2. Reflects back what they shared to show you truly listened
3. Offers 2-3 practical and personalized coping strategies relevant to what they described
4. Ends with an encouraging, hopeful note

Write 2-3 short paragraphs (8-12 sentences total). Be conversational and caring, like a supportive friend who also understands wellness. {lang_instruction}"""

        user_response = llm.invoke(user_prompt)

        # Doctor-facing clinical report
        doctor_report = None
        urgency = "low"
        if doctor_id:
            doctor_prompt = f"""You are a clinical mental health analyst for HearMe.
Analyze this patient's mental health check-in transcription and provide a clinical summary for their doctor.

Patient: {patient_name}
Transcription: "{transcript}"

Provide:
1. Brief clinical summary (2-3 sentences)
2. Key concerns identified
3. Recommended follow-up actions
4. Urgency level: low, moderate, or high

Format as a professional clinical note. Respond in English."""

            doctor_response = llm.invoke(doctor_prompt)
            doctor_report = doctor_response.content

            # Determine urgency from keywords
            report_lower = doctor_report.lower()
            if any(w in report_lower for w in ["high urgency", "urgent", "crisis", "suicidal", "self-harm", "emergency"]):
                urgency = "high"
            elif any(w in report_lower for w in ["moderate urgency", "moderate", "concerning", "anxiety", "depression"]):
                urgency = "moderate"

            # Save notification to Node.js backend (MongoDB)
            try:
                async with httpx.AsyncClient(timeout=10) as client:
                    await client.post(
                        f"{BACKEND_URL}/mental-health/notifications",
                        json={
                            "doctorId": doctor_id,
                            "patientId": patient_id,
                            "patientName": patient_name,
                            "clinicalReport": doctor_report,
                            "urgency": urgency,
                            "transcript": transcript,
                        },
                    )
            except Exception as notif_err:
                print(f"Warning: Failed to save notification to backend: {notif_err}")

        return {
            "user_message": user_response.content,
            "transcript": transcript,
            "doctor_report": doctor_report,
            "urgency": urgency,
            "coins_earned": 10,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Rewards ─────────────────────────────────────────────────────────────────

@app.post("/rewards/redeem")
async def redeem_reward(req: RewardRedeemRequest):
    lang_instruction = LANGUAGE_INSTRUCTIONS.get(req.language, LANGUAGE_INSTRUCTIONS["en"])

    # Map Flutter reward types to prompt keys
    type_map = {
        "meditation": "guided_meditation",
        "wellness_report": "weekly_wellness",
        "health_tips": "premium_health_tips",
        "guided_meditation": "guided_meditation",
        "weekly_wellness": "weekly_wellness",
        "premium_health_tips": "premium_health_tips",
    }

    prompts = {
        "guided_meditation": f"""Create a personalized guided meditation script (5-7 minutes).
Include breathing exercises, body scan, and visualization.
Make it calming and suitable for stress relief. {lang_instruction}""",
        "weekly_wellness": f"""Generate a comprehensive weekly wellness report with:
1. Mental health tips for the week
2. Nutrition recommendations
3. Exercise suggestions
4. Sleep hygiene tips
5. Mindfulness exercises
Make it actionable and motivating. {lang_instruction}""",
        "premium_health_tips": f"""Provide 10 premium health tips covering:
1. Physical health
2. Mental well-being
3. Nutrition
4. Sleep quality
5. Stress management
Make each tip detailed and evidence-based. {lang_instruction}""",
    }

    mapped_type = type_map.get(req.reward_type)
    prompt = prompts.get(mapped_type) if mapped_type else None
    if not prompt:
        raise HTTPException(status_code=400, detail="Invalid reward type")

    try:
        response = llm.invoke(prompt)
        return {"content": response.content, "reward_type": req.reward_type}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Vitals Monitoring ───────────────────────────────────────────────────────

VITALS_SCENARIOS = ["resting", "mild_activity", "post_exercise", "sleeping", "stressed"]

# Normal baseline ranges
VITALS_BASELINES = {
    "resting":       {"hr": (65, 80),  "sys": (110, 125), "dia": (70, 80),  "spo2": (96, 99)},
    "mild_activity": {"hr": (80, 100), "sys": (115, 135), "dia": (72, 85),  "spo2": (95, 98)},
    "post_exercise": {"hr": (100,130), "sys": (125, 145), "dia": (75, 88),  "spo2": (94, 98)},
    "sleeping":      {"hr": (55, 70),  "sys": (100, 115), "dia": (60, 75),  "spo2": (95, 99)},
    "stressed":      {"hr": (85, 110), "sys": (125, 145), "dia": (80, 92),  "spo2": (95, 98)},
}

ALERT_THRESHOLDS = {
    "heart_rate_high":  130,
    "heart_rate_low":   50,
    "systolic_high":    150,
    "systolic_low":     85,
    "spo2_low":         92,
}


def _generate_vitals(session: dict) -> list[dict]:
    """Generate 1-3 simulated data points for a tick."""
    scenario = session["scenario"]
    baseline = VITALS_BASELINES[scenario]
    tick = session["tick_counter"]
    points = []

    count = random.randint(1, 3)
    for i in range(count):
        tick += 1
        # Add some drift and noise
        drift = session.get("drift", 0)
        # Occasionally shift drift to simulate natural fluctuation
        if random.random() < 0.08:
            drift = random.uniform(-8, 8)
            session["drift"] = drift

        hr = random.uniform(*baseline["hr"]) + drift + random.gauss(0, 3)
        sys_ = random.uniform(*baseline["sys"]) + drift * 0.5 + random.gauss(0, 4)
        dia = random.uniform(*baseline["dia"]) + drift * 0.3 + random.gauss(0, 2)
        spo2 = random.uniform(*baseline["spo2"]) + random.gauss(0, 0.5)

        # Clamp to physiologically possible values
        hr = max(35, min(200, hr))
        sys_ = max(70, min(220, sys_))
        dia = max(40, min(130, dia))
        spo2 = max(70, min(100, spo2))

        points.append({
            "tick": tick,
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "heart_rate": round(hr, 1),
            "systolic": round(sys_, 1),
            "diastolic": round(dia, 1),
            "spo2": round(spo2, 1),
        })

    session["tick_counter"] = tick
    return points


def _check_alerts(session: dict, points: list[dict]) -> list[dict]:
    """Check data points against thresholds and generate alerts."""
    alerts = []
    for pt in points:
        ts = pt["timestamp"]

        if pt["heart_rate"] > ALERT_THRESHOLDS["heart_rate_high"]:
            alerts.append(_make_alert(session, "tachycardia", "warning",
                f"Heart rate elevated: {pt['heart_rate']} bpm",
                "heart_rate", pt["heart_rate"], ALERT_THRESHOLDS["heart_rate_high"], ts))
        elif pt["heart_rate"] < ALERT_THRESHOLDS["heart_rate_low"]:
            alerts.append(_make_alert(session, "bradycardia", "critical",
                f"Heart rate dangerously low: {pt['heart_rate']} bpm",
                "heart_rate", pt["heart_rate"], ALERT_THRESHOLDS["heart_rate_low"], ts))

        if pt["systolic"] > ALERT_THRESHOLDS["systolic_high"]:
            alerts.append(_make_alert(session, "hypertension", "warning",
                f"Blood pressure high: {pt['systolic']}/{pt['diastolic']} mmHg",
                "systolic", pt["systolic"], ALERT_THRESHOLDS["systolic_high"], ts))
        elif pt["systolic"] < ALERT_THRESHOLDS["systolic_low"]:
            alerts.append(_make_alert(session, "hypotension", "warning",
                f"Blood pressure low: {pt['systolic']}/{pt['diastolic']} mmHg",
                "systolic", pt["systolic"], ALERT_THRESHOLDS["systolic_low"], ts))

        if pt["spo2"] < ALERT_THRESHOLDS["spo2_low"]:
            sev = "critical" if pt["spo2"] < 88 else "warning"
            alerts.append(_make_alert(session, "hypoxia", sev,
                f"SpO2 low: {pt['spo2']}%",
                "spo2", pt["spo2"], ALERT_THRESHOLDS["spo2_low"], ts))

    return alerts


def _make_alert(session: dict, alert_type: str, severity: str,
                message: str, vital: str, current: float, predicted: float,
                timestamp: str) -> dict:
    return {
        "id": str(uuid.uuid4()),
        "type": alert_type,
        "severity": severity,
        "message": message,
        "vital": vital,
        "current_value": current,
        "predicted_value": predicted,
        "timestamp": timestamp,
        "location": session.get("location", ""),
        "latitude": session.get("latitude", 0),
        "longitude": session.get("longitude", 0),
        "maps_url": f"https://www.google.com/maps?q={session.get('latitude',0)},{session.get('longitude',0)}",
        "emergency_contact_name": session.get("emergency_contact_name", ""),
        "emergency_contact_phone": session.get("emergency_contact_phone", ""),
        "patient_id": session.get("patient_id", ""),
        "patient_name": session.get("patient_name", ""),
        "doctor_id": session.get("doctor_id", ""),
        "created_at": datetime.utcnow().isoformat(),
        "read": False,
    }


class VitalsStartRequest(BaseModel):
    patient_id: str
    patient_name: str
    doctor_id: str = ""
    emergency_contact_name: str = ""
    emergency_contact_phone: str = ""
    location: str = "Unknown"
    latitude: float = 0.0
    longitude: float = 0.0


class VitalsTickRequest(BaseModel):
    session_id: str


@app.post("/vitals/start")
async def vitals_start(req: VitalsStartRequest):
    session_id = str(uuid.uuid4())
    scenario = random.choice(VITALS_SCENARIOS)

    session = {
        "session_id": session_id,
        "scenario": scenario,
        "patient_id": req.patient_id,
        "patient_name": req.patient_name,
        "doctor_id": req.doctor_id,
        "emergency_contact_name": req.emergency_contact_name,
        "emergency_contact_phone": req.emergency_contact_phone,
        "location": req.location,
        "latitude": req.latitude,
        "longitude": req.longitude,
        "tick_counter": 0,
        "drift": 0,
        "created_at": datetime.utcnow().isoformat(),
    }

    vitals_sessions[session_id] = session
    return {"session_id": session_id, "scenario": scenario}


@app.post("/vitals/tick")
async def vitals_tick(req: VitalsTickRequest):
    session = vitals_sessions.get(req.session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found or expired")

    points = _generate_vitals(session)
    alerts = _check_alerts(session, points)

    # Store alerts per doctor and patient for later querying
    if alerts:
        doctor_id = session.get("doctor_id", "")
        patient_id = session.get("patient_id", "")
        if doctor_id:
            vitals_alerts.setdefault(f"doc_{doctor_id}", []).extend(alerts)
        if patient_id:
            vitals_alerts.setdefault(f"pat_{patient_id}", []).extend(alerts)

    return {"data_points": points, "alerts": alerts}


@app.delete("/vitals/session/{session_id}")
async def vitals_stop(session_id: str):
    vitals_sessions.pop(session_id, None)
    return {"status": "stopped"}


@app.get("/vitals/alerts/doctor/{doctor_id}")
async def vitals_doctor_alerts(doctor_id: str):
    alerts = vitals_alerts.get(f"doc_{doctor_id}", [])
    return {"alerts": alerts}


@app.get("/vitals/alerts/patient/{patient_id}")
async def vitals_patient_alerts(patient_id: str):
    alerts = vitals_alerts.get(f"pat_{patient_id}", [])
    return {"alerts": alerts}


@app.put("/vitals/alerts/{alert_id}/read")
async def vitals_mark_alert_read(alert_id: str):
    # Mark alert as read across all alert lists
    for key in vitals_alerts:
        for alert in vitals_alerts[key]:
            if alert.get("id") == alert_id:
                alert["read"] = True
    return {"status": "ok"}


@app.delete("/vitals/alerts/{alert_id}")
async def vitals_delete_alert(alert_id: str):
    """Delete a vitals alert by ID."""
    for key in list(vitals_alerts.keys()):
        vitals_alerts[key] = [a for a in vitals_alerts[key] if a.get("id") != alert_id]
    return {"status": "deleted"}


# ── Run ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
