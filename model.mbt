///|
pub(all) struct Artifact {
  id : String
  digest : String
} derive(ToJson, @json.FromJson)

///|
pub(all) struct Solution {
  id : String
  digest : String
  expected : String
} derive(ToJson, @json.FromJson)

///|
pub(all) struct Run {
  solution : String
  test_id : String
  verdict : String
} derive(ToJson, @json.FromJson)

///|
pub(all) struct Snapshot {
  schema_version : Int32
  problem : String
  revision : String
  semantics : String
  environment : String
  checker : String
  finished : Bool
  tests : Array[Artifact]
  solutions : Array[Solution]
  runs : Array[Run]
} derive(ToJson, @json.FromJson)

///|
pub(all) struct Finding {
  code : String
  solution : String
  evidence : Array[String]
  message : String
} derive(ToJson)

///|
pub(all) struct Report {
  before_revision : String
  after_revision : String
  findings : Array[Finding]
  // Claims in this prototype are conditional on the supplied artifact metadata.
  evidence_level : String
} derive(ToJson)

///|
pub suberror InputError {
  Invalid(String)
}

///|
fn require(condition : Bool, message : String) -> Unit raise InputError {
  if !condition {
    raise Invalid(message)
  }
}

///|
fn digest_valid(value : String) -> Bool {
  value.length() == 64 &&
  value.to_array().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
}

///|
fn keys(value : Json, allowed : Array[String]) -> Unit raise InputError {
  guard value is Object(fields) else { raise Invalid("expected object") }
  for key, _ in fields {
    require(allowed.contains(key), "unknown field: " + key)
  }
}

///|
pub fn parse_snapshot(text : String) -> Snapshot raise {
  let value = @json.parse(text)
  keys(value, [
    "schema_version", "problem", "revision", "semantics", "environment", "checker",
    "finished", "tests", "solutions", "runs",
  ])
  guard value is Object(fields) else { raise Invalid("expected snapshot") }
  for
    (field, names) in [
      ("tests", ["id", "digest"]),
      ("solutions", ["id", "digest", "expected"]),
      ("runs", ["solution", "test_id", "verdict"]),
    ] {
    if fields.get(field) is Some(Array(items)) {
      for item in items {
        keys(item, names)
      }
    }
  }
  let snapshot : Snapshot = @json.from_json(value)
  validate(snapshot)
  snapshot
}

///|
pub fn validate(s : Snapshot) -> Unit raise InputError {
  require(s.schema_version == 1, "unsupported schema_version")
  require(s.problem != "" && s.revision != "", "empty problem/revision")
  require(
    s.semantics != "" && s.environment != "" && s.checker != "",
    "missing comparison context",
  )
  require(s.tests.length() > 0, "empty test universe")
  require(s.solutions.length() > 0, "empty solution universe")
  let tests : Map[String, Bool] = Map([])
  let solutions : Map[String, Bool] = Map([])
  for t in s.tests {
    require(
      t.id != "" && !tests.contains(t.id),
      "empty/duplicate test id: " + t.id,
    )
    require(digest_valid(t.digest), "invalid test digest: " + t.id)
    tests[t.id] = true
  }
  for sol in s.solutions {
    require(
      sol.id != "" && !solutions.contains(sol.id),
      "empty/duplicate solution id: " + sol.id,
    )
    require(digest_valid(sol.digest), "invalid solution digest: " + sol.id)
    require(
      ["pass", "fail", "unspecified"].contains(sol.expected),
      "invalid expectation",
    )
    solutions[sol.id] = true
  }
  let cells : Map[String, Map[String, Bool]] = Map([])
  for r in s.runs {
    require(
      tests.contains(r.test_id) && solutions.contains(r.solution),
      "run references unknown artifact",
    )
    require(
      ["AC", "WA", "PE", "TLE", "MLE", "RE", "SKIPPED", "UNKNOWN", "ERROR"].contains(
        r.verdict,
      ),
      "unsupported verdict: " + r.verdict,
    )
    let row = cells.get(r.solution).unwrap_or(Map([]))
    require(!row.contains(r.test_id), "duplicate run cell")
    row[r.test_id] = true
    cells[r.solution] = row
  }
}

///|
pub extend Artifact with ToJson::{to_json}

///|
pub extend Artifact with @json.FromJson::{from_json}

///|
pub extend Solution with ToJson::{to_json}

///|
pub extend Solution with @json.FromJson::{from_json}

///|
pub extend Run with ToJson::{to_json}

///|
pub extend Run with @json.FromJson::{from_json}

///|
pub extend Snapshot with ToJson::{to_json}

///|
pub extend Snapshot with @json.FromJson::{from_json}

///|
pub extend Finding with ToJson::{to_json}

///|
pub extend Report with ToJson::{to_json}
