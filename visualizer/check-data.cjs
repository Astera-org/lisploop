"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const bundle = JSON.parse(fs.readFileSync(path.join(__dirname, "data.json"), "utf8"));
const html = fs.readFileSync(path.join(__dirname, "report.html"), "utf8");
assert.deepEqual(JSON.parse(html.match(/<script id="report-data" type="application\/json">([\s\S]*?)<\/script>/)[1]), bundle);
assert(!html.includes("@@"));
assert.equal(bundle.version, 2);
assert.equal(bundle.experiments.length, 2);
const expected = [[50,15,13,13016], [35,83,71,52481]];
let scopes = 0;
for (const [i, experiment] of bundle.experiments.entries()) {
  const training = experiment.scopes.find(s => s.kind === "training");
  assert.deepEqual([training.bound, training.records.length, training.buckets.length, training.ledger.total], expected[i]);
  assert.equal(training.acquisition.total + training.orientation.total, [1150,711][i]);
  for (const scope of experiment.scopes) {
    scopes++;
    const rows = scope.frame.rows;
    assert.equal(new Set(rows.map(row => row.key)).size, rows.length);
    assert.equal(scope.evidence, "replayed-observations");
    assert.equal(scope.encodingVersion, 7);
    assert.equal(scope.tariffVersion, 7);
    assert.equal(scope.unit, "bits");
    assert.equal(scope.literals, "All domain literals");
    assert(!("costModel" in scope));
    for (const ledger of [scope.ledger, scope.acquisition, scope.orientation].filter(Boolean)) {
      assert.equal(ledger.total, ledger.categories.reduce((sum, c) => sum + c.work, 0));
    }
    const memberships = new Set();
    for (const bucket of scope.buckets) {
      assert.equal(bucket.values.length, rows.length);
      for (const id of bucket.members) {
        assert(!memberships.has(id)); memberships.add(id);
        const record = scope.records[id];
        assert.equal(record.status, "complete");
        assert.equal(record.type, bucket.type);
        assert.deepEqual(record.values, bucket.values);
      }
      const invariant = Boolean(scope.pairs.length) && scope.pairs.every(([a,b]) => bucket.values[a] === bucket.values[b]);
      const informative = invariant && Boolean(scope.anchors.length) && scope.anchors.some(a => bucket.values[a] !== bucket.values[scope.anchors[0]]);
      assert.equal(bucket.invariant, invariant); assert.equal(bucket.informative, informative);
    }
    assert.equal(memberships.size, scope.records.length);
    for (const record of scope.records) {
      assert.match(record.packet, /^[01]+$/);
      assert.equal(record.packet.length, record.size);
      assert.equal(record.size, record.headerBits + record.bodyBits);
      assert(record.size <= scope.bound);
      assert(!("bytes" in record));
    }
    for (const message of scope.messages.filter(m => m.coverage)) {
      assert.equal(message.encodingVersion, scope.encodingVersion);
      assert.equal(message.tariffVersion, scope.tariffVersion);
      assert.equal(message.coverage, scope.mode === "enumeration" ? "grammar" : "listed-expressions");
    }
    for (const row of rows) for (const value of row.known) assert.equal(typeof value, "string");
    if (["training", "fresh", "extended"].includes(scope.kind)) {
      const informative = scope.buckets.filter(b => b.informative);
      assert.equal(informative.length, 1);
      assert.deepEqual(informative[0].members.map(id => scope.records[id].expression).sort(), ["(a + b)", "(b + a)"]);
      for (const id of informative[0].members) {
        const record = scope.records[id];
        assert.equal(record.headerBits, [38,23][i]);
        assert.equal(record.bodyBits, 12);
        if (scope.kind === "training") assert.equal(record.runWork, [800,452][i]);
      }
    }
    if (scope.kind === "changed") {
      assert(scope.buckets.every(b => !b.invariant && b.counterexample));
    }
    if (scope.transitions) {
      assert.equal(scope.transitions.rows.length, scope.pairs.length);
      for (const [j, transition] of scope.transitions.rows.entries()) {
        const [before, after] = scope.pairs[j];
        assert.deepEqual(rows[before].known, transition.known);
        assert.deepEqual(rows[after].known, transition.allowed.values[0]);
        assert.equal(transition.allowed.values.length, 1);
      }
    }
  }
  const old = experiment.scopes.find(s => s.kind === "ambiguous"), expanded = experiment.scopes.find(s => s.kind === "expanded");
  const bucketOf = (s, expression) => s.buckets.find(b => b.members.some(id => s.records[id].expression === expression));
  assert.equal(bucketOf(old, "x"), bucketOf(old, "(x * x)"));
  assert.notEqual(bucketOf(expanded, "x"), bucketOf(expanded, "(x * x)"));
  assert.deepEqual(old.records.map(r => r.packet).sort(), expanded.records.map(r => r.packet).sort());
  const fresh = experiment.scopes.find(s => s.kind === "fresh");
  assert.equal(fresh.ledger.total, [1280,27421][i]);
  assert.equal(fresh.acquisition.total + fresh.orientation.total, [690,15788][i]);
  if (training.domain === "Integer") {
    const fresh = experiment.scopes.find(s => s.kind === "fresh");
    const n = 1n << 256n;
    assert.equal(fresh.frame.rows[0].known[0], String(n));
    assert(fresh.frame.rows.some(row => row.known[0] === String(n + 1n)));
    for (const record of fresh.records) assert.deepEqual(record.values, fresh.frame.rows.map(row => String(BigInt(row.known[0]) + BigInt(row.known[1]))));
  }
}
assert.equal(scopes, 11);
const extended = bundle.experiments[0].scopes.find(s => s.kind === "extended");
assert.equal(extended.bound, 54);
assert.equal(extended.records.length, 105);
assert.equal(extended.buckets.length, 25);
assert.equal(extended.ledger.total, 117996);
for (const record of bundle.experiments[0].scopes[0].records) assert(extended.records.some(r => r.packet === record.packet));
console.log(`Validated ${scopes} scopes: reference counts/work, exact values, pair links, buckets, split controls, and embedded report data.`);
