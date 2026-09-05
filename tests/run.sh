#!/bin/sh
# Runs the pure-Lua tests. The data model and the length guard touch no WoW API,
# so they are testable outside the game — which matters, because everything that
# does touch the API can only be verified by loading the addon in a live client.
set -e
cd "$(dirname "$0")/.."
for f in InomrahsMythicInstructions/*.lua InomrahsMythicInstructions/Libs/*/*.lua; do luac5.1 -p "$f"; done
echo "syntax ok"
lua5.1 tests/color_test.lua
lua5.1 tests/util_test.lua
lua5.1 tests/history_test.lua
lua5.1 tests/core_test.lua
lua5.1 tests/export_test.lua
lua5.1 tests/sheet_test.lua
lua5.1 tests/starter_test.lua
lua5.1 tests/binds_test.lua
lua5.1 tests/ui_test.lua
lua5.1 tests/layout_test.lua
lua5.1 tests/sweep_test.lua
lua5.1 tests/runlab_test.lua

# The self-test's manifest is generated from the addon. Out of date, the in-game
# checks run against a list that no longer describes the addon — the one failure
# mode a generated file exists to remove.
lua5.1 tools/manifest.lua --check

# The manifest is only worth generating if the self-test actually reads it. It
# once shipped generated, listed in the .toc, and unused, because a hand-written
# list it replaced was restored by a stray git checkout — and everything still
# passed, because a stale list of nineteen names looks exactly like a fresh one.
if ! grep -q "InomrahsMISelfTestManifest" InomrahsMISelfTest/SelfTest.lua; then
    echo "  FAIL: the self-test does not read its manifest."
    exit 1
fi
if ! grep -q "^Manifest.lua" InomrahsMISelfTest/InomrahsMISelfTest.toc; then
    echo "  FAIL: Manifest.lua is not loaded by the self-test's .toc."
    exit 1
fi
echo "self-test reads its manifest"
