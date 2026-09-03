# Bundled libraries

Vendored rather than required as separate installs, so the addon is one folder
to drop in. All three are pure Lua: they perform string and arithmetic work and
touch no game API, so a WoW patch cannot break them. That is why they do not
count against the isolation principle in DESIGN.md, which is about code that
reads game state.

| Library      | Purpose                                  | Licence       |
| ------------ | ---------------------------------------- | ------------- |
| LibStub      | Library versioning stub                  | Public domain |
| LibDeflate   | DEFLATE compression, print-safe encoding | zlib          |
| LibSerialize | Table serialisation                      | MIT           |

Unmodified upstream copies. LibSerialize deserialises a binary format rather
than evaluating Lua, so an import string cannot execute code.
