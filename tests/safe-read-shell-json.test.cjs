// Node test runner (`node --test tests/`) for bin/safe-read-shell-json.sh,
// the guard every live read of shell.json goes through.
//
// The widget runs inside a shell process that stays up for the whole session,
// so it must never be talked into reading whatever happens to sit at
// ~/.config/omarchy/shell.json. These cases pin the guard's contract, which
// Panel.qml depends on: a refused path produces empty stdout and a non-zero
// exit, a missing file produces empty stdout and success, and only an
// ordinary file under the cap is ever printed. Empty stdout is what makes the
// widget fall back to its injected settings snapshot instead of applying
// something foreign.
//
// Each case builds a throwaway $HOME so the script sees a real path, rather
// than a mocked one — the whole point here is what the filesystem does.
const test = require("node:test")
const assert = require("node:assert/strict")
const { execFileSync } = require("node:child_process")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const SCRIPT = path.join(__dirname, "..", "bin", "safe-read-shell-json.sh")
const MAX_BYTES = 524288

// Runs the guard against a fresh $HOME that `build` has laid out, and reports
// what the caller actually sees: exit code, stdout, stderr.
function run(build) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "theme-rotate-guard-"))
  try {
    fs.mkdirSync(path.join(home, ".config", "omarchy"), { recursive: true })
    build({ home, config: path.join(home, ".config", "omarchy", "shell.json") })
    try {
      const stdout = execFileSync("bash", [SCRIPT], {
        env: { ...process.env, HOME: home },
        encoding: "utf8",
        timeout: 10000,
        // A device node would otherwise be capped by the buffer rather than
        // by the guard, which would hide a real failure.
        maxBuffer: 64 * 1024 * 1024
      })
      return { code: 0, stdout, stderr: "" }
    } catch (e) {
      if (e.code === "ETIMEDOUT" || e.signal) assert.fail("guard blocked or was killed: " + (e.signal || e.code))
      return { code: e.status, stdout: String(e.stdout || ""), stderr: String(e.stderr || "") }
    }
  } finally {
    fs.rmSync(home, { recursive: true, force: true })
  }
}

// A refusal must be silent on stdout: anything printed there would be applied
// as settings by the caller.
function assertRefused(result, because) {
  assert.notEqual(result.code, 0, "expected a non-zero exit when " + because)
  assert.equal(result.stdout, "", "refused path must print nothing on stdout when " + because)
  assert.match(result.stderr, /refusing to read/, "expected a reason on stderr when " + because)
}

test("prints an ordinary shell.json verbatim", () => {
  const body = JSON.stringify({
    version: 1,
    bar: { layout: { left: [], center: [], right: [{ id: "tim.theme-rotate", mode: "interval" }] } }
  })
  const result = run(({ config }) => fs.writeFileSync(config, body))
  assert.equal(result.code, 0)
  assert.equal(result.stdout, body)
})

test("a missing file is a silent success, not an error", () => {
  // Normal on first run, before the shell has ever written the file.
  const result = run(() => {})
  assert.equal(result.code, 0)
  assert.equal(result.stdout, "")
})

test("an empty file is a silent success", () => {
  const result = run(({ config }) => fs.writeFileSync(config, ""))
  assert.equal(result.code, 0)
  assert.equal(result.stdout, "")
})

test("refuses a symlink without printing the target", () => {
  // The case the guard exists for: the shell must not be made to follow the
  // path somewhere the user never pointed it.
  const secret = "SHOULD-NEVER-BE-PRINTED"
  const result = run(({ home, config }) => {
    fs.writeFileSync(path.join(home, "elsewhere.json"), secret)
    fs.symlinkSync(path.join(home, "elsewhere.json"), config)
  })
  assertRefused(result, "the path is a symlink")
  assert.doesNotMatch(result.stdout + result.stderr, /SHOULD-NEVER-BE-PRINTED/)
})

test("refuses a dangling symlink rather than calling it missing", () => {
  // -e and -f follow the link and would both say "no such file", which would
  // wrongly report the normal first-run state for a replaced path.
  const result = run(({ home, config }) => fs.symlinkSync(path.join(home, "nope.json"), config))
  assertRefused(result, "the path is a dangling symlink")
})

test("refuses a symlink pointing at a directory", () => {
  const result = run(({ home, config }) => {
    fs.mkdirSync(path.join(home, "adir"))
    fs.symlinkSync(path.join(home, "adir"), config)
  })
  assertRefused(result, "the path is a symlink to a directory")
})

test("refuses a directory in place of the file", () => {
  const result = run(({ config }) => fs.mkdirSync(config))
  assertRefused(result, "the path is a directory")
})

test("refuses a FIFO instead of blocking on it forever", () => {
  // A plain read of a FIFO with no writer blocks on open, which would hang
  // the reader for the rest of the session. run() fails the test on a
  // timeout, so reaching the assertions at all is part of the check.
  const result = run(({ config }) => execFileSync("mkfifo", [config]))
  assertRefused(result, "the path is a FIFO")
})

test("refuses a character device without streaming from it", () => {
  // /dev/zero never ends: the guard has to reject it rather than read it.
  const result = run(({ config }) => fs.symlinkSync("/dev/zero", config))
  assertRefused(result, "the path is a character device")
})

test("refuses a file over the size cap", () => {
  const result = run(({ config }) => fs.writeFileSync(config, "x".repeat(MAX_BYTES + 1)))
  assertRefused(result, "the file is over the cap")
  assert.match(result.stderr, /over the 524288 byte cap/)
})

test("allows a file exactly at the size cap", () => {
  // The cap is inclusive, so the boundary is a normal read, not a refusal.
  const body = "y".repeat(MAX_BYTES)
  const result = run(({ config }) => fs.writeFileSync(config, body))
  assert.equal(result.code, 0)
  assert.equal(result.stdout.length, MAX_BYTES)
})

test("never prints more than the cap", () => {
  // The size check and the read are two separate steps, so the read caps
  // itself too: a file that grows in between still cannot stream past it.
  for (const size of [0, 1, 1024, MAX_BYTES]) {
    const result = run(({ config }) => fs.writeFileSync(config, "z".repeat(size)))
    assert.equal(result.code, 0)
    assert.ok(result.stdout.length <= MAX_BYTES, size + " byte file printed " + result.stdout.length)
  }
})

test("does not print contents when the file cannot be read", () => {
  const result = run(({ config }) => {
    fs.writeFileSync(config, JSON.stringify({ version: 1 }))
    fs.chmodSync(config, 0o000)
  })
  assert.notEqual(result.code, 0)
  assert.equal(result.stdout, "")
})
