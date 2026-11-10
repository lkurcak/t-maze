# Friction log

What got in the way of writing a terminal maze game in T, with the code
that hit it. Each entry is labelled:

- **gap**: T should have it;
- **by design**: T leaves it out on purpose, and the entry says what that
  costs here;
- **unsure**: not clear which;
- **works**: something that went better than expected.

The log is evidence for t-lang's plans, not a design for them.

Written against `t` 0.76.0, the first release with refinements inside
type arguments of any type (`List<{ p: usize | p < n }>`), which most of
this program leans on. Entries say what 0.77.0 fixed.

## The checker takes minutes on one method — gap

**Fixed in t 0.77.0** (t-lang step 61: backjumping, facts said once,
carried refinements flattened). `Game::search` is one method again, and
the whole program checks in about half a second.

`play.t`'s `Game::search` was first one method: search, then a loop that
draws a frame and waits for the next or a key, which `break`s; then
`self.found = Some(found)`. `t check` didn't finish in minutes. Split in
two, the loop in `spread`, which only reads, the whole program checks in
about 2 s.

A program of 90 lines shows it growing (the first under *Repros* below: a
`Game` whose fields are refined by `board.width() * board.height()`, a
`while` that passes `Some(&found)` to a function and can `break`, and the
store after). With two such fields it checks in 1.1 s, with three in 4.4
s, with four in 20 s: about 4 times as long for each. Without the store, or
the `break`, or the call, it's 0.25 s. Something there, maybe joining the
loop's two exits, is exponential in the facts that mention the product.

## An enum of refined pairs: 512 cases, or two minutes — gap

**Fixed in t 0.77.0**: the repro below checks in a quarter of a second,
with the extra facts too. The maze still numbers its squares, which is
what the union-find works on anyway.

Kruskal's algorithm wants the walls in one list, to shuffle. A wall is
east or south of a square, and which squares can have one differs:

```text
let mut walls: List<
    Wall<
        ({ x: usize | x + 1 < width }, { y: usize | y < height }),
        ({ x: usize | x < width }, { y: usize | y + 1 < height }),
    >,
> = List::new();
...
for wall in walls.iter() {
    match *wall {
        East((x, y)) => .. need(width, x + 1) ..
```

`x + 1` failed: "the proof exceeded the solver's limit of 512 cases". With
`width > 0`, `height > 0` and `n == width * height` known too, `t check`
took 118 s to fail. The same pairs in a list of tuples, or an enum of
single numbers, are quick. Each element's knowledge seems to be a
disjunction over the variants, split again for each part.

The maze numbers its squares instead (`y * width + x`) and keeps each
wall as `(a, b, east)`: the two squares, both `< n`, and which way.

## A `&mut` to a refined list can't be lent to `set` — gap

**Fixed in t 0.77.0**: what a refined `&mut` points to, and a refined
`let`, are proved again after a call they're lent to straight, from what
it ensures; `push` fails with "can't prove `l.len() == n` for `*l` after
the call to `push`". `Parts` stays: it reads better.

The union-find was first two functions over a list:

```text
fn root(n: usize, parent: &mut { l: List<{ p: usize | p < n }> | l.len() == n }, ..)
    ...
    parent.set(v, up);
// error: can't prove `l.len() == n` of what `set` may write behind argument `self`
```

`set`, `replace`, `swap` and `l[v] = x` all fail the same way, though each
ensures `self.len() == old(self.len())`. The same list as a struct's
refined field is fine (step 30's call-scoped lends). A `&mut` to a refined
place is new in 0.76.0; its check of what a callee may write seems to use
only the callee's parameter type, not its postcondition.

What the maze does instead reads better anyway: a struct whose field is
refined by its own length.

```text
struct Parts { parent: List<{ p: usize | p < parent.len() }> }
```

## A product in scope breaks other proofs — gap

**Fixed in t 0.77.0**: a constraint whose numbers don't fit is left out
of a proof, not the end of it. `number()` stays, as the name of the
numbering.

```text
for y in 0..height {
    for x in 0..width {
        walls.push(y * width + x)      // into a List<{ a: usize | a < n }>
// note: the proof exceeded the solver's checked integer arithmetic range
```

with `n == width * height` known. The same with `x` and `y` parameters, or
with `while` loops and invariants (as t-libs' grid does), is proved. And
once that fact was in scope, `cy + 2` in a later, unrelated loop failed the
same way. `maze.t` has a function for it, `number(width, height, n, x, y)
-> { a: usize | a < n }`, whose own proof is quick.

## A pattern forgets a refined reference's refinement — gap

**Fixed in t 0.77.0**, the `for` head too: `draw::lights`' invariant no
longer says `n == f.squares` again.

```text
fn a(n: usize, found: Option<&{ f: Found | f.squares == n }>, ..) {
    let Some(f) = found else { return 0 };
    let k: { k: usize | k == n } = f.squares;   // error: can't prove `k == n`
```

`match &self.found { Some(f) => .. }`, with `found: Option<{ f: Found |
.. }>` a field, forgets it the same way; `self.found.as_ref()` keeps it
(a generic function, so step 55's free theorems). In `draw::lights` the
fact is known after the `let`, but the `for`'s head forgets it, so its
invariant says it again.

## Nothing, and an empty list, aren't known to hold nothing — gap

**Fixed in t 0.77.0**, through joins of branches and through a `let`
that declares a refinement of an empty list's elements.

```text
let found = match g.cheapest_path(from, to, |w| *w) {
    Some((_, way)) => Some(way),
    None => None,
};
let way: List<{ v: usize | v < g.node_count() }> = match found { .. }
// error: can't prove `v < g.node_count()` for `way`
```

The join of `Some(way)` with `None` forgets what's known of `way`'s
elements, as if `None` held any number. Declaring the type on one `let`,
and matching straight into it, works, so `search.t` does that. Likewise a
`let l: List<{ x: usize | x + 1 < w }> = List::new();` that's never pushed
to: iterating it, `*x + 1 < w` isn't known. (Pushed to in a loop, it is.)

## `let mut` forgets refinements — by design (docs/60)

Twice: `let mut v = v;` in `Parts::root`, which needs `v < n` for
`parent[v]` (written `let mut v: { v: usize | v < n } = v;`), and `let
mut rest = way.iter();`, to skip the first square of a way, whose items
then aren't nodes any more (written with the iterator's type in full).
t-lang's docs/60 says so: a `let mut` declares only what the type says.
(The second is `way.iter().skip(1)` since t 0.79.0, with no `let`.)

## A square can't know where it is — by design

A `Square` has `east` and `south`: is there a passage. The east column has
none east, and the bottom row none south, but nothing in the type says
so, so `graph()` and `draw::picture` check `x + 1 < w` again before using
the square east. Saying it would need a refinement over every element and
its index, which T doesn't have (quantified invariants were option C in
t-libs' graph findings).

## Small gaps

- No `Iterator::skip`: `let _ = rest.next();` before the `for`. 0.77.0
  has `skip`, but an iterator adapter doesn't carry what's known of its
  values (they come through `I::Item`), so `way.iter().skip(1)` gives
  squares that aren't known to be nodes: `search.t` still does it by hand.
  Fixed in t 0.79.0: adapters carry what a type argument says of their
  items, and `search.t` is `for v in way.iter().skip(1)`.
- No `saturating_add` for integers (`Duration` has one): `search::plus`.
  0.77.0 has `core::num::saturating_add`; `plus` is gone.
- An f-string is a `Display`, not a `&str`, so a function wanting a `&str`
  gets `String::of(&f"..").as_str()`. Fine, once known.
- No `#[cfg(test)]`: test helpers (`maze::some`, `passages`) are in the
  program. No warning says so, so it doesn't matter yet.
- `t fmt --check ./*.t | head` panics in `t` when `head` closes the pipe
  ("failed printing to stdout: Broken pipe"). Fixed in 0.77.0.
- No exit code: a bad command line prints usage to stderr and exits 0.

## A second copy of keys and random numbers — unsure (done: t-libs)

`keys.t` is t-nonograms' key reader again, with other keys, and `rng.t`
its SplitMix64. That's two programs with each: the rule of two says a
library now (t-libs: `term` for keys and the other-screen guard, `rand`
with `below(n) -> { r | r < n }`).

**Done** (t-libs `term` and `rand`): `keys.t` is only what each key does,
a `match` on `term::Key` (`Char('q') | Ctrl('c') | Escape => Quit`), and
`rng.t` is gone. `Maze::new`'s `loops` became `{ l: u64 | l <= 100 }`, as
`rand`'s `chance` asks; `LOOPS`, a `const`, is proved to be.

## What worked — works

- The searches are t-libs' graph's (`distances`, `shortest_path`,
  `cheapest_path`). Since 0.76.0, with paths refined too (t-libs #38, for
  this), the way's squares go back to the maze with no checks:
  `maze.place(*v)` takes `v < width * height`.
- Nothing in the program panics: `#![warn(implicit_panics)]` and
  `--deny-warnings`. What it took: `number()`, `around()` (the squares
  next to one, in range), `plus`, and drawing the top wall without
  `2 * w + 1`.
- `Parts`, the union-find, with parents refined by the list's own length,
  proved with no runtime checks, path halving and all.
- `raw.wait(deadline)` is exactly a frame loop: draw, then wait for the
  next frame or a key, whichever comes first; a key ends the animation at
  once. Deadlines from the start (`start.add(k * 30 ms)`) don't drift.
- A `Discard` guard for the terminal's other screen (`Screen`), dropped on
  every way out of `play`, `?` included, as `Raw` is for raw mode.
- `tests/terminal.py` plays the compiled game on a pseudo-terminal and
  checks the terminal's settings after are as before.

## Repros

Each checked with `t check` of 0.76.0, on its own.

The slow loop (4.4 s; add a fourth refined field to `Game`, 20 s):

```text
use alloc::list::List;

#[derive(Discard)]
struct Board { w: usize, h: usize }

impl Board {
    #[measure]
    fn width(&self) -> usize { self.w }
    #[measure]
    fn height(&self) -> usize { self.h }
}

#[derive(Discard)]
struct Graph { n: usize }

impl Graph {
    #[measure]
    fn count(&self) -> usize { self.n }
}

#[derive(Discard)]
struct Found { squares: usize, far: { f: List<Option<u64>> | f.len() == squares } }

#[derive(Discard)]
struct Game {
    board: Board,
    graph: { g: Graph | g.count() == board.width() * board.height() },
    you: { v: usize | v < board.width() * board.height() },
    steps: u64,
    found: Option<{ f: Found | f.squares == board.width() * board.height() }>,
}

fn look(
    b: &Board,
    f: Option<&{ f: Found | f.squares == b.width() * b.height() }>,
    upto: u64,
) -> { l: List<u8> | l.len() == b.width() * b.height() } with {alloc, panic} {
    let n = b.width() * b.height();
    let mut l = List::filled(n, 0u8);
    let Some(f) = f else { return l };
    for v in 0..n invariant l.len() == n && n == f.squares {
        if let Some(d) = f.far[v] {
            if d <= upto {
                l.set(v, 1);
            }
        }
    }
    l
}

fn ready(k: u64) -> Result<bool, u8> { if k == 99 { Err(1) } else { Ok(k % 7 == 3) } }

impl Game {
    fn run(
        &mut self,
        found: { f: Found | f.squares == self.board.width() * self.board.height() },
    ) -> Result<bool, u8> with {alloc, panic} {
        let top = found.far[self.you].unwrap_or(0);
        let mut k: u64 = 1;
        let mut go_on = true;
        while k <= 60 {
            let upto = match core::num::checked_mul(top, k) {
                Some(t) => t / 60,
                None => top,
            };
            let lit = look(&self.board, Some(&found), upto);
            let _ = lit.len();
            if ready(k)? {
                go_on = false;
                break;
            }
            k = k + 1;
        }
        self.found = Some(found);
        Ok(go_on)
    }
}

fn main() with {alloc, panic} {
    let mut g = Game {
        board: Board { w: 2, h: 2 },
        graph: Graph { n: 4 },
        you: 0,
        steps: 0,
        found: None,
    };
    let _ = g.run(Found { squares: 4, far: List::filled(4, None) });
}
```

The enum of refined pairs (512 cases); with `width`/`height` refined `> 0`
and an `n: { n: usize | n == width * height }` parameter, 118 s:

```text
use alloc::list::List;

#[derive(Copy, Discard)]
enum Wall<E, S> { East(E), South(S) }

fn need(n: usize, x: { x: usize | x < n }) -> usize { x }

fn f(width: usize, height: usize) -> usize with alloc {
    let mut walls: List<Wall<({ x: usize | x + 1 < width }, { y: usize | y < height }), ({ x: usize | x < width }, { y: usize | y + 1 < height })>> = List::new();
    for y in 0..height {
        for x in 0..width {
            if x + 1 < width {
                walls.push(Wall::East((x, y)));
            }
            
        }
    }
    let mut s: usize = 0;
    for wall in walls.iter() {
        match *wall {
            Wall::East((x, _)) => {
                s = need(width, x + 1);
            },
            Wall::South(_) => {},
        }
    }
    s
}

fn main() with alloc {
    let _ = f(2, 2);
}
```

A product in scope (exceeded the arithmetic range):

```text
use alloc::list::List;

fn need(n: usize, x: { x: usize | x < n }) -> usize { x }

fn h(width: usize, height: usize, n: { n: usize | n == width * height }) -> usize {
    let mut s = 0;
    for y in 0..height {
        for x in 0..width {
            s = need(n, y * width + x);
        }
    }
    s
}

fn k(width: usize, height: usize, n: { n: usize | n == width * height }, x: { x: usize | x < width }, y: { y: usize | y < height }) -> usize with alloc {
    let mut walls: List<{ a: usize | a < n }> = List::new();
    walls.push(y * width + x);
    walls.len()
}

fn main() with alloc {
    let _ = h(2, 2, 4);
    let _ = k(2, 2, 4, 0, 0);
}
```

A `&mut` to a refined list, and a pattern that forgets:

```text
use alloc::list::List;

fn f(n: usize, l: &mut { l: List<usize> | l.len() == n }, v: { v: usize | v < n }) {
    let _ = l.replace(v, 3);
}

fn k(l: &mut { l: List<usize> | l.len() == 4 }) {
    l.swap(0, 1);
}

fn main() {}
```

```text
use alloc::list::List;

#[derive(Discard)]
struct Found { squares: usize, far: { f: List<u64> | f.len() == squares } }

fn a(n: usize, found: Option<&{ f: Found | f.squares == n }>, v: { v: usize | v < n }) -> u64 {
    let Some(f) = found else { return 0 };
    let k: { k: usize | k == n } = f.squares;
    f.far[v]
}

fn main() with alloc {
    let x = Found { squares: 4, far: List::filled(4, 0) };
    let _ = a(4, Some(&x), 1);
}
```
