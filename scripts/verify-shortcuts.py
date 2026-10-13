#!/usr/bin/env python3
"""Replay native key events through GlobalShortcuts without posting OS events."""
import argparse
import platform
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--log", type=Path)
args = parser.parse_args()
work = root / ".build/shortcuts"
work.mkdir(parents=True, exist_ok=True)
source = (root / "Sources/HydayTalk/GlobalShortcuts.swift").read_text()
# Reproduce a session key-state snapshot lagging behind the incoming event.
# The event's own flags are preserved; no real keys, audio or permissions change.
source = source.replace("CGEventSource.keyState(.combinedSessionState, key: 56)", "false")
source += """
extension GlobalShortcuts {
    func replay(type: CGEventType, code: UInt16, flags: CGEventFlags, repeated: Bool = false) -> Bool {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: type != .keyUp)!
        event.type = type; event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeated ? 1 : 0)
        return handle(type: type, event: event) == nil
    }
}
"""
adapter = work / "GlobalShortcuts+Replay.swift"
adapter.write_text(source)
bin_dir = Path(subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=root, text=True).strip())
command = ["swiftc", "-parse-as-library", "-target", f"{platform.machine()}-apple-macosx14.0",
           "-I", str(bin_dir / "Modules"), str(adapter),
           str(root / "scripts/fixtures/shortcuts/Probe.swift")]
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
