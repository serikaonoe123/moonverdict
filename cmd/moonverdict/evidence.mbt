///|
// Framing v1: domain plus NUL, then each field as u64-BE byte length + bytes.
// Node supplies file and crypto primitives; MoonBit validates and compares IDs.
extern "js" fn hash_bundle(path : String) -> String =
  #| (manifestPath) => {
  #|   try {
  #|     const fs = require('node:fs'), p = require('node:path'), crypto = require('node:crypto');
  #|     const manifestFile = fs.realpathSync(manifestPath);
  #|     const root = p.dirname(manifestFile);
  #|     const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
  #|     function read(name) {
  #|       if (typeof name !== 'string' || p.isAbsolute(name)) throw Error('Expected relative evidence path');
  #|       const target = fs.realpathSync(p.resolve(root, name));
  #|       const relative = p.relative(root, target);
  #|       if (relative === '..' || relative.startsWith('..' + p.sep) || p.isAbsolute(relative)) throw Error('Evidence path leaves bundle directory');
  #|       return fs.readFileSync(target);
  #|     }
  #|     function digest(domain, fields) {
  #|       const h = crypto.createHash('sha256').update(domain + '\0');
  #|       for (const field of fields) {
  #|         const bytes = Buffer.isBuffer(field) ? field : Buffer.from(field, 'utf8');
  #|         const size = Buffer.alloc(8); size.writeBigUInt64BE(BigInt(bytes.length));
  #|         h.update(size).update(bytes);
  #|       }
  #|       return h.digest('hex');
  #|     }
  #|     if (manifest.schema_version !== 1 || !Array.isArray(manifest.tests) || !Array.isArray(manifest.solutions)) throw Error('Invalid bundle schema');
  #|     const tests = manifest.tests.map(t => ({id:t.id,digest:digest('moonverdict-test-v1',[read(t.input),read(t.answer)])}));
  #|     const solutions = manifest.solutions.map(s => {
  #|       if (!Array.isArray(s.files) || s.files.length === 0) throw Error('Empty solution files');
  #|       const files = [...s.files].sort();
  #|       if (new Set(files).size !== files.length || files.some(f => typeof f !== 'string' || f.includes('\\') || f.split('/').some(part => !part || part === '.' || part === '..'))) throw Error('Noncanonical or duplicate solution path');
  #|       const fields = []; for (const file of files) fields.push(file,read(file));
  #|       return {id:s.id,digest:digest('moonverdict-solution-v1',fields)};
  #|     });
  #|     return JSON.stringify({ok:true,content:JSON.stringify({tests,solutions})});
  #|   } catch (error) { return JSON.stringify({ok:false,content:String(error.message)}); }
  #| }

///|
fn verify_files(snapshot_path : String, bundle_path : String) -> Unit {
  try {
    let source : ReadResult = @json.from_json(
      @json.parse(read_text(snapshot_path)),
    )
    let hashes : ReadResult = @json.from_json(
      @json.parse(hash_bundle(bundle_path)),
    )
    if !source.ok || !hashes.ok {
      println(
        "Evidence read error: " +
        (if !source.ok { source.content } else { hashes.content }),
      )
      set_exit(2)
      return
    }
    let snapshot = @verdict.parse_snapshot(source.content)
    let observed = @verdict.parse_observed(hashes.content)
    let findings = @verdict.verify_artifacts(snapshot, observed)
    println(
      (
        {
          "artifact_bytes_match": findings.is_empty(),
          "run_binding_verified": false,
          "findings": findings,
        } : Json).stringify(indent=2),
    )
    if !findings.is_empty() {
      set_exit(1)
    }
  } catch {
    error => {
      println("Evidence input error: \{error}")
      set_exit(2)
    }
  }
}
