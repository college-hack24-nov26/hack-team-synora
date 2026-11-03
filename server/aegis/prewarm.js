#!/usr/bin/env node
/**
 * Aegis demo pre-warm — keeps the three Render free-tier services hot so they
 * never cold-start (~50s spin-up) in the middle of a live demo.
 *
 * Pings all three health endpoints on an interval. Run it from the demo
 * machine starting ~10 min before you present, and leave it running.
 *
 *   node server/aegis/prewarm.js              # loop, ping every 4 min
 *   node server/aegis/prewarm.js --once       # single ping (CI / manual check)
 *   node server/aegis/prewarm.js --interval 180   # custom seconds
 *
 * Exit code of --once is non-zero if any service is unhealthy — useful as a
 * pre-demo go/no-go gate.
 */

const SERVICES = [
  { name: 'API server',  url: 'https://medicoscope-server.onrender.com/api/health' },
  { name: 'Chatbot',     url: 'https://medicoscope-chatbot-mu7p.onrender.com/health' },
  { name: 'CardioScope', url: 'https://cardio-l3eb.onrender.com/' },
];

const args = process.argv.slice(2);
const once = args.includes('--once');
const intervalIdx = args.indexOf('--interval');
const intervalSec = intervalIdx >= 0 ? Number(args[intervalIdx + 1]) : 240;

function stamp() {
  return new Date().toISOString().replace('T', ' ').slice(0, 19);
}

async function ping(svc) {
  const started = Date.now();
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 90000); // observed cold start: API ~40s, chatbot ~10s, cardio ~40s
    const res = await fetch(svc.url, { signal: ctrl.signal });
    clearTimeout(timer);
    const ms = Date.now() - started;
    const ok = res.ok;
    const cold = ms > 8000; // heuristic: slow response => was spinning up
    console.log(
      `[${stamp()}] ${ok ? '✓' : '✗'} ${svc.name.padEnd(12)} ${res.status} ${ms}ms` +
      (cold ? '  (was cold — now warm)' : '')
    );
    return ok;
  } catch (err) {
    const ms = Date.now() - started;
    console.log(`[${stamp()}] ✗ ${svc.name.padEnd(12)} ERROR ${ms}ms  ${err.name === 'AbortError' ? 'timeout' : err.message}`);
    return false;
  }
}

async function round() {
  const results = await Promise.all(SERVICES.map(ping));
  return results.every(Boolean);
}

(async () => {
  if (once) {
    const allOk = await round();
    console.log(allOk ? '\nAll services healthy — clear to demo.' : '\nSome services unhealthy — wait and re-run before demoing.');
    process.exit(allOk ? 0 : 1);
  }

  console.log(`Aegis pre-warm running. Pinging ${SERVICES.length} services every ${intervalSec}s. Ctrl+C to stop.\n`);
  await round();
  setInterval(round, intervalSec * 1000);
})();
