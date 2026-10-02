#!/bin/zsh
set -eu
cd "${0:A:h}"
python3 scripts/compiler-overlay.py
xcrun swiftc -target arm64-apple-macosx13.0 \
  -vfsoverlay "$PWD/build/compiler-overlay.json" \
  -Xcc -ivfsoverlay -Xcc "$PWD/build/compiler-overlay.json" \
  -module-cache-path "$PWD/build/module-cache" \
  -parse-as-library Sources/Domain.swift Tests/DomainTests.swift -o build/DomainTests
./build/DomainTests
xcrun swiftc -target arm64-apple-macosx14.2 \
  -vfsoverlay "$PWD/build/compiler-overlay.json" \
  -Xcc -ivfsoverlay -Xcc "$PWD/build/compiler-overlay.json" \
  -module-cache-path "$PWD/build/module-cache" \
  -parse-as-library Sources/SingleInstanceLock.swift Tests/SingleInstanceTests.swift -o build/SingleInstanceTests
./build/SingleInstanceTests
xcrun clang -fmodules -I Vendor/m1ddc/headers Tests/DDCPacketTests.m \
  Vendor/m1ddc/sources/i2c.m -framework Foundation -framework CoreDisplay -o build/DDCPacketTests
./build/DDCPacketTests
xcrun clang -std=c11 -I Sources Tests/AudioDSPTests.c Sources/AudioDSP.c -o build/AudioDSPTests
./build/AudioDSPTests
