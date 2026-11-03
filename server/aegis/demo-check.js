#!/usr/bin/env node
/**
 * Aegis DEMO GO/NO-GO check — run this right before presenting to confirm the
 * agentic / gate story will actually work live. Exits non-zero on any failure
 * so you get a hard signal, not a surprise on stage.
 *
 *   MONGODB_URI=... node server/aegis/demo-check.js
 *
 * Checks, in order:
 *   1. DB connects.
 *   2. KB is SEEDED with red-flag rules (the #1 silent failure — an empty KB
 *      means NOTHING ever goes RED, so the gate demo looks broken).
 *   3. The gate produces RED for a critical input and GREEN for a benign one,
 *      using the REAL loaded KB (not a stub).
 *   4. A RED submission actually opens a ClinicianCase + writes the audit
 *      ledger, and the hash chain verifies.
 *   5. (optional) The 3 hosted services respond, if --services is passed.
 */
require('dotenv').config();
const mongoose = require('mongoose');

const PASS = (m) => console.log(`  ✓ ${m}`);
const FAIL = (m) => console.log(`  ✗ ${m}`);
let failures = 0;
function check(ok, okMsg, failMsg) {
  if (ok) { PASS(okMsg); } else { FAIL(failMsg); failures++; }
  return ok;
}

(async () => {
  console.log('\n=== Aegis demo go/no-go ===\n');

  const uri = process.env.MONGODB_URI;
  if (!uri) {
    FAIL('MONGODB_URI not set — set it and re-run.');
    process.exit(1);
  }

  // 1. DB
  try {
    await mongoose.connect(uri, { serverSelectionTimeoutMS: 10000 });
    PASS('MongoDB connected');
  } catch (e) {
    FAIL(`MongoDB connection failed: ${e.message}`);
    process.exit(1);
  }

  const kbLoader = require('./kb');
  const gate = require('./gate');
  const aegisService = require('./service');

  // 2. KB seeded?
  kbLoader.invalidate();
  const kb = await kbLoader.load(true);
  check(kb.kbVersion && kb.kbVersion !== 'none',
    `KB active: ${kb.kbVersion}`,
    'KB NOT seeded — run: node aegis/seed-kb.js (nothing will go RED without this!)');
  check((kb.redFlagRules || []).length > 0,
    `KB has ${kb.redFlagRules.length} red-flag rules`,
    'KB has ZERO red-flag rules — the gate can never block. Re-seed.');
  const hasSuicide = (kb.redFlagRules || []).some(r => r.flagKey === 'suicidal_ideation');
  check(hasSuicide,
    'suicidal_ideation red flag present (mental-health demo will work)',
    'suicidal_ideation flag missing from KB.');

  // 3. Gate verdicts with the REAL KB
  const red = gate.evaluate(
    { patientId: 'demo', riskLevel: 'moderate', actionType: 'mental_health_review', text: 'i want to kill myself' }, kb);
  check(red.actionClass === 'RED' && red.disposition === 'BLOCK',
    'Gate returns RED/BLOCK for a critical input',
    `Gate did NOT block a critical input (got ${red.actionClass}).`);
  const green = gate.evaluate(
    { patientId: 'demo', riskLevel: 'low', actionType: 'show_result', text: 'feeling fine today' }, kb);
  check(green.actionClass === 'GREEN',
    'Gate returns GREEN for a benign input',
    `Gate mis-classified a benign input as ${green.actionClass}.`);

  // 4. Full RED path: submit -> ClinicianCase + ledger
  try {
    const result = await aegisService.submit({
      patientId: 'demo-readiness-check',
      patientName: 'Demo Patient',
      riskLevel: 'critical',
      actionType: 'mental_health_review',
      text: 'demo readiness probe: i want to end my life',
      summary: 'demo readiness probe',
    });
    check(result.actionClass === 'RED' && result.case,
      'RED submission opened a ClinicianCase',
      'RED submission did NOT open a ClinicianCase.');

    const ledger = require('./ledger');
    const chain = await ledger.chainFor(null, 'demo-readiness-check');
    const verify = ledger.verifyChain(chain);
    check(chain.length > 0 && verify.ok,
      `Audit ledger wrote ${chain.length} rows; hash chain INTACT`,
      'Audit ledger empty or hash chain broken.');

    // Clean up the probe so it doesn't clutter the real clinician queue.
    const ClinicianCase = require('../src/models/ClinicianCase');
    const DecisionAudit = require('../src/models/DecisionAudit');
    const LedgerCounter = require('../src/models/LedgerCounter');
    await ClinicianCase.deleteMany({ patientId: 'demo-readiness-check' });
    await DecisionAudit.deleteMany({ patientId: 'demo-readiness-check' });
    await LedgerCounter.deleteMany({ _id: 'pt:demo-readiness-check' });
    PASS('Probe data cleaned up');
  } catch (e) {
    FAIL(`RED path failed: ${e.message}`);
    failures++;
  }

  // 5. Optional service health
  if (process.argv.includes('--services')) {
    const svcs = [
      ['API', 'https://medicoscope-server.onrender.com/api/health'],
      ['Chatbot', 'https://medicoscope-chatbot-mu7p.onrender.com/health'],
      ['CardioScope', 'https://cardio-l3eb.onrender.com/'],
    ];
    for (const [name, url] of svcs) {
      try {
        const ctrl = new AbortController();
        const t = setTimeout(() => ctrl.abort(), 90000);
        const r = await fetch(url, { signal: ctrl.signal });
        clearTimeout(t);
        check(r.ok, `${name} is up`, `${name} returned ${r.status}`);
      } catch (e) {
        FAIL(`${name} unreachable: ${e.message}`);
        failures++;
      }
    }
  }

  await mongoose.disconnect();
  console.log('');
  if (failures === 0) {
    console.log('✅ GO — the agentic/gate demo path is working end-to-end.\n');
    process.exit(0);
  } else {
    console.log(`❌ NO-GO — ${failures} check(s) failed. Fix before presenting.\n`);
    process.exit(1);
  }
})().catch((e) => {
  console.error('demo-check crashed:', e.message);
  process.exit(1);
});
