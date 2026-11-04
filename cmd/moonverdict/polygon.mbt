///|
fn import_polygon_files(response_path : String, context_path : String) -> Unit {
  try {
    let response : ReadResult = @json.from_json(
      @json.parse(read_text(response_path)),
    )
    let context : ReadResult = @json.from_json(
      @json.parse(read_text(context_path)),
    )
    if !response.ok || !context.ok {
      println(
        "Import read error: " +
        (if !response.ok { response.content } else { context.content }),
      )
      set_exit(2)
      return
    }
    let snapshot = @verdict.import_polygon(
      response.content,
      @verdict.parse_polygon_context(context.content),
    )
    println(@json.to_json(snapshot).stringify(indent=2))
    if @verdict.needs_review(@verdict.compare(snapshot, snapshot)) {
      set_exit(1)
    }
  } catch {
    error => {
      println("Polygon import error: \{error}")
      set_exit(2)
    }
  }
}
