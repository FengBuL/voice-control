"""Exercise real app launches without enabling audio capture.

Run after build.sh with no Voice instance running. Existing audio unit tests
cover DSP; this check only opens the menu bar and tests process handoff.
"""
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

root = Path(__file__).resolve().parent.parent
app = root / "build/Voice.app"
binary = app / "Contents/MacOS/Voice"


def launch(executable):
    return subprocess.Popen(
        [str(executable), "--smoke-test"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )


def result(process):
    output, _ = process.communicate(timeout=10)
    assert process.returncode == 0, output
    return output


processes = []
try:
    with tempfile.TemporaryDirectory(prefix="voice-instance-test-", dir=root / "build") as temporary:
        copied_app = Path(temporary) / "Voice.app"
        shutil.copytree(app, copied_app)
        copied_binary = copied_app / "Contents/MacOS/Voice"
        primary = launch(binary)
        processes.append(primary)
        time.sleep(1)
        assert primary.poll() is None, "Quit the existing Voice before running this check"
        duplicates = [launch(executable) for executable in [binary, copied_binary, binary, copied_binary]]
        processes.extend(duplicates)
        for duplicate in duplicates:
            assert "already running" in result(duplicate)
        assert primary.poll() is None, "The original process must remain running"
        subprocess.run(["open", str(app)], check=True, timeout=5)
        output = result(primary)
        assert "REOPEN: source=another-process, panel=true" in output, output
        assert "REOPEN: source=launch-services, panel=true" in output, output
        assert "SMOKE:" in output, output
        print("App checks passed: repeated launch, copied app, existing panel and Finder reopen.")

        racers = [launch(executable) for executable in [binary, copied_binary, binary, copied_binary]]
        processes.extend(racers)
        outputs = [result(process) for process in racers]
        assert sum("SMOKE:" in output for output in outputs) == 1, outputs
        assert sum("already running" in output for output in outputs) == 3, outputs
        print("Simultaneous launch check passed: exactly one primary process.")
finally:
    for process in processes:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
