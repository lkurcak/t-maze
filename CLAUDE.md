# t-maze

A terminal maze game written in T, the language at `~/repos/tooling/t-lang`
(GitHub: lkurcak/t-lang). Like tcalc, t-libs and t-nonograms, part of its
purpose is to find out what using T is like, here for an interactive,
animated program over t-libs' `graph` and `grid` (and `term` for keys
and the other screen, `rand` for random numbers).

- `main.t` is the program's root: the command line, and text output when
  it isn't on a terminal. Modules: `maze` (`Maze`, Kruskal + union-find,
  `graph()`), `search` (the graph's searches as `Found`), `draw` (the
  picture, in colour or as text), `play` (the game: raw mode, the other
  screen, frames), `keys` (what each key does).
- Nothing in it panics: `#![warn(implicit_panics)]` with `--deny-warnings`.
  Keep it so; a test may `#[allow(implicit_panics)]`.
- `tests/run.sh` runs what CI runs: `t check --deny-warnings`, `t fmt
  --check`, `t test`, the text transcript of `tests/expected.txt` both
  interpreted and compiled, and `tests/terminal.py` (needs python3), which plays
  the compiled game on a pseudo-terminal. `BLESS=1` rewrites the expected
  transcript. The interpreted transcript takes a while.
- CI pins a `t` release (`t-version` + `t-sha256` in .github/workflows/t.yml,
  which calls forge's shared t-ci.yml); bump both after a t-lang release.
  t-libs is a git dependency pinned by `rev` in `t.toml`.
- `FRICTION.md` is the friction log: label entries gap / by design / unsure
  / works, with the code that hit them. It's evidence for t-lang steps,
  planned in t-lang, not here. Don't change t-lang from here.
- `git` over ssh doesn't work in Claude's shell: push and fetch through
  `origin` with `-c url."https://github.com/".insteadOf=git@github.com:
  -c credential.helper='!gh auth git-credential'`.
