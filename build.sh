#!/bin/zsh
# Hark — build, sign, install and package.
# Requires only Xcode Command Line Tools. No Xcode, no dependencies.
#
# The German-named .command files next to this one are the same thing,
# double-clickable from Finder. This is the entry point for everyone else.

exec "$(dirname "$0")/HARK BAUEN.command"
