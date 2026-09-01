#!/bin/sh
# Runs the pure-Lua tests. The data model and the length guard touch no WoW API,
# so they are testable outside the game — which matters, because everything that
# does touch the API can only be verified by loading the addon in a live client.
set -e
cd "$(dirname "$0")/.."
for f in MythicMacros/*.lua MythicMacros/Libs/*/*.lua; do luac5.1 -p "$f"; done
echo "syntax ok"
lua5.1 tests/util_test.lua
lua5.1 tests/core_test.lua
lua5.1 tests/export_test.lua
