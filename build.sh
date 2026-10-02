#!/bin/zsh
set -eu
cd "${0:A:h}"
make -C Vendor/m1ddc
app="build/Voice.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
# A local VFS overlay avoids a stale duplicate module map in this host's CLT.
# The installed toolchain and SDK files remain untouched.
python3 scripts/compiler-overlay.py
xcrun clang -O2 -target arm64-apple-macosx14.2 -std=c11 -c Sources/AudioDSP.c -o build/AudioDSP.o
xcrun swiftc -O -target arm64-apple-macosx14.2 \
  -vfsoverlay "$PWD/build/compiler-overlay.json" \
  -Xcc -ivfsoverlay -Xcc "$PWD/build/compiler-overlay.json" \
  -module-cache-path "$PWD/build/module-cache" \
  -import-objc-header Sources/AudioDSP.h \
  -parse-as-library Sources/Domain.swift Sources/SingleInstanceLock.swift Sources/AudioVolumeEngine.swift Sources/App.swift build/AudioDSP.o \
  -framework AppKit -framework SwiftUI -framework CoreAudio -framework ApplicationServices \
  -o "$app/Contents/MacOS/Voice"
cp Vendor/m1ddc/m1ddc "$app/Contents/Helpers/m1ddc"
cp Vendor/m1ddc/LICENSE "$app/Contents/Resources/m1ddc-LICENSE.txt"
cp Info.plist "$app/Contents/Info.plist"
./scripts/build-icon.sh
cp build/Voice.icns "$app/Contents/Resources/Voice.icns"
cp Assets/VoiceIcon.png "$app/Contents/Resources/VoiceIcon.png"
cp LICENSE "$app/Contents/Resources/Voice-LICENSE.txt"
codesign --force --sign - "$app/Contents/Helpers/m1ddc"
codesign --force --sign - "$app"
print "已构建：${PWD}/$app"
