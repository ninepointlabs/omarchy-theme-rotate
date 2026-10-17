// Node test runner (`node --test tests/about.test.cjs`) for the About page's
// facts: they come from the repo's own files (manifest.json, LICENSE) and from
// bin/about-versions.sh, so these check the parsing against the real files.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { execFileSync } = require("node:child_process")
const About = require("../About.js")

const ROOT = path.join(__dirname, "..")
const read = (name) => fs.readFileSync(path.join(ROOT, name), "utf8")

test("version comes from manifest.json", () => {
  const manifest = JSON.parse(read("manifest.json"))
  assert.equal(About.manifestVersion(read("manifest.json")), manifest.version)
  assert.match(About.manifestVersion(read("manifest.json")), /^\d+\.\d+\.\d+$/)
  assert.equal(About.manifestVersion("not json"), "")
  assert.equal(About.manifestVersion(""), "")
})

test("license summary and text come from LICENSE", () => {
  const text = read("LICENSE")
  assert.equal(About.licenseSummary(text), "MIT License, © 2026 Nine Point Labs")
  const body = About.licenseBody(text)
  assert.ok(body.startsWith("MIT License\n\nCopyright (c) 2026 Nine Point Labs\n\nPermission is hereby granted"))
  assert.ok(body.includes("THE SOFTWARE IS PROVIDED \"AS IS\""))
  assert.ok(!/\n(?!\n)/.test(body.replace(/\n\n/g, "")), "one line per paragraph")
})

test("facts: Nine Point Labs, created date, support address", () => {
  assert.equal(About.ORGANIZATION, "Nine Point Labs")
  assert.equal(About.SUPPORT_EMAIL, "help@ninepointlabs.com")
  const first = execFileSync("git", ["log", "--reverse", "--format=%ad", "--date=format:%B %Y"], { cwd: ROOT, encoding: "utf8" }).split("\n")[0]
  assert.equal(About.CREATED, first)
})

test("privacy statement names the one network service and where data lives", () => {
  assert.match(About.PRIVACY, /No accounts and no telemetry/)
  assert.match(About.PRIVACY, /wttr\.in, and only while Follow the sun is on/)
  assert.match(About.PRIVACY, /~\/\.config\/omarchy\/shell\.json/)
  // wttr.in is the only host any script or QML file talks to.
  const hosts = new Set()
  for (const dir of [".", "bin"]) {
    for (const f of fs.readdirSync(path.join(ROOT, dir))) {
      if (!/\.(qml|js|sh)$/.test(f)) continue
      for (const m of fs.readFileSync(path.join(ROOT, dir, f), "utf8").matchAll(/https?:\/\/([^/"'\s$]+)/g)) hosts.add(m[1])
    }
  }
  assert.deepEqual([...hosts], ["wttr.in"])
})

test("mailto prefills subject and version details", () => {
  const v = { quickshell: "0.3.1", qt: "6.11.2", omarchy: "4.0.4-1" }
  const details = About.details("1.2.0", v, "Hyprland")
  assert.equal(details, "Theme Rotate 1.2.0\nQuickshell 0.3.1, Qt 6.11.2, Omarchy 4.0.4-1\nHyprland")
  const url = About.mailto("1.2.0", details)
  assert.ok(url.startsWith("mailto:help@ninepointlabs.com?subject=Theme%20Rotate%201.2.0&body="))
  assert.equal(decodeURIComponent(url.split("&body=")[1]), "\n\n--\n" + details)
  assert.equal(About.builtWith({ quickshell: "", qt: "", omarchy: "" }), "Quickshell and Qt")
})

test("about-versions.sh reports each tool's version, and blanks for missing ones", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "theme-rotate-about-"))
  const stub = (name, body) => fs.writeFileSync(path.join(dir, name), "#!/bin/bash\n" + body + "\n", { mode: 0o755 })
  stub("quickshell", 'echo "Quickshell 9.8.7 (revision , distributed by Test)"')
  stub("qtpaths6", 'echo 6.99.1')
  stub("omarchy", '[[ $1 == version ]] && echo 5.0.0-1')
  const run = () => execFileSync(path.join(ROOT, "bin/about-versions.sh"), { encoding: "utf8", env: { ...process.env, PATH: dir + ":" + process.env.PATH } })
  assert.equal(run(), "9.8.7\t6.99.1\t5.0.0-1\n")
  assert.deepEqual(About.parseVersions(run()), { quickshell: "9.8.7", qt: "6.99.1", omarchy: "5.0.0-1" })
  stub("quickshell", "exit 1")
  stub("omarchy", "exit 1")
  assert.deepEqual(About.parseVersions(run()), { quickshell: "", qt: "6.99.1", omarchy: "" })
  fs.rmSync(dir, { recursive: true, force: true })
})

test("the panel only looks up the sun while Follow the sun is on", () => {
  const panel = fs.readFileSync(path.join(ROOT, "Panel.qml"), "utf8")
  const fn = panel.match(/function refreshSun\(\) \{([\s\S]*?)\n  \}/)
  assert.ok(fn, "refreshSun() not found")
  const body = fn[1]
  const guard = body.indexOf("if (!root.followSun) return")
  assert.ok(guard >= 0, "refreshSun() must return early when followSun is off")
  assert.ok(guard < body.indexOf("sunProc.running = true"), "the guard must come before starting sunProc")
  // sunProc is the only thing that runs sun-status.sh from the panel.
  assert.equal(panel.match(/sunProc\.running = true/g).length, 1)
})
