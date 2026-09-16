#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}/.."
mkdir -p .build
xcrun swiftc Mac/Server.swift Mac/EventSource.swift Mac/main.swift -o .build/tars-server
exec .build/tars-server "$@"
