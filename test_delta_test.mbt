///|
fn delta_report(
  old : Array[@moonverdict.Artifact],
  new : Array[@moonverdict.Artifact],
) -> @moonverdict.Report raise {
  let s = sample()
  @moonverdict.compare({ ..s, tests: old, runs: [], }, {
    ..s,
    tests: new,
    runs: [],
  })
}

///|
fn count_kind(report : @moonverdict.Report, kind : String) -> Int32 {
  report.test_changes.filter(c => c.kind == kind).length()
}

///|
test "test rename follows content and preserves failed witness link" {
  let s = sample()
  let t = s.tests[1]
  let report = @moonverdict.compare(s, {
    ..s,
    tests: [s.tests[0], { ..t, id: "renamed", }],
    runs: [
      s.runs[0],
      { solution: "overflow", test_id: "renamed", verdict: "WA", },
    ],
  })
  assert_eq(count_kind(report, "renamed"), 1)
  assert_eq(count_kind(report, "removed"), 0)
  assert_eq(report.witness_changes[0].content_status, "renamed")
  assert_eq(report.witness_changes[0].after_test, Some("renamed"))
  assert_eq(report.witness_changes[0].after_verdict, Some("WA"))
}

///|
test "same ID changed content is replacement not retained witness" {
  let s = sample()
  let replacement = {
    ..s.tests[1],
    digest: "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  }
  let r = @moonverdict.compare(s, { ..s, tests: [s.tests[0], replacement], })
  assert_eq(count_kind(r, "modified"), 1)
  assert_eq(r.witness_changes[0].content_status, "modified")
}

///|
test "swapped test names are two content renames" {
  let s = sample()
  let report = delta_report(s.tests, [
    { ..s.tests[0], id: "large", },
    { ..s.tests[1], id: "small", },
  ])
  assert_eq(count_kind(report, "renamed"), 2)
  assert_eq(count_kind(report, "modified"), 0)
}

///|
test "duplicates never silently match by a familiar ID" {
  let s = sample()
  let copy = { ..s.tests[1], id: "copy", }
  let report = delta_report([s.tests[0], s.tests[1], copy], s.tests)
  assert_eq(count_kind(report, "ambiguous"), 1)
  assert_eq(
    report.test_changes.filter(c => c.kind == "ambiguous")[0].before_ids,
    ["copy", "large"],
  )
  assert_eq(count_kind(report, "removed"), 0)
}

///|
test "deleting failed test exposes the exact witness" {
  let report = @moonverdict.compare(sample(), reduced())
  assert_eq(count_kind(report, "removed"), 1)
  assert_eq(report.witness_changes[0].before_test, "large")
  assert_eq(report.witness_changes[0].content_status, "removed")
  assert_eq(report.witness_changes[0].after_test, None)
}

///|
test "unknown result on retained witness remains explicit" {
  let s = sample()
  let report = @moonverdict.compare(s, { ..s, runs: [s.runs[0]], })
  assert_eq(report.witness_changes[0].content_status, "unchanged")
  assert_eq(report.witness_changes[0].after_test, Some("large"))
  assert_eq(report.witness_changes[0].after_verdict, None)
  assert_false(has(report, "KNOWN_FAILURE_LOST"))
}

///|
test "new content under a new ID is added while old content is removed" {
  let s = sample()
  let t : @moonverdict.Artifact = {
    id: "new",
    digest: "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  }
  let report = delta_report(s.tests, [s.tests[0], t])
  assert_eq(count_kind(report, "added"), 1)
  assert_eq(count_kind(report, "removed"), 1)
  assert_eq(count_kind(report, "modified"), 0)
}

///|
test "test ordering does not change test delta output" {
  let s = sample()
  let r1 = delta_report(s.tests, [s.tests[1], s.tests[0]])
  let r2 = delta_report([s.tests[1], s.tests[0]], s.tests)
  assert_eq(
    @json.to_json(r1.test_changes).stringify(),
    @json.to_json(r2.test_changes).stringify(),
  )
  assert_eq(count_kind(r1, "unchanged"), 2)
}

///|
test "changed reference solution must still report rejection" {
  let s = sample()
  let sol = {
    ..s.solutions[0],
    digest: "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    expected: "pass",
  }
  let report = @moonverdict.compare(s, { ..s, solutions: [sol], })
  assert_true(has(report, "REFERENCE_REJECTED"))
  assert_true(has(report, "IDENTITY_UNRESOLVED"))
}

///|
test "data-only changes require review even without a verdict regression" {
  let s = sample()
  let r = @moonverdict.compare(
    { ..s, runs: [s.runs[0], { ..s.runs[1], verdict: "AC", }], },
    { ..reduced(), solutions: [{ ..s.solutions[0], expected: "fail", }], },
  )
  assert_eq(r.findings.length(), 0)
  assert_true(@moonverdict.needs_review(r))
}
