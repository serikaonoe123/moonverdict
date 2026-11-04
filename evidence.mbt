///|
pub(all) struct ObservedArtifacts {
  tests : Array[Artifact]
  solutions : Array[Artifact]
} derive(@json.FromJson)

///|
pub extend ObservedArtifacts with @json.FromJson::{from_json}

///|
pub fn parse_observed(text : String) -> ObservedArtifacts raise {
  @json.from_json(@json.parse(text))
}

///|
pub fn verify_artifacts(
  snapshot : Snapshot,
  observed : ObservedArtifacts,
) -> Array[String] raise InputError {
  validate(snapshot)
  let findings : Array[String] = []
  for
    (kind, expected, actual) in [
      ("test", snapshot.tests, observed.tests),
      (
        "solution",
        snapshot.solutions.map(s => Artifact::{ id: s.id, digest: s.digest, }),
        observed.solutions,
      ),
    ] {
    let by_id : Map[String, String] = Map([])
    for artifact in actual {
      require(!by_id.contains(artifact.id), "duplicate observed artifact id")
      require(digest_valid(artifact.digest), "invalid observed digest")
      by_id[artifact.id] = artifact.digest
    }
    for artifact in expected {
      match by_id.get(artifact.id) {
        None => findings.push(kind + ": missing " + artifact.id)
        Some(digest) =>
          if digest != artifact.digest {
            findings.push(kind + ": digest mismatch " + artifact.id)
          }
      }
      ignore(by_id.remove(artifact.id))
    }
    for id, _ in by_id {
      findings.push(kind + ": unexpected " + id)
    }
  }
  findings.sort()
  findings
}
