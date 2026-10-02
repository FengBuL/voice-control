import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
build = root / "build"
build.mkdir(exist_ok=True)
(build / "empty.modulemap").write_text("// Empty replacement for a stale duplicate SwiftBridging map.\n")
include = Path("/Library/Developer/CommandLineTools/usr/include/swift")
roots = []
if (include / "module.modulemap").exists() and (include / "bridging.modulemap").exists():
    roots.append({"type": "file", "name": str(include / "module.modulemap"),
                  "external-contents": str(build / "empty.modulemap")})
(build / "compiler-overlay.json").write_text(json.dumps({"version": 0, "roots": roots}))
