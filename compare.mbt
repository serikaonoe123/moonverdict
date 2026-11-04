///|
fn failure(v : String) -> Bool {
  ["WA", "PE", "TLE", "MLE", "RE"].contains(v)
}

///|
fn row(s : Snapshot, id : String) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for r in s.runs {
    if r.solution == id {
      result[r.test_id] = r.verdict
    }
  }
  result
}

///|
fn all_pass(s : Snapshot, results : Map[String, String]) -> Bool {
  s.finished && s.tests.all(t => results.get(t.id) == Some("AC"))
}

///|
pub fn compare(before : Snapshot, after : Snapshot) -> Report raise InputError {
  validate(before)
  validate(after)
  require(
    before.problem == after.problem,
    "different problems cannot be compared",
  )
  let findings : Array[Finding] = []
  for sol in before.solutions {
    let previous = row(before, sol.id)
    if !before.finished ||
      before.tests.any(t => {
        match previous.get(t.id) {
          Some(v) => v != "AC" && !failure(v)
          None => true
        }
      }) {
      findings.push({
        code: "BASELINE_INCOMPLETE",
        solution: sol.id,
        evidence: [],
        message: "Baseline does not contain a complete final result matrix.",
      })
    }
  }
  let context_equal = before.semantics == after.semantics &&
    before.environment == after.environment &&
    before.checker == after.checker
  if !context_equal {
    findings.push({
      code: "CONTEXT_CHANGED",
      solution: "",
      evidence: [],
      message: "Semantics, checker or environment changed; observations do not establish a cause.",
    })
  }
  for sol in after.solutions {
    let current = row(after, sol.id)
    let missing = after.tests
      .filter(t => {
        match current.get(t.id) {
          None => true
          Some(v) => v != "AC" && !failure(v)
        }
      })
      .map(t => t.id)
    if !after.finished || missing.length() > 0 {
      findings.push({
        code: "INCOMPLETE",
        solution: sol.id,
        evidence: missing,
        message: "Not all required runs are final; no all-pass claim can be made.",
      })
    }
    // Matching requires a unique digest on both sides, never just a reused name.
    let old_matches = before.solutions.filter(x => x.digest == sol.digest)
    let new_matches = after.solutions.filter(x => x.digest == sol.digest)
    if old_matches.length() != 1 || new_matches.length() != 1 {
      findings.push({
        code: "IDENTITY_UNRESOLVED",
        solution: sol.id,
        evidence: [],
        message: "Solution has no unique content match across snapshots.",
      })
      continue
    }
    let old = old_matches[0]
    let previous = row(before, old.id)
    if old.expected != sol.expected {
      findings.push({
        code: "EXPECTATION_CHANGED",
        solution: sol.id,
        evidence: [],
        message: "Expected outcome changed; review the comparison premise.",
      })
    }
    let witnesses = before.tests
      .filter(t => {
        match previous.get(t.id) {
          Some(v) => failure(v)
          None => false
        }
      })
      .map(t => t.id)
    if witnesses.length() > 0 && all_pass(after, current) {
      let confirmed = context_equal &&
        old.expected == "fail" &&
        sol.expected == "fail"
      findings.push({
        code: if confirmed {
          "KNOWN_FAILURE_LOST"
        } else {
          "FAIL_TO_PASS_REVIEW"
        },
        solution: sol.id,
        evidence: witnesses,
        message: "Previously observed failures now pass all required tests; artifact bindings are supplied, not independently verified.",
      })
    }
    if sol.expected == "pass" {
      let rejected = after.tests
        .filter(t => {
          match current.get(t.id) {
            Some(v) => failure(v)
            None => false
          }
        })
        .map(t => t.id)
      if rejected.length() > 0 {
        findings.push({
          code: "REFERENCE_REJECTED",
          solution: sol.id,
          evidence: rejected,
          message: "A declared reference solution failed; review the solution, data and judge.",
        })
      }
    }
  }
  {
    before_revision: before.revision,
    after_revision: after.revision,
    findings,
    evidence_level: "supplied-metadata-unverified",
  }
}

///|
pub fn report_json(report : Report) -> String {
  @json.to_json(report).stringify(indent=2)
}

///|
fn html_escape(value : String) -> String {
  value
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="'", new="&#39;")
}

///|
pub fn report_html(report : Report) -> String {
  let body = html_escape(report_json(report))
  "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>MoonVerdict</title><style>body{font:16px system-ui;max-width:1000px;margin:3rem auto;padding:1rem;background:#f5f7fb;color:#182438}pre{white-space:pre-wrap;background:white;padding:2rem;border-radius:12px}h1{color:#245d8a}</style><h1>MoonVerdict comparison</h1><p>Prototype: findings depend on supplied metadata. Missing runs remain unknown.</p><pre>" +
  body +
  "</pre></html>"
}
