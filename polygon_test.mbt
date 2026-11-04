///|
fn poly_context() -> @moonverdict.PolygonContext {
  let s = sample()
  {
    problem: "p",
    package_id: 10L,
    package_revision: 2,
    package_state: "READY",
    package_comment: "",
    invocation_id: 20L,
    testset: "tests",
    semantics: "sum",
    environment: "fixture",
    checker: "tokens",
    tests: [{ index: 1, id: "small", digest: s.tests[0].digest, }],
    solutions: [{ id: "overflow", digest: s.solutions[0].digest, }],
  }
}

///|
fn poly_json(
  verdict~ : String = "WA",
  state~ : String = "FINISHED",
  tag~ : String = "WA",
  violate~ : Bool = false,
  missing~ : Bool = false,
  duplicate~ : Bool = false,
  no_name~ : Bool = false,
  extra_tags~ : Bool = false,
) -> String {
  let run : Json = {
    "id": 30,
    "solution": if no_name {
      Json::null()
    } else {
      Json::string("overflow")
    },
    "test": 1,
    "verdict": verdict,
    "violateTag": violate,
  }
  let runs = if missing { [] } else if duplicate { [run, run] } else { [run] }
  let groups : Map[String, String] = if extra_tags {
    { "g": "OK" }
  } else {
    Map([])
  }
  let value : Json = {
    "status": "OK",
    "result": {
      "invocation": {
        "id": 20,
        "packageId": 10,
        "testset": "tests",
        "status": state,
        "violateTag": violate,
        "solutions": ["overflow"],
        "tests": [1],
      },
      "solutionTags": [{ "name": "overflow", "tag": tag, "groupTags": groups }],
      "runs": runs,
    },
  }
  value.stringify()
}

///|
test "import preserves package source and maps verdict tags" {
  let s = @moonverdict.import_polygon(poly_json(), poly_context())
  assert_eq(s.revision, "2")
  assert_eq(s.source, Some("polygon/package/10/invocation/20/testset/tests"))
  assert_eq(s.runs[0].verdict, "WA")
  assert_eq(s.solutions[0].expected, "fail")
  assert_true(s.finished)
  assert_eq(s.import_notes, Some([]))
  assert_eq(
    @moonverdict.parse_snapshot(@json.to_json(s).stringify()).source,
    s.source,
  )
}

///|
test "all documented verdict codes are conservative" {
  for
    (raw, normalized) in [
      ("OK", "AC"),
      ("WA", "WA"),
      ("PE", "PE"),
      ("TL", "TLE"),
      ("ML", "MLE"),
      ("RE", "RE"),
      ("IL", "ERROR"),
      ("CE", "ERROR"),
      ("FL", "ERROR"),
      ("RJ", "SKIPPED"),
      ("NO", "UNKNOWN"),
      ("TS", "UNKNOWN"),
    ] {
    let s = @moonverdict.import_polygon(poly_json(verdict=raw), poly_context())
    assert_eq(s.runs[0].verdict, normalized)
    if ["RJ", "NO", "TS", "IL", "CE", "FL"].contains(raw) {
      assert_true(has(@moonverdict.compare(s, s), "INCOMPLETE"))
    }
  }
}

///|
test "finished with missing cells remains incomplete" {
  let s = @moonverdict.import_polygon(poly_json(missing=true), poly_context())
  assert_true(has(@moonverdict.compare(s, s), "INCOMPLETE"))
}

///|
test "pending running and aborted cannot become final all pass" {
  for state in ["PENDING", "RUNNING", "ABORTED"] {
    let s = @moonverdict.import_polygon(
      poly_json(verdict="OK", state~),
      poly_context(),
    )
    assert_false(s.finished)
    assert_true(has(@moonverdict.compare(s, s), "INCOMPLETE"))
  }
}

///|
test "package and invocation mismatches rejected" {
  let c = poly_context()
  for
    bad in [
      { ..c, package_id: 11L, },
      { ..c, invocation_id: 21L, },
      { ..c, testset: "other", },
    ] {
    assert_true(
      try {
        ignore(@moonverdict.import_polygon(poly_json(), bad))
        false
      } catch {
        _ => true
      },
    )
  }
  let unbound = poly_json().replace_all(
    old="\"packageId\":10",
    new="\"packageId\":null",
  )
  assert_true(
    try {
      ignore(@moonverdict.import_polygon(unbound, c))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "package failure and run tag flags survive import and comparison" {
  let c = poly_context()
  let s = @moonverdict.import_polygon(poly_json(verdict="OK", violate=true), {
    ..c,
    package_state: "FAILED",
    package_comment: "wrong solution passed",
  })
  assert_true(s.import_notes.unwrap().length() >= 3)
  assert_true(has(@moonverdict.compare(s, s), "IMPORT_REVIEW"))
}

///|
test "duplicate run IDs and repeated cells are rejected" {
  assert_true(
    try {
      ignore(
        @moonverdict.import_polygon(poly_json(duplicate=true), poly_context()),
      )
      false
    } catch {
      _ => true
    },
  )
  let value = @json.parse(poly_json(duplicate=true))
  guard value is Object(root) else { abort("fixture") }
  guard root["result"] is Object(result) else { abort("fixture") }
  guard result["runs"] is Array(runs) else { abort("fixture") }
  guard runs[0] is Object(first) else { abort("fixture") }
  first["id"] = Json::number(31)
  let raw = value.stringify()
  assert_true(
    try {
      ignore(@moonverdict.import_polygon(raw, poly_context()))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "large IDs retain exact JSON integer identity" {
  let c = { ..poly_context(), invocation_id: 9007199254740993L, }
  let raw = poly_json().replace_all(
    old="\"id\":20",
    new="\"id\":9007199254740993",
  )
  let imported = @moonverdict.import_polygon(raw, c)
  assert_eq(
    imported.source,
    Some("polygon/package/10/invocation/9007199254740993/testset/tests"),
  )
}

///|
test "fractional exponential and duplicate key identities rejected" {
  for
    raw in [
      poly_json().replace_all(old="\"id\":20", new="\"id\":20.5"),
      poly_json().replace_all(old="\"id\":20", new="\"id\":2e1"),
      poly_json().replace_all(old="\"id\":20", new="\"id\":20,\"id\":20"),
      poly_json().replace_all(old="\"test\":1", new="\"test\":1.5"),
    ] {
    assert_true(
      try {
        ignore(@moonverdict.import_polygon(raw, poly_context()))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "reference tags and unconstrained accepted-or-slow tag differ" {
  for tag in ["MA", "OK"] {
    let s = @moonverdict.import_polygon(poly_json(tag~), poly_context())
    assert_eq(s.solutions[0].expected, "pass")
    assert_true(has(@moonverdict.compare(s, s), "REFERENCE_REJECTED"))
  }
  for tag in ["TO", "NR"] {
    let s = @moonverdict.import_polygon(poly_json(tag~), poly_context())
    assert_eq(s.solutions[0].expected, "unspecified")
    assert_true(has(@moonverdict.compare(s, s), "IMPORT_REVIEW"))
  }
}

///|
test "missing source name is diagnosed not turned into pass" {
  let s = @moonverdict.import_polygon(
    poly_json(verdict="OK", no_name=true),
    poly_context(),
  )
  assert_true(s.runs.is_empty())
  let r = @moonverdict.compare(s, s)
  assert_true(has(r, "IMPORT_REVIEW"))
  assert_true(has(r, "INCOMPLETE"))
}

///|
test "extra tag semantics require review" {
  let s = @moonverdict.import_polygon(
    poly_json(tag="MA", extra_tags=true),
    poly_context(),
  )
  assert_eq(s.solutions[0].expected, "unspecified")
  assert_true(has(@moonverdict.compare(s, s), "IMPORT_REVIEW"))
}

///|
test "unknown verdict or failed API envelope rejected" {
  for
    raw in [
      poly_json(verdict="FUTURE"),
      "{\"status\":\"FAILED\",\"comment\":\"denied\"}",
    ] {
    assert_true(
      try {
        ignore(@moonverdict.import_polygon(raw, poly_context()))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "unbound extra materials rejected" {
  let c = poly_context()
  assert_true(
    try {
      ignore(@moonverdict.import_polygon(poly_json(), { ..c, tests: [], }))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        @moonverdict.import_polygon(poly_json(), {
          ..c,
          tests: c.tests + [{ ..c.tests[0], index: 2, id: "extra", }],
        }),
      )
      false
    } catch {
      _ => true
    },
  )
}
