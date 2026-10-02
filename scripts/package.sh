#!/bin/zsh
set -eu
cd "${0:A:h:h}"
./build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
artifact="Voice-${version}-macOS-arm64"
stage="build/dmg-stage"
# Only remove this script's disposable staging directory.
python3 - <<'PY'
from pathlib import Path
import shutil
stage = Path('build/dmg-stage')
if stage.exists():
    shutil.rmtree(stage)
stage.mkdir(parents=True)
PY
mkdir -p release
ditto build/Voice.app "$stage/Voice.app"
ln -s /Applications "$stage/Applications"
cp docs/INSTALL.txt "$stage/Read Me.txt"
ditto -c -k --sequesterRsrc --keepParent build/Voice.app "release/$artifact.zip"
hdiutil create -volname "Voice $version" -srcfolder "$stage" -format UDZO -ov "release/$artifact.dmg"
cp docs/INSTALL.txt "release/INSTALL.txt"
(cd release && shasum -a 256 "$artifact.dmg" "$artifact.zip" > SHA256SUMS.txt)
codesign --verify --deep --strict build/Voice.app
print "安装包：${PWD}/release/$artifact.dmg"
