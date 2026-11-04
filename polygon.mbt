///|
pub(all) struct PolygonTestBinding {
  index : Int32
  id : String
  digest : String
} derive(@json.FromJson)

///|
pub extend PolygonTestBinding with @json.FromJson::{from_json}

///|
pub(all) struct PolygonContext {
  problem : String
  package_id : Int64
  package_revision : Int32
  package_state : String
  package_comment : String
  invocation_id : Int64
  testset : String
  semantics : String
  environment : String
  checker : String
  tests : Array[PolygonTestBinding]
  solutions : Array[Artifact]
} derive(@json.FromJson)

///|
pub extend PolygonContext with @json.FromJson::{from_json}

///|
priv struct PolygonInvocation {
  id : Int64
  packageId : Int64?
  testset : String
  status : String
  violateTag : Bool
  solutions : Array[String]
  tests : Array[Int32]
} derive(@json.FromJson)

///|
priv struct PolygonTag {
  name : String
  tag : String?
  testsetTags : Map[String, String]?
  groupTags : Map[String, String]?
} derive(@json.FromJson)

///|
priv struct PolygonRun {
  id : Int64
  solution : String?
  verdict : String
  violateTag : Bool
} derive(@json.FromJson)

///|
fn[T : @json.FromJson] json_field(value : Json, key : String) -> T raise {
  guard value is Object(fields) else {
    raise Invalid("expected Polygon object")
  }
  guard fields.get(key) is Some(item) else {
    raise Invalid("missing Polygon field: " + key)
  }
  @json.from_json(item)
}

///|
fn decimal_integer(value : Json) -> String raise InputError {
  guard value is Number(_, repr=Some(text)) else {
    raise Invalid("expected JSON integer with preserved representation")
  }
  require(
    !text.is_empty() && text.to_array().all(c => c >= '0' && c <= '9'),
    "identifier/index must be an unsigned decimal integer",
  )
  text
}

///|
fn id_fields(value : Json, names : Array[String]) -> Json raise InputError {
  guard value is Object(fields) else {
    raise Invalid("expected id-bearing object")
  }
  for name in names {
    if fields.get(name) is Some(number) {
      if number == Json::null() {
        ignore(fields.remove(name))
      } else {
        fields[name] = Json::string(decimal_integer(number))
      }
    }
  }
  value
}

///|
fn strip_nulls(value : Json, names : Array[String]) -> Json raise InputError {
  guard value is Object(fields) else { raise Invalid("expected object") }
  for name in names {
    if fields.get(name) == Some(Json::null()) {
      ignore(fields.remove(name))
    }
  }
  value
}

///|
pub fn parse_polygon_context(text : String) -> PolygonContext raise {
  let value = @json.parse(
    text,
    preserve_number_repr=true,
    reject_duplicate_keys=true,
  )
  keys(value, [
    "problem", "package_id", "package_revision", "package_state", "package_comment",
    "invocation_id", "testset", "semantics", "environment", "checker", "tests", "solutions",
  ])
  let revision : Json = json_field(value, "package_revision")
  ignore(decimal_integer(revision))
  let tests : Array[Json] = json_field(value, "tests")
  for t in tests {
    ignore(decimal_integer((json_field(t, "index") : Json)))
  }
  @json.from_json(id_fields(value, ["package_id", "invocation_id"]))
}

///|
fn polygon_verdict(value : String) -> String raise InputError {
  match value {
    "OK" => "AC"
    "WA" | "PE" | "RE" => value
    "TL" => "TLE"
    "ML" => "MLE"
    "RJ" => "SKIPPED"
    "NO" | "TS" => "UNKNOWN"
    "IL" | "CE" | "FL" => "ERROR"
    _ => raise Invalid("unsupported Polygon verdict: " + value)
  }
}

///|
fn polygon_expectation(tag : String?) -> String raise InputError {
  match tag {
    Some("MA" | "OK") => "pass"
    Some("WA" | "PE" | "TL" | "ML" | "RE" | "TM" | "RJ") => "fail"
    Some("NR" | "TO") | None => "unspecified"
    Some(other) => raise Invalid("unsupported Polygon solution tag: " + other)
  }
}

///|
pub fn import_polygon(
  text : String,
  context : PolygonContext,
) -> Snapshot raise {
  let response = @json.parse(
    text,
    preserve_number_repr=true,
    reject_duplicate_keys=true,
  )
  let status : String = json_field(response, "status")
  require(status == "OK", "Polygon API response failed")
  let result : Json = json_field(response, "result")
  let raw_invocation : Json = json_field(result, "invocation")
  let raw_tests : Array[Json] = json_field(raw_invocation, "tests")
  for t in raw_tests {
    ignore(decimal_integer(t))
  }
  let invocation : PolygonInvocation = @json.from_json(
    id_fields(raw_invocation, ["id", "packageId"]),
  )
  require(
    context.package_id > 0L &&
    context.invocation_id > 0L &&
    context.package_revision >= 0,
    "invalid source identifiers",
  )
  require(invocation.id == context.invocation_id, "invocation id mismatch")
  require(
    invocation.packageId == Some(context.package_id),
    "package id missing or mismatched; unbound runs are unsupported",
  )
  require(
    invocation.testset == context.testset && context.testset != "",
    "testset mismatch",
  )
  require(
    ["PENDING", "RUNNING", "FINISHED", "ABORTED"].contains(invocation.status),
    "invalid invocation status",
  )
  require(
    ["PENDING", "RUNNING", "READY", "FAILED"].contains(context.package_state),
    "invalid package state",
  )
  let notes : Array[String] = []
  if invocation.violateTag {
    notes.push(
      "Polygon invocation reports violateTag; package verification is not certified successful.",
    )
  }
  if context.package_state != "READY" || context.package_comment != "" {
    notes.push(
      "Package state/comment requires review: " +
      context.package_state +
      ": " +
      context.package_comment,
    )
  }
  let bound_tests : Map[Int32, Artifact] = Map([])
  for t in context.tests {
    require(
      t.index > 0 && !bound_tests.contains(t.index),
      "duplicate/invalid bound test index",
    )
    bound_tests[t.index] = { id: t.id, digest: t.digest, }
  }
  let tests : Array[Artifact] = []
  let invocation_tests : Map[Int32, String] = Map([])
  for index in invocation.tests {
    require(
      !invocation_tests.contains(index),
      "duplicate invocation test index",
    )
    guard bound_tests.get(index) is Some(t) else {
      raise Invalid("missing test material binding")
    }
    invocation_tests[index] = t.id
    tests.push(t)
  }
  require(bound_tests.length() == tests.length(), "extra test material binding")
  let bound_solutions : Map[String, Artifact] = Map([])
  for s in context.solutions {
    require(!bound_solutions.contains(s.id), "duplicate bound solution")
    bound_solutions[s.id] = s
  }
  let raw_tags : Array[Json] = json_field(result, "solutionTags")
  let by_name : Map[String, PolygonTag] = Map([])
  for raw_tag in raw_tags {
    let tag : PolygonTag = @json.from_json(
      strip_nulls(raw_tag, ["tag", "testsetTags", "groupTags"]),
    )
    require(
      !by_name.contains(tag.name) && invocation.solutions.contains(tag.name),
      "duplicate/unknown solution tag",
    )
    by_name[tag.name] = tag
  }
  let solutions : Array[Solution] = []
  let names : Map[String, Bool] = Map([])
  for name in invocation.solutions {
    require(!names.contains(name), "duplicate invocation solution")
    names[name] = true
    guard bound_solutions.get(name) is Some(binding) else {
      raise Invalid("missing solution material binding")
    }
    let expectation = match by_name.get(name) {
      None => {
        notes.push("Missing stored solution tag: " + name)
        "unspecified"
      }
      Some(tag) =>
        if !tag.testsetTags.unwrap_or(Map([])).is_empty() ||
          !tag.groupTags.unwrap_or(Map([])).is_empty() {
          notes.push("Extra testset/group tags are unsupported: " + name)
          "unspecified"
        } else {
          let value = polygon_expectation(tag.tag)
          if value == "unspecified" {
            notes.push("No supported binary expectation for solution: " + name)
          }
          value
        }
    }
    solutions.push({ id: name, digest: binding.digest, expected: expectation, })
  }
  require(
    bound_solutions.length() == solutions.length(),
    "extra solution material binding",
  )
  let raw_runs : Array[Json] = json_field(result, "runs")
  let runs : Array[Run] = []
  let run_ids : Map[Int64, Bool] = Map([])
  for raw in raw_runs {
    ignore(decimal_integer((json_field(raw, "test") : Json)))
    let run : PolygonRun = @json.from_json(
      strip_nulls(id_fields(raw, ["id"]), ["solution"]),
    )
    require(
      run.id > 0L && !run_ids.contains(run.id),
      "duplicate/invalid run id; rejudge history needs explicit resolution",
    )
    run_ids[run.id] = true
    let index : Int32 = json_field(raw, "test")
    guard invocation_tests.get(index) is Some(test_id) else {
      raise Invalid("run outside invocation tests")
    }
    let verdict = polygon_verdict(run.verdict)
    match run.solution {
      None =>
        notes.push("Run has no stored solution name: " + run.id.to_string())
      Some(name) => {
        require(names.contains(name), "run outside invocation solutions")
        runs.push({ solution: name, test_id, verdict, })
      }
    }
    if run.violateTag {
      notes.push("Stored run violates solution tag: " + run.id.to_string())
    }
  }
  let snapshot : Snapshot = {
    schema_version: 1,
    problem: context.problem,
    revision: context.package_revision.to_string(),
    semantics: context.semantics,
    environment: context.environment,
    checker: context.checker,
    finished: invocation.status == "FINISHED",
    tests,
    solutions,
    runs,
    source: Some(
      "polygon/package/" +
      context.package_id.to_string() +
      "/invocation/" +
      invocation.id.to_string() +
      "/testset/" +
      context.testset,
    ),
    import_notes: Some(notes),
  }
  validate(snapshot)
  snapshot
}
