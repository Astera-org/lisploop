/* Optional integration check using Chromium's debugging pipe; no npm packages. */
"use strict";
const {spawn} = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {pathToFileURL} = require("node:url");
const assert = require("node:assert/strict");
const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lisploop-visualizer-browser-"));
const chrome = spawn(process.env.CHROMIUM || "chromium", ["--headless", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage", "--no-first-run", "--remote-debugging-pipe", `--user-data-dir=${profile}`], {stdio:["ignore", "ignore", "pipe", "pipe", "pipe"]});
let serial = 0, buffer = "", diagnostics = "";
const waiting = new Map(), errors = [];
chrome.stderr.on("data", chunk => { diagnostics += chunk; });
chrome.on("error", error => { for (const request of waiting.values()) request.reject(error); });
chrome.on("exit", code => { for (const request of waiting.values()) request.reject(new Error(`Chromium exited ${code}: ${diagnostics.slice(-2000)}`)); });
chrome.stdio[4].on("data", chunk => {
  buffer += chunk.toString();
  let end;
  while ((end = buffer.indexOf("\0")) >= 0) {
    const message = JSON.parse(buffer.slice(0, end)); buffer = buffer.slice(end + 1);
    if (message.method === "Runtime.exceptionThrown") errors.push(message.params.exceptionDetails);
    if (!message.id) continue;
    const request = waiting.get(message.id); waiting.delete(message.id);
    if (message.error) request.reject(new Error(JSON.stringify(message.error))); else request.resolve(message.result);
  }
});
function send(method, params = {}, sessionId) {
  return new Promise((resolve, reject) => {
    const id = ++serial;
    const timer = setTimeout(() => { waiting.delete(id); reject(new Error(`Timed out: ${method}`)); }, 10000);
    waiting.set(id, {resolve: value => {clearTimeout(timer);resolve(value);}, reject: error => {clearTimeout(timer);reject(error);}});
    chrome.stdio[3].write(JSON.stringify({id,method,params,...(sessionId ? {sessionId} : {})}) + "\0");
  });
}
(async () => {
  try {
    const {targetId} = await send("Target.createTarget", {url:"about:blank"});
    const {sessionId} = await send("Target.attachToTarget", {targetId, flatten:true});
    await send("Runtime.enable", {}, sessionId);
    await send("Page.enable", {}, sessionId);
    const evaluate = async expression => {
      const result = await send("Runtime.evaluate", {expression, returnByValue:true, awaitPromise:true}, sessionId);
      if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
      return result.result.value;
    };
    await send("Page.navigate", {url:pathToFileURL(path.join(__dirname,"report.html")).href}, sessionId);
    for (let tries = 0; tries < 50; tries++) {
      if (await evaluate("document.documentElement.dataset.ready === 'true'")) break;
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    assert(await evaluate("document.documentElement.dataset.ready === 'true'"), "report did not render");
    const result = await evaluate(`(() => {
      const $ = id => document.getElementById(id);
      const check = (value, message) => { if (!value) throw new Error(message); };
      const change = (id, value) => { $(id).value = value; $(id).dispatchEvent(new Event('change')); };
      const bundle = JSON.parse($('report-data').textContent);
      check(bundle.version === 2, 'current report schema');
      let visited = 0;
      bundle.experiments.forEach((experiment, e) => {
        change('experiment', e);
        experiment.scopes.forEach((scope, s) => {
          change('scope', s); visited++;
          check($('scope-title').textContent === scope.title, 'scope switch');
          check($('probe-table').querySelectorAll('tbody tr').length === scope.frame.rows.length, 'probe table rows');
          check($('bucket-list').querySelectorAll('button').length === scope.buckets.length, 'bucket count');
          const first = scope.buckets.find(b => b.informative) || scope.buckets[0];
          const record = scope.records[first.members[0]];
          check($('bucket-detail').textContent.includes(record.headerBits + ' header bits + ' + record.bodyBits + ' body bits'), 'header/body bits');
          check($('bucket-detail').textContent.includes(record.packet), 'exact binary packet');
          check(!$('bucket-detail').textContent.includes('bytes v1'), 'no obsolete byte costs');
          check($('trajectory').hidden === !scope.pairs.length, 'trajectory visibility');
          if (scope.pairs.length) check($('transition-graph').querySelector('svg'), 'missing SVG');
          if (scope.kind === 'changed') check($('probe-table').querySelector('tr.failed'), 'changed transition failure');
          $('filter').value = 'no-such-expression'; $('filter').dispatchEvent(new Event('input'));
          check(!$('bucket-list').querySelector('button'), 'search filter');
          $('filter').value = ''; $('filter').dispatchEvent(new Event('input'));
          $('bucket-list').querySelector('button')?.click();
          $('bucket-detail').querySelectorAll('[data-record]')[1]?.click();
          check($('split-control').querySelectorAll('.split-card').length === 2, 'split control');
        });
      });
      change('experiment', 1); change('scope', 1);
      $('exact').checked = true; $('exact').dispatchEvent(new Event('change'));
      check($('probe-table').textContent.includes(String((1n<<256n)+1n)), 'exact adjacent integer');
      $('exact').checked = false; $('exact').dispatchEvent(new Event('change'));
      check($('probe-table').textContent.includes('N+1'), 'symbolic integer');
      $('split-control').querySelector('[data-control-scope="expanded"]').click();
      check($('scope-title').textContent.includes('Expanded'), 'inspect split control');
      return {visited, hash:location.hash};
    })()`);
    assert.equal(result.visited, 11);
    assert.equal(errors.length, 0, JSON.stringify(errors));
    console.log(`Desktop browser checked ${result.visited} scopes, filters, selections, and exact values.`);
  } finally {
    if (chrome.exitCode === null && chrome.signalCode === null) {
      const closed = new Promise(resolve => chrome.once("exit", resolve));
      chrome.kill(); await closed;
    }
    fs.rmSync(profile, {recursive:true,force:true});
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
