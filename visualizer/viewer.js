/* Plain DOM + inline SVG. Domain integers stay as strings, or exact BigInts. */
"use strict";
(() => {
  const $ = id => document.getElementById(id);
  const esc = value => String(value).replace(/[&<>"']/g, c => ({"&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;"}[c]));
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  const number = n => n.toLocaleString("en-US");
  const N = 1n << 256n;
  const palette = ["#e2efe7", "#f7ebd4", "#e3edf8", "#eee5f2", "#f8e4dc", "#e4eecc", "#daeff0"];
  let bundle, experiment, scope, selectedBucket, selectedRecord;

  function shortInteger(text) {
    if ($("exact").checked || !/^-?\d{18,}$/.test(text)) return text;
    const value = BigInt(text);
    for (const multiplier of [1n, -1n, 2n, -2n]) {
      const delta = value - multiplier * N;
      if (delta >= -3n && delta <= 3n) {
        const base = ({"1":"N", "-1":"−N", "2":"2N", "-2":"−2N"})[String(multiplier)];
        return base + (delta === 0n ? "" : delta > 0n ? `+${delta}` : `−${-delta}`);
      }
    }
    if (value === N * N) return "N²";
    if (value === (N + 1n) ** 2n) return "(N+1)²";
    return `${text.slice(0, 7)}…${text.slice(-5)} (${text.replace("-", "").length} digits)`;
  }
  function display(value) {
    if (value === undefined) return "unknown";
    if (Array.isArray(value)) return `(${value.map(display).join(", ")})`;
    if (typeof value === "boolean") return value ? "true" : "false";
    return shortInteger(String(value));
  }
  function exact(value) {
    return Array.isArray(value) ? `(${value.map(exact).join(", ")})` : String(value);
  }
  function valueMarkup(value) {
    return `<span title="${esc(exact(value))}">${esc(display(value))}</span>`;
  }
  function color(value) {
    let hash = 0;
    for (const char of JSON.stringify(value) || "unknown") hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
    return palette[hash % palette.length];
  }
  function badge(bucket, currentScope = scope) {
    if (!currentScope.pairs.length) return '<span class="badge">Observed agreement</span>';
    if (bucket.informative) return '<span class="badge">Informative invariant</span>';
    if (bucket.invariant) return '<span class="badge neutral">Invariant · no anchor variation</span>';
    return '<span class="badge bad">Fails an observed pair</span>';
  }
  function pickedRecord() {
    return scope.records.find(record => record.id === selectedRecord);
  }
  function pickedBucket() {
    return scope.buckets.find(bucket => bucket.id === selectedBucket);
  }
  function setScope(index) {
    scope = experiment.scopes[index];
    $("scope").value = String(index);
    const preferred = scope.buckets.find(bucket => bucket.informative) || scope.buckets.find(bucket =>
      bucket.members.some(id => scope.records[id].expression === "(a + b)")) || scope.buckets[0];
    selectedBucket = preferred?.id;
    selectedRecord = preferred?.members[0];
    $("filter").value = "";
    $("classification").value = "all";
    renderScope();
    updateHash();
  }
  function setExperiment(index, scopeIndex = 0) {
    experiment = bundle.experiments[index];
    $("experiment").value = String(index);
    $("scope").innerHTML = experiment.scopes.map((s, i) => `<option value="${i}">${esc(s.title)}</option>`).join("");
    setScope(scopeIndex);
  }
  function updateHash() {
    const params = new URLSearchParams({experiment: experiment.id, scope: scope.kind});
    if (selectedRecord !== undefined) params.set("record", String(selectedRecord));
    // file:// reports can be opened directly; no server or fetch is involved.
    history.replaceState(null, "", `#${params}`);
  }
  function renderScope() {
    $("scope-id").textContent = scope.id;
    $("scope-title").textContent = scope.title;
    $("evidence").textContent = scope.evidence;
    const descriptions = {
      training: "Enumerate h over the declared inputs. Look for equal outputs before and after every transition, with variation across the selected starting states.",
      fresh: "Decode and replay the two discovered sums on six fresh transition pairs. Only these listed expressions are checked here.",
      changed: "Change the transition's b increment. Replaying the same two sums supplies counterexamples to invariance under the new transition.",
      extended: "Extend the field description bound to include all 105 single-application expressions. The additional syntax does not change the informative invariant bucket.",
      ambiguous: "Enumerate on x in {0,1}. Matching output vectors can conceal disagreement on unseen inputs.",
      expanded: "Replay every retained expression on expanded inputs. Bucket identities are local to this new scope; the original observations are preserved."
    };
    $("scope-description").textContent = descriptions[scope.kind] || "A read-only snapshot of a scoped observation job.";
    const invariantCount = scope.buckets.filter(bucket => bucket.informative).length;
    $("metrics").innerHTML = [
      [scope.frame.rows.length, "ordered input probes"], [scope.records.length, "retained expressions"],
      [scope.buckets.length, "typed output buckets"], [invariantCount, "informative invariant buckets"],
      [`${scope.bound} ${scope.unit}`, `${scope.mode === "enumeration" ? "grammar" : "replay"} description bound`]
    ].map(([value, label]) => `<div class="metric"><strong>${esc(value)}</strong><span>${esc(label)}</span></div>`).join("");
    if (scope.pending || scope.records.some(record => record.status !== "complete")) {
      $("scope-description").innerHTML += '<div class="notice">This snapshot contains unfinished or failed work. Only complete output vectors supply bucket evidence. See unbucketed records below.</div>';
    }
    renderBucketList();
    renderSelection();
    renderSplit();
    renderAccounting();
    $("original-section").hidden = !scope.transitions;
    if (scope.transitions) $("original-table").innerHTML = frameTable(scope.transitions, false);
  }
  function renderBucketList() {
    const query = $("filter").value.toLowerCase().trim();
    const classification = $("classification").value;
    const buckets = [...scope.buckets].sort((a, b) => Number(b.informative) - Number(a.informative) || a.id - b.id)
      .filter(bucket => (!query || bucket.members.some(id => scope.records[id].expression.toLowerCase().includes(query))) &&
        (classification === "all" || classification === "informative" && bucket.informative ||
          classification === "constant" && bucket.invariant && !bucket.informative ||
          classification === "failing" && scope.pairs.length && !bucket.invariant));
    $("bucket-count").textContent = `${buckets.length} / ${scope.buckets.length} buckets shown`;
    $("bucket-list").innerHTML = buckets.map(bucket => {
      const expressions = bucket.members.slice(0, 4).map(id => scope.records[id].expression).join(", ");
      return `<button class="bucket-item" type="button" data-bucket="${bucket.id}" aria-pressed="${bucket.id === selectedBucket}">
        <span class="quiet">Bucket ${bucket.id + 1} · ${esc(bucket.type)} · ${bucket.members.length} syntax forms</span>
        <strong>${esc(expressions)}${bucket.members.length > 4 ? ", …" : ""}</strong>${badge(bucket)}</button>`;
    }).join("") || '<p class="empty">No buckets match these filters.</p>';
    $("bucket-list").querySelectorAll("[data-bucket]").forEach(button => button.addEventListener("click", () => {
      selectedBucket = Number(button.dataset.bucket);
      selectedRecord = pickedBucket().members[0];
      renderBucketList(); renderSelection(); updateHash();
    }));
  }
  function renderSelection() {
    const bucket = pickedBucket(), record = pickedRecord();
    if (!bucket || !record) {
      $("bucket-detail").innerHTML = '<p class="empty">No complete output bucket is available yet.</p>';
    } else {
      const outputs = bucket.values.map((value, i) => `<span class="value-chip" style="background:${color(value)}" title="${esc(scope.frame.rows[i].key)}: ${esc(exact(value))}">${esc(display(value))}</span>`).join("");
      $("bucket-detail").innerHTML = `<div class="heading-row"><h3>Bucket ${bucket.id + 1}</h3>${badge(bucket)}</div>
        <p class="quiet">${esc(bucket.type)} · ${bucket.members.length} retained syntax forms · scope ${esc(scope.id)}</p>
        <div class="member-buttons">${bucket.members.map(id => `<button type="button" data-record="${id}" aria-pressed="${id === selectedRecord}">${esc(scope.records[id].expression)}</button>`).join("")}</div>
        <h4>Ordered output vector</h4><p class="quiet">One cell per frame row, in row order. Hover for the occurrence key and full exact value.</p><div class="vector">${outputs}</div>
        ${bucket.counterexample ? `<div class="notice"><strong>First failing pair</strong><pre>${esc(bucket.counterexample)}</pre></div>` : ""}
        <h4>Selected expression: <code>${esc(record.expression)}</code></h4>
        <div class="facts"><div class="fact"><span>Description length</span>${record.size} bits</div><div class="fact"><span>Completed execution on this scope's probes</span>${number(record.runWork)} work units</div><div class="fact"><span>Standalone packet</span>${record.headerBits} header bits + ${record.bodyBits} body bits</div></div>
        <details><summary>Typed Lisp AST &amp; exact binary packet</summary><pre>${esc(record.ast)}</pre><pre>${esc(record.packet)}</pre></details>`;
      $("bucket-detail").querySelectorAll("[data-record]").forEach(button => button.addEventListener("click", () => {
        selectedRecord = Number(button.dataset.record); renderSelection(); updateHash();
      }));
    }
    const unbucketed = scope.records.filter(r => r.status !== "complete").concat(scope.pending ? [scope.pending] : []);
    if (unbucketed.length) $("bucket-detail").innerHTML += `<details><summary>Unbucketed records (${unbucketed.length})</summary>${unbucketed.map(r => `<pre>${esc(JSON.stringify(r, null, 2))}</pre>`).join("")}</details>`;
    const inputs = scope.frame.schema.inputs.map(input => `${input.name} [ID ${input.id}]: ${input.type}`).join("; ");
    $("schema").textContent = `Inputs: ${inputs || "none"}. Target: ${scope.frame.schema.target}. Selected observable: ${record?.expression || "none"}.`;
    $("probe-table").innerHTML = frameTable(scope.frame, true);
    renderGraph();
  }
  function allowedMarkup(allowed) {
    return allowed.kind === "finite" ? `{${allowed.values.map(valueMarkup).join(", ")}}` :
      `<details><summary>Executable predicate</summary><pre>${esc(allowed.predicate)}</pre></details>`;
  }
  function frameTable(frame, probes) {
    const record = probes ? pickedRecord() : null;
    const failed = new Set();
    if (record) scope.pairs.forEach(([before, after]) => { if (!same(record.values[before], record.values[after])) { failed.add(before); failed.add(after); } });
    const seen = new Set();
    const names = frame.schema.inputs.map(input => `<th scope="col">${esc(input.name)} · ${esc(input.type)}</th>`).join("");
    return `<table><thead><tr><th scope="col">Occurrence key · metadata</th>${names}<th scope="col">Allowed · ${esc(frame.schema.target)}</th>${probes ? '<th scope="col">Selected h output</th>' : ""}</tr></thead><tbody>${frame.rows.map((row, i) => {
      const duplicate = seen.has(JSON.stringify(row.known)); seen.add(JSON.stringify(row.known));
      const anchor = probes && scope.anchors.includes(i);
      const pair = probes ? scope.pairs.findIndex(indices => indices.includes(i)) : -1;
      return `<tr class="${failed.has(i) ? "failed" : ""} ${anchor ? "anchor" : ""}"><td class="key">${esc(row.key)}${pair >= 0 ? `<span class="row-note">pair ${pair + 1} · ${scope.pairs[pair][0] === i ? "before" : "after"}</span>` : ""}${anchor ? '<span class="row-note">selected start anchor</span>' : ""}${duplicate ? '<span class="row-note">repeated input values · separate occurrence</span>' : ""}</td>${row.known.map(value => `<td class="value">${valueMarkup(value)}</td>`).join("")}<td class="value">${allowedMarkup(row.allowed)}</td>${probes ? `<td class="value">${valueMarkup(record?.values[i])}</td>` : ""}</tr>`;
    }).join("")}</tbody></table>`;
  }
  function renderGraph() {
    $("trajectory").hidden = !scope.pairs.length;
    if (!scope.pairs.length) return;
    const rows = scope.frame.rows, record = pickedRecord();
    const groups = [];
    scope.pairs.forEach(pair => {
      const previous = groups.at(-1)?.at(-1);
      if (!previous || scope.anchors.includes(pair[0]) || !same(rows[previous[1]].known, rows[pair[0]].known)) groups.push([]);
      groups.at(-1).push(pair);
    });
    $("trajectory-description").textContent = `Each arrow is a recorded transition; node labels show the selected h output. Red arrows mark unequal before/after outputs. Repeated states remain separate occurrences in the table below.${scope.domain === "Integer" ? " N = 2^256; hover for exact decimal values." : " Arithmetic is modulo 5."}`;
    const width = Math.max(600, ...groups.map(group => (group.length + 1) * 170 + 20));
    const height = groups.length * 150;
    let svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="graph-title graph-desc"><title id="graph-title">Recorded transitions with outputs of ${esc(record?.expression || "no selected expression")}</title><desc id="graph-desc">${scope.pairs.length} before/after pairs. Equal values share a fill color; unequal pairs have red arrows. Exact rows are available in the frame table.</desc><defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="#667e77"/></marker><marker id="arrow-bad" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="#a53f39"/></marker></defs>`;
    groups.forEach((group, g) => {
      const top = g * 150;
      svg += `<text x="8" y="${top + 19}" fill="#5e7377" font-size="11">Trajectory ${g + 1} · ${group.length} recorded ${group.length === 1 ? "step" : "steps"}</text>`;
      group.forEach(([before, after], i) => {
        const checked = record?.status === "complete" && record.values[before] !== undefined && record.values[after] !== undefined;
        const bad = checked && !same(record.values[before], record.values[after]);
        const x = 8 + i * 170;
        svg += `<path d="M${x + 145},${top + 80} H${x + 163}" stroke="${bad ? "#a53f39" : "#667e77"}" stroke-width="2" marker-end="url(#${bad ? "arrow-bad" : "arrow"})"/><text x="${x + 150}" y="${top + 63}" font-size="11" fill="${bad ? "#a53f39" : "#667e77"}">${!checked ? "?" : bad ? "≠" : "="}</text>`;
      });
      const nodes = group.map(pair => pair[0]).concat([group.at(-1)[1]]);
      nodes.forEach((rowIndex, i) => {
        const row = rows[rowIndex], value = record?.values[rowIndex], x = 8 + i * 170;
        const state = display(row.known);
        const stateLabel = state.length > 21 ? `${state.slice(0, 18)}…` : state;
        const h = display(value), outputLabel = h.length > 16 ? `${h.slice(0, 13)}…` : h;
        svg += `<g><title>${esc(row.key)}\nInputs: ${esc(exact(row.known))}\nh = ${esc(exact(value))}</title><rect x="${x}" y="${top + 36}" width="145" height="87" rx="6" fill="${color(value)}" stroke="${scope.anchors.includes(rowIndex) ? "#13675c" : "#bdcec4"}" stroke-width="${scope.anchors.includes(rowIndex) ? 2 : 1}"/><text x="${x + 12}" y="${top + 58}" font-size="10" fill="#5e7377">${i === 0 ? "START / " : ""}t=${i}</text><text x="${x + 12}" y="${top + 82}" font-size="12" fill="#183135">${esc(stateLabel)}</text><text x="${x + 12}" y="${top + 107}" font-size="13" font-weight="600" fill="#183135">h = ${esc(outputLabel)}</text></g>`;
      });
    });
    $("transition-graph").innerHTML = svg + "</svg>";
  }
  function renderSplit() {
    const old = experiment.scopes.find(s => s.kind === "ambiguous"), fresh = experiment.scopes.find(s => s.kind === "expanded");
    $("agreement").hidden = !old || !fresh;
    if (!old || !fresh) return;
    $("split-control").innerHTML = `<div class="split-layout">${[old, fresh].map(s => {
      const x = s.records.find(r => r.expression === "x"), square = s.records.find(r => r.expression === "(x * x)");
      const xb = s.buckets.find(b => b.members.includes(x?.id)), sb = s.buckets.find(b => b.members.includes(square?.id));
      if (!x || !square || !xb || !sb) return '<p class="empty">Control expressions are unavailable in this snapshot.</p>';
      return `<div class="split-card"><h4>${esc(s.title)}</h4><span class="badge ${xb.id === sb.id ? "neutral" : ""}">${xb.id === sb.id ? "Same bucket" : "Separate buckets"}</span><p class="quiet">${s.records.length} expressions retained · ${s.buckets.length} buckets<br>Scope ${esc(s.id)}</p><div class="scroll"><table><thead><tr><th>x input</th><th>h = x</th><th>h = x * x</th></tr></thead><tbody>${s.frame.rows.map((row, i) => `<tr class="${same(x.values[i], square.values[i]) ? "" : "failed"}"><td class="value">${valueMarkup(row.known[0])}</td><td class="value">${valueMarkup(x.values[i])}</td><td class="value">${valueMarkup(square.values[i])}</td></tr>`).join("")}</tbody></table></div><button type="button" data-control-scope="${esc(s.kind)}">Inspect this scope</button></div>`;
    }).join("")}</div><p class="quiet">Integer labels use N = 2^256. Hover for full exact decimals, or enable “Show full integers”. Bucket numbers from different scopes are independent.</p>`;
    $("split-control").querySelectorAll("[data-control-scope]").forEach(button => button.addEventListener("click", () => {
      setScope(experiment.scopes.findIndex(s => s.kind === button.dataset.controlScope));
    }));
  }
  function renderAccounting() {
    const facts = [["Domain", scope.domain], ["Known input IDs", scope.frame.schema.inputs.map(i => i.id).join(", ")],
      ["Candidate literals", scope.literals], ["Operators", scope.operators.join(", ")],
      ["Description encoding", `Binary v${scope.encodingVersion} · bits`],
      ["Work tariff / equality", `Structural v${scope.tariffVersion} / ${scope.equality}`],
      ["Language / simulator version", `${scope.languageVersion} / ${scope.simulatorVersion}`],
      ["Coverage", `${scope.mode === "enumeration" ? "Grammar" : "Listed expressions only"}; completed bound ${scope.completedBound} ${scope.unit}`],
      ["Saved phase", scope.phase], ["Pair links / anchors", `${scope.pairs.length} / ${scope.anchors.length}`]];
    $("scope-facts").innerHTML = `<div class="facts">${facts.map(([label, value]) => `<div class="fact"><span>${esc(label)}</span>${esc(value)}</div>`).join("")}</div>`;
    $("ledgers").innerHTML = [[scope.ledger, scope.mode === "enumeration" ? "Discovery work" : "Replay work"], [scope.acquisition, "Original transition generation"], [scope.orientation, "Probe orientation · no transition rerun"]].filter(([ledger]) => ledger).map(([ledger, title]) => `<div><h4>${esc(title)}</h4><table><thead><tr><th>Category</th><th>Work</th></tr></thead><tbody>${ledger.categories.map(c => `<tr><td>${esc(c.name)}</td><td>${number(c.work)}</td></tr>`).join("")}<tr><th>Total</th><td><strong>${number(ledger.total)}</strong></td></tr></tbody></table></div>`).join("");
    $("messages").innerHTML = `<pre>${esc(JSON.stringify(scope.messages, null, 2))}</pre>`;
    $("raw").textContent = JSON.stringify(scope, null, 2);
  }
  try {
    bundle = JSON.parse($("report-data").textContent);
    if (bundle.version !== 2) throw new Error("Regenerate this report with the current visualizer and kernel.");
    $("experiment").innerHTML = bundle.experiments.map((e, i) => `<option value="${i}">${esc(e.title)}</option>`).join("");
    $("experiment").addEventListener("change", () => setExperiment(Number($("experiment").value)));
    $("scope").addEventListener("change", () => setScope(Number($("scope").value)));
    $("filter").addEventListener("input", renderBucketList);
    $("classification").addEventListener("change", renderBucketList);
    $("exact").addEventListener("change", renderScope);
    $("download").addEventListener("click", () => {
      const url = URL.createObjectURL(new Blob([JSON.stringify(scope, null, 2)], {type:"application/json"}));
      const a = document.createElement("a"); a.href = url; a.download = `${experiment.id}-${scope.kind}.json`; a.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    });
    const params = new URLSearchParams(location.hash.slice(1));
    const e = Math.max(0, bundle.experiments.findIndex(candidate => candidate.id === params.get("experiment")));
    const s = Math.max(0, bundle.experiments[e].scopes.findIndex(candidate => candidate.kind === params.get("scope")));
    const recordId = params.has("record") ? Number(params.get("record")) : undefined;
    setExperiment(e, s);
    const bucket = scope.buckets.find(candidate => candidate.members.includes(recordId));
    if (bucket) { selectedBucket = bucket.id; selectedRecord = recordId; renderBucketList(); renderSelection(); updateHash(); }
    $("controls").hidden = false; $("inspector").hidden = false;
    document.documentElement.dataset.ready = "true";
  } catch (error) {
    $("error").hidden = false; $("error").textContent = `The report could not be rendered: ${error.message}`;
    console.error(error);
  }
})();
