#!/bin/sh
# Checks t-maze: it type-checks with no warnings (so nothing in it can
# panic: main.t asks for `implicit_panics`), it's formatted, its tests
# pass, its output for the mazes below is tests/expected.txt, and the game
# plays on a terminal (tests/terminal.py). Run from anywhere; `t` must be on
# PATH, and python3, for the terminal.
# BLESS=1 rewrites tests/expected.txt with what it writes now.
set -eu
cd "$(dirname "$0")/.."

t check --deny-warnings main.t
t fmt --check ./*.t
t test --deny-warnings main.t

# What it writes when its output isn't a terminal: mazes from fixed seeds,
# as text, and what it says to command lines it can't use.
transcript() {
    for args in "12 6 42" "20 8 5" "1 1 7" "5 1 9" "0 4 1" "3 x" "1 2 3 4"; do
        echo "\$ maze $args"
        # shellcheck disable=SC2086 # each word of $args is an argument
        "$@" $args < /dev/null 2>&1
    done
}

# `t main.t` compiles the game; `--interp` runs it in the interpreter,
# which checks as it goes what the checker proved.
if [ "${BLESS:-}" = 1 ]; then
    transcript t --interp main.t > tests/expected.txt
    echo "wrote tests/expected.txt"
    exit 0
fi

transcript t --interp main.t > tests/actual.txt
if ! diff -u tests/expected.txt tests/actual.txt; then
    echo "FAIL: output differs from tests/expected.txt"
    exit 1
fi

# Compiled through C, as `t main.t` runs it, it must do just what the
# interpreter does; and play on a terminal.
t build -o tests/maze main.t
transcript tests/maze > tests/actual.txt
if ! diff -u tests/expected.txt tests/actual.txt; then
    echo "FAIL: the compiled game's output differs from tests/expected.txt"
    exit 1
fi
python3 -I tests/terminal.py tests/maze
rm tests/actual.txt tests/maze
echo "ok"
