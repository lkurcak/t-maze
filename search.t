//! Searching the maze, as a graph, for the way from a square to the way
//! out: for the way with the fewest steps, as a breadth-first search finds
//! it, and for the quickest, mud and all, with Dijkstra's algorithm.

use alloc::list::List;
use core::num::saturating_add;
use graph::Graph;

use crate::maze::Maze;
use crate::maze::Dir;

/// Which way to look for.
#[derive(Copy, Discard, Eq)]
pub enum Kind {
    /// The one with the fewest steps, each counting the same, mud or not,
    /// as a breadth-first search finds it.
    Fewest,
    /// The quickest, a step onto mud taking longer: Dijkstra's algorithm.
    Quickest,
}

/// What a search of a maze of `squares` squares found.
#[derive(Discard)]
pub struct Found {
    pub kind: Kind,
    pub squares: usize,
    /// How far each square is from where the search started, by number:
    /// in steps, for the fewest, or in time, for the quickest; `None` for
    /// a square it doesn't reach, which in a maze there's none of.
    pub far: { f: List<Option<u64>> | f.len() == squares },
    /// The squares on the way it found, from where it started to the way
    /// out, by number.
    pub way: List<{ v: usize | v < squares }>,
    /// How many steps the way has, and how long it takes, mud and all.
    pub steps: usize,
    pub time: u64,
}

/// Searches `maze`, as `graph`, from square `from` to the way out for the
/// way `kind` says.
pub fn search(
    maze: &Maze,
    graph: &{ g: Graph<(), u64> | g.node_count() == maze.width() * maze.height() },
    from: { v: usize | v < maze.width() * maze.height() },
    kind: Kind,
) -> { f: Found | f.squares == maze.width() * maze.height() } with alloc {
    let to = maze.exit();
    let far = match kind {
        Kind::Fewest => graph.distances(from, |_| 1),
        Kind::Quickest => graph.distances(from, |w| *w),
    };
    let way: List<{ v: usize | v < graph.node_count() }> = match kind {
        Kind::Fewest => match graph.shortest_path(from, to) {
            Some(way) => way,
            None => List::new(),
        },
        Kind::Quickest => match graph.cheapest_path(from, to, |w| *w) {
            Some((_, way)) => way,
            None => List::new(),
        },
    };
    // How long the way takes: each step onto a square takes what that
    // square costs. The first square is where it starts from.
    let mut time: u64 = 0;
    for v in way.iter().skip(1) {
        let (x, y) = maze.place(*v);
        time = saturating_add(time, maze.cost(x, y));
    }
    let steps = if way.len() > 0 { way.len() - 1 } else { 0 };
    Found { kind, squares: graph.node_count(), far, way, steps, time }
}

/// The ending of `step`, or another word, for how many there are: `"s"`,
/// unless there's `one`.
pub fn plural(one: bool) -> &'static str {
    if one { "" } else { "s" }
}

/// Checks that `way` goes from square `from` of `maze` to the way out, a
/// step at a time, through passages.
fn goes(maze: &Maze, from: usize, way: &List<{ v: usize | v < maze.width() * maze.height() }>) {
    assert_eq(&way.first().copied(), &Some(from));
    assert_eq(&way.last().copied(), &Some(maze.exit()));
    let mut at: Option<usize> = None;
    for v in way.iter() {
        if let Some(a) = at {
            let (x, y) = maze.place(*v);
            let mut joined = false;
            for d in [Dir::Up, Dir::Down, Dir::Left, Dir::Right].iter() {
                if let Some((nx, ny)) = maze.step(x, y, *d) {
                    joined = joined || maze.number(nx, ny) == a;
                }
            }
            assert(joined);
        }
        at = Some(*v);
    }
}

#[test]
fn the_quickest_way_is_never_slower() {
    for maze in crate::maze::some(8).iter() {
        let graph = maze.graph();
        let fewest = search(maze, &graph, maze.start(), Kind::Fewest);
        let quickest = search(maze, &graph, maze.start(), Kind::Quickest);
        goes(maze, maze.start(), &fewest.way);
        goes(maze, maze.start(), &quickest.way);
        assert(quickest.time <= fewest.time);
        assert(fewest.steps <= quickest.steps);
        // How far the way out is, as each search found, is how long its
        // way takes, in steps or in time.
        assert_eq(&fewest.far[maze.exit()], &Some(fewest.steps as u64));
        assert_eq(&quickest.far[maze.exit()], &Some(quickest.time));
    }
}
