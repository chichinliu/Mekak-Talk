#!/usr/bin/env python3
"""Exercise actual AppModel begin/finish code with isolated OS boundaries."""
import argparse
import platform
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--log", type=Path)
args = parser.parse_args()
work = root / ".build/app-flow"
work.mkdir(parents=True, exist_ok=True)
source = (root / "Sources/HydayTalk/AppModel.swift").read_text()
# Only the OS permission boundary is overridden in this disposable source copy.
# Recording, processing, clipboard fallback, cancellation and state transitions
# remain the actual AppModel implementation.
boundary = "    func refreshPermissions() {\n"
assert source.count(boundary) == 1
source = source.replace(boundary, boundary + """        if FlowEnvironment.isolatedPermissions {
            microphoneAllowed = true; speechAllowed = true
            accessibilityAllowed = true; shortcutReady = true
            return
        }
""", 1)
source += """
extension AppModel {
    func configureForFlow(autoInsert: Bool = true) {
        var configured = TalkSettings()
        configured.speechBackend = .system
        configured.textBackend = .basic
        configured.autoInsert = autoInsert
        configured.saveHistory = true
        configured.interactionSounds = false
        settings = configured
    }
    func primeForFlow(action: VoiceAction = .dictate, autoInsert: Bool = true) {
        configureForFlow(autoInsert: autoInsert)
        sessionSettings = settings
        self.action = action; target = TextInsertion.capturedTarget
        sessionID = UUID(); started = Date()
        result = ""; notice = ""; phase = .recording
    }
}
"""
model = work / "AppModel+Flow.swift"
model.write_text(source)
bin_dir = Path(subprocess.check_output(
    ["swift", "build", "--show-bin-path"], cwd=root, text=True).strip())
fixtures = root / "scripts/fixtures/app-flow"
command = [
    "swiftc", "-parse-as-library",
    "-target", f"{platform.machine()}-apple-macosx14.0",
    "-I", str(bin_dir / "Modules"),
    str(model), str(fixtures / "Dependencies.swift"), str(fixtures / "Probe.swift"),
]
command += [str(path) for path in (bin_dir / "TalkCore.build").glob("*.swift.o")]
command += ["-o", str(work / "probe")]
subprocess.run(command, cwd=root, check=True)
result = subprocess.run([str(work / "probe")], cwd=root, text=True, capture_output=True)
output = result.stdout + result.stderr
if args.log:
    args.log.parent.mkdir(parents=True, exist_ok=True)
    args.log.write_text(output)
print(output, end="")
sys.exit(result.returncode)
