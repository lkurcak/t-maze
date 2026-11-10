# t-maze

Find the way out of a maze, and watch two searches find it. A terminal
game written in [T](https://github.com/lkurcak/t-lang), partly to find out
what writing an interactive program in T is like, and to use t-libs'
[graph](https://github.com/lkurcak/t-libs/tree/main/graph). What got in the
way is in [FRICTION.md](FRICTION.md).

```text
$ maze 12 6 42 > maze.txt
A maze 12 squares wide and 6 high, from seed 42.
#########################
#@#~  #ooooO#OoooOOOOO# #
#o#~# #o# #o#o###~###o# #
#OOOoooo# #ooo# #~~~#ooo#
#~##### ### ### ### # #o#
...
```

You start in the top left corner; the way out is in the bottom right. Some
squares are mud (brown, or `~` as text): stepping onto one takes 4, and
onto any other square 1. So the way with the fewest steps isn't always the
quickest.

On a terminal, the maze fills it:

- the arrow keys, or `hjkl`, walk;
- `b` shows a breadth-first search spreading out from where you are, the
  edge it's got to in cyan, until it reaches the way out, and then the way
  with the fewest steps, in gold (orange through mud);
- `d` does the same with Dijkstra's algorithm, which finds the quickest
  way: it spreads more slowly through mud;
- `n` is a new maze, and `q`, Escape or Ctrl-C stops.

Once you're out, it says how long you took, against the quickest way.

`maze [WIDTH HEIGHT [SEED]]`: a maze of that many squares, from that seed,
the same each time; with no seed, a new one each run; with no size, as big
as the terminal. When its output isn't a terminal, it writes the maze as
text, with the way with the fewest steps, and the quickest.

Nothing in it can panic: `main.t` asks for the `implicit_panics` lint, and
the checker proves every index and every bit of arithmetic in range.

## How it works

- `maze.t`: the maze, a `Grid` (t-libs) of squares, each knowing whether
  there's a passage east and south. It's made by Kruskal's algorithm: the
  walls in a random order, each knocked down if it's between two parts not
  yet joined, which a union-find keeps track of; then a few more walls come
  down (`LOOPS`, 8 in a hundred), so there's sometimes more than one way.
  Mud comes in patches. `graph()` gives the maze as a t-libs `Graph`, a
  node for each square and an edge each way along each passage, its value
  what stepping onto the square it goes to takes.
- `search.t`: the graph's `distances` (Dijkstra) and `shortest_path` /
  `cheapest_path`: how far each square is, in steps or in time, and the way.
  The fewest steps are Dijkstra's with each step counting 1, which is what
  a breadth-first search finds.
- `draw.t`: the picture, `2 * width + 1` places by `2 * height + 1`, each
  square, wall or passage two characters wide in colour, or one as text.
- `play.t`: the game. The terminal's in raw mode (`std::io::Raw`) and on
  its other screen (t-libs' `term::Screen`), which goes back when it's
  dropped; a search
  spreads over 60 frames 30 ms apart, `raw.wait(deadline)` waiting for the
  next frame or a key, whichever comes first.
- `keys.t`: what the keys do; t-libs' `term` reads them, arrows included.
  Random numbers are t-libs' `rand`.

## Running it

```sh
t main.t              # compile through C, and play
t main.t 30 15 7      # a 30 by 15 maze, from seed 7
t build -o maze main.t
```

`tests/run.sh` runs what CI runs: `t check --deny-warnings`, `t fmt
--check`, `t test`, the text output for a few mazes against
`tests/expected.txt` (interpreted and compiled), and `tests/terminal.py`, which
plays the compiled game on a pseudo-terminal and checks the terminal's put
back as it was. `BLESS=1 tests/run.sh` rewrites the expected output.
