///|
extern "js" fn read_text(path : String) -> String =
  #| (path) => { try { return JSON.stringify({ok:true, content:require('node:fs').readFileSync(path,'utf8')}); } catch(e) { return JSON.stringify({ok:false, content:String(e.message)}); } }

///|
priv struct ReadResult {
  ok : Bool
  content : String
} derive(@json.FromJson)

///|

///|
extern "js" fn set_exit(code : Int32) -> Unit =
  #| (code) => { process.exitCode = code; }

///|
fn main {
  let args = @env.args()
  if args.length() == 5 && args[2] == "verify" {
    verify_files(args[3], args[4])
    return
  }
  if args.length() < 4 || args.length() > 5 {
    println("Usage: moonverdict BEFORE.json AFTER.json [json|html]")
    set_exit(2)
    return
  }
  let format = if args.length() == 5 { args[4] } else { "json" }
  if format != "json" && format != "html" {
    println("Unknown format: " + format)
    set_exit(2)
    return
  }
  try {
    let left : ReadResult = @json.from_json(@json.parse(read_text(args[2])))
    let right : ReadResult = @json.from_json(@json.parse(read_text(args[3])))
    if !left.ok || !right.ok {
      println(
        "Read error: " + (if !left.ok { left.content } else { right.content }),
      )
      set_exit(2)
      return
    }
    let before = @verdict.parse_snapshot(left.content)
    let after = @verdict.parse_snapshot(right.content)
    let report = @verdict.compare(before, after)
    println(
      if format == "html" {
        @verdict.report_html(report)
      } else {
        @verdict.report_json(report)
      },
    )
    if @verdict.needs_review(report) {
      set_exit(1)
    }
  } catch {
    error => {
      println("Input error: \{error}")
      set_exit(2)
    }
  }
}
