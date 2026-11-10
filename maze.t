//! A maze: a grid of squares with passages between some neighbours. It
//! starts as a perfect one, where from any square to any other there's
//! exactly one way that doesn't go back on itself; then a few more walls
//! come down, so there's sometimes more than one. Some squares are mud,
//! which takes longer to cross, so the way with the fewest steps isn't
//! always the quickest.

use alloc::list::List;
use core::ops::Range;
use graph::Graph;
use grid::Grid;

use rand::Rng;

/// A square: is there a passage from it to the square east of it, and to
/// the one south of it? And is it mud?
#[derive(Copy, Discard)]
pub struct Square { pub east: bool, pub south: bool, pub mud: bool }

/// How long stepping onto a square of mud takes, counting a step onto one
/// that isn't as 1.
pub const MUD: u64 = 4;

/// A way to go from a square: to one of its four neighbours.
#[derive(Copy, Discard, Eq)]
pub enum Dir { Up, Down, Left, Right }

/// A maze, at least one square wide and one high. You start in the top
/// left corner, and the way out is in the bottom right one.
#[derive(Discard)]
pub struct Maze { squares: { g: Grid<Square> | g.width() > 0 && g.height() > 0 } }

impl Maze {
    /// A maze `width` squares wide and `height` high, from `rng`, with
    /// about `loops` passages in a hundred more than a perfect maze has;
    /// or `None` if it would have more squares than a `usize` counts.
    pub fn new(
        rng: &mut Rng,
        width: { w: usize | w > 0 },
        height: { h: usize | h > 0 },
        loops: { l: u64 | l <= 100 },
    ) -> Option<{ m: Maze | m.width() == width && m.height() == height }> with alloc {
        let blank = Square { east: false, south: false, mud: false };
        let mut squares = Grid::new(width, height, blank)?;
        let n: { n: usize | n == width * height } = squares.cells().len();
        // Kruskal's algorithm: take the walls in a random order, and knock
        // each down that's between two parts not yet joined, until there's
        // one part. Then the squares are a tree, joined by passages: a
        // perfect maze. A wall is the squares it's between, by number, and
        // whether the second is east of the first, or south of it.
        let mut walls: List<({ a: usize | a < n }, { b: usize | b < n }, bool)> = List::new();
        for y in 0..height {
            for x in 0..width {
                let a = number(width, height, n, x, y);
                if x + 1 < width {
                    walls.push((a, number(width, height, n, x + 1, y), true));
                }
                if y + 1 < height {
                    walls.push((a, number(width, height, n, x, y + 1), false));
                }
            }
        }
        rng.shuffle(walls.as_mut_slice());
        let mut parts = Parts::new(n);
        for wall in walls.iter() {
            let (a, b, east) = *wall;
            if parts.join(a, b) || rng.chance(loops) {
                let x = squares.x_of(a);
                let y = squares.y_of(a);
                let mut s = *squares.get(x, y);
                if east {
                    s.east = true;
                } else {
                    s.south = true;
                }
                squares.set(x, y, s);
            }
        }
        // Mud, in patches about three squares across, one for each 16
        // squares or so; but not where you start, or at the way out.
        for _ in 0..n / 16 {
            let cx = rng.below(width);
            let cy = rng.below(height);
            for y in around(cy, height) {
                for x in around(cx, width) {
                    if rng.chance(75) {
                        let mut s = *squares.get(x, y);
                        s.mud = true;
                        squares.set(x, y, s);
                    }
                }
            }
        }
        let mut s = *squares.get(0, 0);
        s.mud = false;
        squares.set(0, 0, s);
        let mut s = *squares.get(width - 1, height - 1);
        s.mud = false;
        squares.set(width - 1, height - 1, s);
        Some(Maze { squares })
    }

    /// How many squares wide it is.
    #[measure]
    pub fn width(&self) -> usize { self.squares.width() }

    /// How many squares high it is.
    #[measure]
    pub fn height(&self) -> usize { self.squares.height() }

    /// The square in column `x` of row `y`.
    pub fn square(
        &self,
        x: { x: usize | x < self.width() },
        y: { y: usize | y < self.height() },
    ) -> Square { *self.squares.get(x, y) }

    /// How many squares it has.
    pub fn squares(&self) -> { n: usize | n == self.width() * self.height() } {
        self.squares.cells().len()
    }

    /// The number of the square in column `x` of row `y`: they're numbered
    /// row by row, `y * width() + x`, as the graph's nodes are.
    pub fn number(
        &self,
        x: { x: usize | x < self.width() },
        y: { y: usize | y < self.height() },
    ) -> { v: usize | v < self.width() * self.height() } {
        number(self.width(), self.height(), self.squares(), x, y)
    }

    /// The column and row of square number `v`.
    pub fn place(
        &self,
        v: { v: usize | v < self.width() * self.height() },
    ) -> ({ x: usize | x < self.width() }, { y: usize | y < self.height() }) {
        (self.squares.x_of(v), self.squares.y_of(v))
    }

    /// The number of the square where you start, the top left: 0.
    pub fn start(&self) -> { v: usize | v < self.width() * self.height() } { self.number(0, 0) }

    /// The number of the square where the way out is, the bottom right.
    pub fn exit(&self) -> { v: usize | v < self.width() * self.height() } {
        self.number(self.width() - 1, self.height() - 1)
    }

    /// How long stepping onto the square in column `x` of row `y` takes.
    pub fn cost(
        &self,
        x: { x: usize | x < self.width() },
        y: { y: usize | y < self.height() },
    ) -> u64 {
        if self.square(x, y).mud { MUD } else { 1 }
    }

    /// The square one step from column `x` of row `y` in direction `d`,
    /// if there's a passage to it.
    pub fn step(
        &self,
        x: { x: usize | x < self.width() },
        y: { y: usize | y < self.height() },
        d: Dir,
    ) -> Option<({ x: usize | x < self.width() }, { y: usize | y < self.height() })> {
        let open = match d {
            Dir::Up => y > 0 && self.square(x, y - 1).south,
            Dir::Down => y + 1 < self.height() && self.square(x, y).south,
            Dir::Left => x > 0 && self.square(x - 1, y).east,
            Dir::Right => x + 1 < self.width() && self.square(x, y).east,
        };
        if !open {
            return None;
        }
        Some(match d {
            Dir::Up => (x, y - 1),
            Dir::Down => (x, y + 1),
            Dir::Left => (x - 1, y),
            Dir::Right => (x + 1, y),
        })
    }

    /// The maze as a graph: a node for each square, numbered row by row,
    /// so the square in column `x` of row `y` is node `y * width() + x`,
    /// and an edge each way along each passage, whose value is how long
    /// stepping onto the square it goes to takes.
    pub fn graph(&self) -> { g: Graph<(), u64> | g.node_count() == self.width() * self.height() }
    with alloc
    {
        let n = self.squares.cells().len();
        let mut g = Graph::new();
        let mut i: usize = 0;
        while i < n invariant g.node_count() == i && i <= n {
            let _ = g.add_node(());
            i = i + 1;
        }
        let w = self.width();
        let h = self.height();
        for y in 0..h {
            for x in 0..w {
                let s = self.square(x, y);
                let v = number(w, h, n, x, y);
                // A square on the east edge has no passage east, nor one on
                // the south edge south; but the checker can't know that of
                // `s`, which doesn't know where it is.
                if s.east && x + 1 < w {
                    let e = number(w, h, n, x + 1, y);
                    g.add_edge(v, e, self.cost(x + 1, y));
                    g.add_edge(e, v, self.cost(x, y));
                }
                if s.south && y + 1 < h {
                    let b = number(w, h, n, x, y + 1);
                    g.add_edge(v, b, self.cost(x, y + 1));
                    g.add_edge(b, v, self.cost(x, y));
                }
            }
        }
        g
    }
}

/// The number of the square in column `x` of row `y` of a maze `width`
/// squares wide and `height` high, which has `n` squares: they're
/// numbered row by row.
fn number(
    width: usize,
    height: usize,
    n: { n: usize | n == width * height },
    x: { x: usize | x < width },
    y: { y: usize | y < height },
) -> { a: usize | a < n } { y * width + x }

/// The numbers from one less than `c` to one more, that are less than
/// `n`.
fn around(c: usize, n: { n: usize | c < n }) -> { r: Range<usize> | r.end() <= n } {
    let start = if c > 0 { c - 1 } else { 0 };
    let end = if c + 1 < n { c + 2 } else { n };
    start..end
}

/// Squares joined into parts, as a forest: each square's parent, up to
/// the root of its tree, which is its own parent. Each parent is one of
/// the squares, so less than how many there are.
#[derive(Discard)]
struct Parts { parent: List<{ p: usize | p < parent.len() }> }

impl Parts {
    /// `n` squares, each a part of its own.
    fn new(n: usize) -> { p: Parts | p.len() == n } with alloc {
        let mut parent: List<{ p: usize | p < n }> = List::new();
        let mut i: usize = 0;
        while i < n invariant parent.len() == i && i <= n {
            parent.push(i);
            i = i + 1;
        }
        Parts { parent }
    }

    /// How many squares there are.
    #[measure]
    fn len(&self) -> usize { self.parent.len() }

    /// Joins the parts that squares `a` and `b` are in: `true` if they
    /// were apart, `false` if they were one part already.
    fn join(&mut self, a: { a: usize | a < self.len() }, b: { b: usize | b < self.len() }) -> bool
    ensures
        self.len() == old(self.len()),
    {
        let ra = self.root(a);
        let rb = self.root(b);
        if ra == rb {
            return false;
        }
        self.parent.set(ra, rb);
        true
    }

    /// The root of the tree that `v` is in. On the way it points each
    /// square it passes at its grandparent, halving the way, so the next
    /// look is quicker.
    fn root(&mut self, v: { v: usize | v < self.len() }) -> { r: usize | r < self.len() }
    ensures
        self.len() == old(self.len()),
    {
        let n = self.len();
        let mut v: { v: usize | v < n } = v;
        while self.parent[v] != v {
            let up = self.parent[self.parent[v]];
            self.parent.set(v, up);
            v = up;
        }
        v
    }
}

/// Mazes of a few sizes, from a few seeds, each with `loops` extra
/// passages in a hundred.
pub fn some(loops: { l: u64 | l <= 100 }) -> List<Maze> with alloc {
    let mut mazes = List::new();
    let mut rng = Rng::new(1);
    for (w, h) in [(1usize, 1usize), (1, 7), (7, 1), (2, 2), (9, 4), (20, 10)].iter() {
        if *w > 0 && *h > 0 {
            if let Some(m) = Maze::new(&mut rng, *w, *h, loops) {
                mazes.push(m);
            }
        }
    }
    mazes
}

/// How many passages `m` has.
#[allow(implicit_panics)]
fn passages(m: &Maze) -> usize {
    let mut n: usize = 0;
    for s in m.squares.iter() {
        if s.east {
            n = n + 1;
        }
        if s.south {
            n = n + 1;
        }
    }
    n
}

#[test]
fn every_square_is_reached() {
    for m in some(8).iter() {
        assert_eq(&m.graph().breadth_first(m.start()).len(), &m.squares());
    }
}

#[allow(implicit_panics)]
#[test]
fn without_loops_it_is_perfect() {
    // A tree with `n` nodes has `n - 1` edges: a passage fewer would leave
    // a square out; one more would make a second way somewhere.
    for m in some(0).iter() {
        assert_eq(&(passages(m) + 1), &m.squares());
        assert_eq(&m.graph().breadth_first(m.start()).len(), &m.squares());
    }
}

#[test]
fn the_edges_are_walls() {
    for m in some(50).iter() {
        for y in 0..m.height() {
            assert(!m.square(m.width() - 1, y).east);
        }
        for x in 0..m.width() {
            assert(!m.square(x, m.height() - 1).south);
        }
    }
}

#[test]
fn start_and_way_out_are_not_mud() {
    for m in some(8).iter() {
        assert(!m.square(0, 0).mud);
        assert(!m.square(m.width() - 1, m.height() - 1).mud);
    }
}
