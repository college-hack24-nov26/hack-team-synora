/**
 * Memory service — episode lifecycle, long-term memory upkeep, and the
 * context-assembly that feeds the agent/chatbot. Pure helpers (assembleContext,
 * shouldReopen) are exported for testing; DB ops use the models.
 */
const Episode = require('../src/models/Episode');
const PatientMemory = require('../src/models/PatientMemory');

const REOPEN_WINDOW_DAYS = 30;
const TIMELINE_CAP = 40;

/** Pure: decide reopen-in-place vs new linked child vs fresh. */
function reopenDecision(latest, { primaryDisease, now }) {
  if (!latest) return 'fresh';
  const ageDays = (now - new Date(latest.updatedAt).getTime()) / 86400000;
  const sameFocus = latest.currentAssessment?.primaryDisease === primaryDisease;
  if (ageDays <= REOPEN_WINDOW_DAYS && sameFocus) return 'reopen';
  return 'child';
}

/** Pure: assemble a compact context block (~1.5-2k tokens) from memory parts. */
function assembleContext({ memory, currentEpisode, relatedEpisodes }) {
  const lines = [];
  if (memory) {
    const active = (memory.facts || []).filter(f => f.active);
    if (active.length) {
      lines.push('KNOWN PATIENT FACTS:');
      for (const f of active.slice(0, 15)) lines.push(`- ${f.category}/${f.key}: ${f.value}`);
    }
    if (memory.cachedSummary) { lines.push('', 'PRIOR SUMMARY:', memory.cachedSummary); }
    if ((memory.riskTimeline || []).length) {
      lines.push('', 'RISK TREND:');
      for (const p of memory.riskTimeline.slice(-6)) {
        lines.push(`- ${new Date(p.at).toISOString().slice(0, 10)} ${p.disease}: ${p.risk} (${p.score.toFixed?.(2) ?? p.score})`);
      }
    }
  }
  if (currentEpisode) {
    lines.push('', 'CURRENT EPISODE:');
    lines.push(`- complaint: ${currentEpisode.chiefComplaint || '(none)'}`);
    lines.push(`- status: ${currentEpisode.status}`);
    const ca = currentEpisode.currentAssessment || {};
    if (ca.summary) lines.push(`- assessment: ${ca.summary}`);
    for (const o of (currentEpisode.observations || [])) {
      lines.push(`  • ${o.modality} ${o.disease}: ${o.risk} (conf ${o.confidence}, ${o.fidelity})`);
    }
  }
  if (relatedEpisodes && relatedEpisodes.length) {
    lines.push('', 'RELATED PAST EPISODES:');
    for (const e of relatedEpisodes.slice(0, 5)) {
      lines.push(`- ${new Date(e.updatedAt).toISOString().slice(0, 10)}: ${e.currentAssessment?.summary || e.chiefComplaint || '(episode)'}`);
    }
  }
  return lines.join('\n');
}

// ── DB ops ───────────────────────────────────────────────────────────────────
async function startOrReopen({ patientId, patientName, doctorId, chiefComplaint, primaryDisease, kbVersion }) {
  const now = Date.now();
  const latest = await Episode.findOne({ patientId }).sort({ updatedAt: -1 }).lean();
  const decision = reopenDecision(latest, { primaryDisease, now });

  if (decision === 'reopen') {
    const ep = await Episode.findById(latest._id);
    ep.status = 'reopened';
    ep.reopenCount += 1;
    if (chiefComplaint) ep.chiefComplaint = chiefComplaint;
    await ep.save();
    return ep;
  }
  return Episode.create({
    patientId, patientName, doctorId: doctorId || null,
    chiefComplaint: chiefComplaint || '',
    parentEpisodeId: decision === 'child' && latest ? latest._id : null,
    kbVersionRef: kbVersion || '',
  });
}

async function addObservation(episodeId, obs) {
  const ep = await Episode.findById(episodeId);
  if (!ep) throw new Error('episode not found');
  ep.observations.push(obs);
  await ep.save();
  // mirror into long-term timeline
  await touchTimeline(ep.patientId, { disease: obs.disease, risk: obs.risk, score: obs.score });
  return ep;
}

async function setAssessment(episodeId, assessment) {
  return Episode.findByIdAndUpdate(episodeId, { $set: { currentAssessment: assessment } }, { new: true });
}

async function scheduleFollowUp(episodeId, dueAt) {
  return Episode.findByIdAndUpdate(episodeId, { $set: { followUpDueAt: dueAt, followUpDone: false } }, { new: true });
}

async function touchTimeline(patientId, point) {
  // Atomic append + cap in a single update so concurrent observations can't
  // clobber each other's timeline writes (the old read-modify-write raced).
  return PatientMemory.findOneAndUpdate(
    { patientId },
    {
      $setOnInsert: { patientId },
      $push: {
        riskTimeline: {
          $each: [{ disease: point.disease, risk: point.risk, score: point.score, at: new Date() }],
          $slice: -TIMELINE_CAP,
        },
      },
    },
    { upsert: true, new: true, setDefaultsOnInsert: true }
  );
}

async function upsertFact(patientId, fact) {
  // Try an atomic in-place update of the matching fact first (no read-modify-
  // write). arrayFilters targets the (category,key) pair if it already exists.
  const now = new Date();
  const updated = await PatientMemory.findOneAndUpdate(
    { patientId, 'facts.category': fact.category, 'facts.key': fact.key },
    { $set: { 'facts.$[f].value': fact.value, 'facts.$[f].updatedAt': now } },
    { new: true, arrayFilters: [{ 'f.category': fact.category, 'f.key': fact.key }] }
  );
  if (updated) return updated;

  // Not present yet — atomically push it (upserting the memory doc if needed).
  return PatientMemory.findOneAndUpdate(
    { patientId },
    {
      $setOnInsert: { patientId },
      $push: { facts: { ...fact, updatedAt: now } },
    },
    { upsert: true, new: true, setDefaultsOnInsert: true }
  );
}

async function getContext(patientId, { episodeId, query } = {}) {
  const memory = await PatientMemory.findOne({ patientId }).lean();
  const currentEpisode = episodeId
    ? await Episode.findById(episodeId).lean()
    : await Episode.findOne({ patientId, status: { $in: ['open', 'awaiting_input', 'reopened', 'escalated'] } }).sort({ updatedAt: -1 }).lean();
  let relatedEpisodes = [];
  if (query) {
    relatedEpisodes = await Episode.find({ patientId, $text: { $search: query } }).limit(5).lean().catch(() => []);
  }
  if (!relatedEpisodes.length) {
    relatedEpisodes = await Episode.find({ patientId }).sort({ updatedAt: -1 }).limit(5).lean();
  }
  return { text: assembleContext({ memory, currentEpisode, relatedEpisodes }), memory, currentEpisode, relatedEpisodes };
}

async function dueFollowUps(now = Date.now()) {
  return Episode.find({ followUpDueAt: { $lte: new Date(now) }, followUpDone: false }).lean();
}

module.exports = {
  reopenDecision, assembleContext,                 // pure
  startOrReopen, addObservation, setAssessment, scheduleFollowUp,
  touchTimeline, upsertFact, getContext, dueFollowUps,
  REOPEN_WINDOW_DAYS, TIMELINE_CAP,
};
