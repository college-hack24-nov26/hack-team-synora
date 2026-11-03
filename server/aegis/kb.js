/**
 * KB loader — reads the active knowledge-base version into memory (cached).
 * The gate/classifier consume `redFlagRules` from here so thresholds live in
 * data, not code, and every decision can be stamped with the kbVersion.
 */
const KbVersion = require('../src/models/KbVersion');
const KbRedFlag = require('../src/models/KbRedFlag');
const KbDiseaseThreshold = require('../src/models/KbDiseaseThreshold');
const KbSpecialtyMap = require('../src/models/KbSpecialtyMap');

const RULES_VERSION = 'rules-1';
let _cache = null;

async function load(force = false) {
  if (_cache && !force) return _cache;
  const active = await KbVersion.findOne({ active: true }).lean();
  if (!active) {
    // Fail-closed-friendly default: no KB => no red-flag data => gate still
    // works (risk-level rules apply) but logs that KB is missing.
    return { kbVersion: 'none', rulesVersion: RULES_VERSION, redFlagRules: [], thresholds: [], specialtyMap: {} };
  }
  const [redFlagRules, thresholds, specialties] = await Promise.all([
    KbRedFlag.find({ kbVersion: active.version }).lean(),
    KbDiseaseThreshold.find({ kbVersion: active.version }).lean(),
    KbSpecialtyMap.find({ kbVersion: active.version }).lean(),
  ]);
  const specialtyMap = {};
  for (const s of specialties) specialtyMap[s.disease] = s.specialties;
  _cache = { kbVersion: active.version, rulesVersion: RULES_VERSION, redFlagRules, thresholds, specialtyMap };
  return _cache;
}

function invalidate() { _cache = null; }

module.exports = { load, invalidate, RULES_VERSION };
