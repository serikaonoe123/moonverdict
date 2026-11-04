///|
fn sample() -> @moonverdict.Snapshot {
  {
    schema_version: 1,
    problem: "sum",
    revision: "r1",
    semantics: "sum-v1",
    environment: "fixture",
    checker: "tokens-v1",
    finished: true,
    tests: [
      {
        id: "small",
        digest: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      },
      {
        id: "large",
        digest: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      },
    ],
    solutions: [
      {
        id: "overflow",
        digest: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
        expected: "fail",
      },
    ],
    runs: [
      { solution: "overflow", test_id: "small", verdict: "AC", },
      { solution: "overflow", test_id: "large", verdict: "WA", },
    ],
  }
}

///|
fn reduced() -> @moonverdict.Snapshot {
  let s = sample()
  { ..s, revision: "r2", tests: [s.tests[0]], runs: [s.runs[0]], }
}

///|
fn has(report : @moonverdict.Report, code : String) -> Bool {
  report.findings.any(f => f.code == code)
}

///|
test "incomplete baseline cannot produce a clean comparison" {
  let s = sample()
  let report = @moonverdict.compare({ ..s, runs: [], }, s)
  assert_true(has(report, "BASELINE_INCOMPLETE"))
}

///|
test "removed witness exposes known wrong solution" {
  let r = @moonverdict.compare(sample(), reduced())
  assert_true(has(r, "KNOWN_FAILURE_LOST"))
  assert_eq(r.findings[0].evidence, ["large"])
}

///|
test "unchanged baseline has no findings" {
  assert_eq(@moonverdict.compare(sample(), sample()).findings.length(), 0)
}

///|
test "missing cell never becomes all pass" {
  let s = sample()
  let r = @moonverdict.compare(s, { ..s, runs: [s.runs[0]], })
  assert_true(has(r, "INCOMPLETE"))
  assert_false(has(r, "KNOWN_FAILURE_LOST"))
}

///|
test "skipped unknown and execution errors never become passes" {
  for v in ["SKIPPED", "UNKNOWN", "ERROR"] {
    let s = reduced()
    let r = @moonverdict.compare(sample(), {
      ..s,
      runs: [{ solution: "overflow", test_id: "small", verdict: v, }],
    })
    assert_true(has(r, "INCOMPLETE"))
    assert_false(has(r, "KNOWN_FAILURE_LOST"))
  }
}

///|
test "unfinished invocation with all AC is incomplete" {
  let s = reduced()
  let r = @moonverdict.compare(sample(), { ..s, finished: false, })
  assert_true(has(r, "INCOMPLETE"))
  assert_false(has(r, "KNOWN_FAILURE_LOST"))
}

///|
test "checker environment and semantics changes prevent attribution" {
  let s = reduced()
  for
    changed in [
      { ..s, checker: "new", },
      { ..s, environment: "new", },
      { ..s, semantics: "new", },
    ] {
    let r = @moonverdict.compare(sample(), changed)
    assert_true(has(r, "CONTEXT_CHANGED"))
    assert_true(has(r, "FAIL_TO_PASS_REVIEW"))
    assert_false(has(r, "KNOWN_FAILURE_LOST"))
  }
}

///|
test "same filename changed solution is not matched" {
  let s = reduced()
  let sol = s.solutions[0]
  let r = @moonverdict.compare(sample(), {
    ..s,
    solutions: [
      {
        ..sol,
        digest: "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      },
    ],
  })
  assert_true(has(r, "IDENTITY_UNRESOLVED"))
  assert_false(has(r, "KNOWN_FAILURE_LOST"))
}

///|
test "duplicate content is ambiguous" {
  let s = reduced()
  let sol = s.solutions[0]
  let r = @moonverdict.compare(sample(), {
    ..s,
    solutions: [sol, { ..sol, id: "copy", }],
  })
  assert_true(has(r, "IDENTITY_UNRESOLVED"))
  assert_false(has(r, "KNOWN_FAILURE_LOST"))
}

///|
test "unique renamed solution matches by digest" {
  let s = reduced()
  let sol = s.solutions[0]
  let r = @moonverdict.compare(sample(), {
    ..s,
    solutions: [{ ..sol, id: "renamed", }],
    runs: [{ solution: "renamed", test_id: "small", verdict: "AC", }],
  })
  assert_true(has(r, "KNOWN_FAILURE_LOST"))
}

///|
test "expectation change is not called a leaked wrong solution" {
  let s = reduced()
  let sol = s.solutions[0]
  let r = @moonverdict.compare(sample(), {
    ..s,
    solutions: [{ ..sol, expected: "pass", }],
  })
  assert_true(has(r, "EXPECTATION_CHANGED"))
  assert_false(has(r, "KNOWN_FAILURE_LOST"))
}

///|
test "reference rejection remains visible with incomplete matrix" {
  let s = sample()
  let sol = s.solutions[0]
  let r = @moonverdict.compare(s, {
    ..s,
    solutions: [{ ..sol, expected: "pass", }],
    runs: [s.runs[1]],
  })
  assert_true(has(r, "REFERENCE_REJECTED"))
  assert_true(has(r, "INCOMPLETE"))
}

///|
test "duplicate cells and orphan cells rejected" {
  let s = sample()
  for
    bad in [
      { ..s, runs: [s.runs[0], s.runs[0]], },
      { ..s, runs: [{ solution: "ghost", test_id: "small", verdict: "AC", }], },
    ] {
    let rejected = try {
      @moonverdict.validate(bad)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "empty universe invalid and foreign problem rejected" {
  let s = sample()
  assert_true(
    try {
      @moonverdict.validate({ ..s, tests: [], })
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(@moonverdict.compare(s, { ..s, problem: "other", }))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "schema roundtrip and unknown fields rejected" {
  let text = @json.to_json(sample()).stringify()
  assert_eq(@moonverdict.parse_snapshot(text).problem, "sum")
  assert_true(
    try {
      ignore(
        @moonverdict.parse_snapshot(
          text.replace_all(old="\"schema_version\"", new="\"typo_version\""),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        @moonverdict.parse_snapshot(
          text.replace_all(old="\"WA\"", new="\"TYPO\""),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "HTML treats artifact IDs as text" {
  let report : @moonverdict.Report = {
    before_revision: "<script>alert(1)</script>",
    after_revision: "r2",
    findings: [],
    test_changes: [],
    witness_changes: [],
    evidence_level: "fixture",
  }
  let html = @moonverdict.report_html(report)
  assert_false(html.contains("<script>"))
  assert_true(html.contains("&lt;script&gt;"))
}
