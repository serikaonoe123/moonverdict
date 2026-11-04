///|
fn group_tests(tests : Array[Artifact]) -> Map[String, Array[String]] {
  let groups : Map[String, Array[String]] = Map([])
  for artifact in tests {
    let ids = groups.get(artifact.digest).unwrap_or([])
    ids.push(artifact.id)
    groups[artifact.digest] = ids
  }
  for _, ids in groups {
    ids.sort()
  }
  groups
}

///|
fn compare_tests(
  before : Array[Artifact],
  after : Array[Artifact],
) -> Array[TestChange] {
  let old_groups = group_tests(before)
  let new_groups = group_tests(after)
  let digests : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  for t in before + after {
    if !seen.contains(t.digest) {
      digests.push(t.digest)
      seen[t.digest] = true
    }
  }
  digests.sort()
  let used_old : Map[String, Bool] = Map([])
  let used_new : Map[String, Bool] = Map([])
  let changes : Array[TestChange] = []
  // Content identity takes precedence over a reused or swapped display ID.
  for digest in digests {
    let old_ids = old_groups.get(digest).unwrap_or([])
    let new_ids = new_groups.get(digest).unwrap_or([])
    if !old_ids.is_empty() && !new_ids.is_empty() {
      let kind = if old_ids.length() == 1 && new_ids.length() == 1 {
        if old_ids[0] == new_ids[0] {
          "unchanged"
        } else {
          "renamed"
        }
      } else {
        "ambiguous"
      }
      changes.push({
        kind,
        before_ids: old_ids,
        after_ids: new_ids,
        before_digest: Some(digest),
        after_digest: Some(digest),
      })
      for id in old_ids {
        used_old[id] = true
      }
      for id in new_ids {
        used_new[id] = true
      }
    }
  }
  let old_by_id : Map[String, Artifact] = Map([])
  let new_by_id : Map[String, Artifact] = Map([])
  let ids : Array[String] = []
  let seen_ids : Map[String, Bool] = Map([])
  for t in before {
    old_by_id[t.id] = t
  }
  for t in after {
    new_by_id[t.id] = t
  }
  for t in before + after {
    if !seen_ids.contains(t.id) {
      ids.push(t.id)
      seen_ids[t.id] = true
    }
  }
  ids.sort()
  for id in ids {
    match (old_by_id.get(id), new_by_id.get(id)) {
      (Some(old), Some(new)) =>
        if !used_old.contains(id) &&
          !used_new.contains(id) &&
          old_groups[old.digest].length() == 1 &&
          new_groups[new.digest].length() == 1 {
          changes.push({
            kind: "modified",
            before_ids: [id],
            after_ids: [id],
            before_digest: Some(old.digest),
            after_digest: Some(new.digest),
          })
          used_old[id] = true
          used_new[id] = true
        }
      _ => ()
    }
  }
  for id in ids {
    if old_by_id.get(id) is Some(old) && !used_old.contains(id) {
      changes.push({
        kind: "removed",
        before_ids: [id],
        after_ids: [],
        before_digest: Some(old.digest),
        after_digest: None,
      })
    }
    if new_by_id.get(id) is Some(new) && !used_new.contains(id) {
      changes.push({
        kind: "added",
        before_ids: [],
        after_ids: [id],
        before_digest: None,
        after_digest: Some(new.digest),
      })
    }
  }
  changes
}

///|
pub fn needs_review(report : Report) -> Bool {
  !report.findings.is_empty() ||
  report.test_changes.any(change => change.kind != "unchanged")
}
