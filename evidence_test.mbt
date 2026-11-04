///|
fn evidence_sample() -> @moonverdict.Snapshot {
  {
    schema_version: 1,
    problem: "p",
    revision: "r",
    semantics: "s",
    environment: "e",
    checker: "c",
    finished: true,
    tests: [
      {
        id: "t",
        digest: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      },
    ],
    solutions: [
      {
        id: "s",
        digest: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        expected: "pass",
      },
    ],
    runs: [{ solution: "s", test_id: "t", verdict: "AC", }],
  }
}

///|
test "evidence missing extra mismatch and matching artifacts" {
  let s = evidence_sample()
  let observed : @moonverdict.ObservedArtifacts = {
    tests: s.tests,
    solutions: [{ id: "s", digest: s.solutions[0].digest, }],
  }
  assert_eq(@moonverdict.verify_artifacts(s, observed), [])
  assert_eq(@moonverdict.verify_artifacts(s, { ..observed, tests: [], }), [
    "test: missing t",
  ])
  assert_eq(
    @moonverdict.verify_artifacts(s, {
      ..observed,
      tests: [{ id: "t", digest: s.solutions[0].digest, }],
    }),
    ["test: digest mismatch t"],
  )
  assert_eq(
    @moonverdict.verify_artifacts(s, {
      ..observed,
      tests: [s.tests[0], { ..s.tests[0], id: "extra", }],
    }),
    ["test: unexpected extra"],
  )
}

///|
test "duplicate observed IDs rejected" {
  let s = evidence_sample()
  let observed : @moonverdict.ObservedArtifacts = {
    tests: [s.tests[0], s.tests[0]],
    solutions: [],
  }
  assert_true(
    try {
      ignore(@moonverdict.verify_artifacts(s, observed))
      false
    } catch {
      _ => true
    },
  )
}
