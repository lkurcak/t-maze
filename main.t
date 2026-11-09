//! t-maze: find the way out of a maze, and watch two searches find it.
//!
//! On a terminal it's a game: the arrow keys walk you from the top left
//! corner to the way out in the bottom right, through mud, which takes
//! longer to cross; `b` shows a breadth-first search spreading out from
//! where you are to find the way with the fewest steps, and `d` Dijkstra's
//! algorithm finding the quickest. Otherwise, as when its output goes to a
//! file, it writes a maze, and both ways, as text.
//!
//! `maze [WIDTH HEIGHT [SEED]]`: a maze of that many squares, from that
//! seed, the same maze each time; with no seed, a new one each time; with
//! no size, on a terminal, one that fills it.
//!
//! Nothing in it panics: `implicit_panics` warns of any arithmetic, or
//! index, the checker can't prove is in range, and CI denies warnings.
#![warn(implicit_panics)]

use alloc::string::String;
use std::io::{Error, Stdout};
use std::Os;

use maze::Maze;
use rng::Rng;
use search::{Found, Kind};

mod draw;
mod keys;
mod maze;
mod play;
mod rng;
mod search;

/// How many passages in a hundred, beyond those of a perfect maze, to
/// knock through: enough that there's more than one way, so mud can make
/// the one with the fewest steps slower than another.
const LOOPS: u64 = 8;

/// What the command line says: how big a maze, and from what seed.
#[derive(Copy, Discard)]
struct Asked { size: Option<(usize, usize)>, seed: Option<u64> }

fn main(os: Os) -> Result<(), Error> {
    let mut input = os.stdin;
    let mut out = os.stdout;
    let mut err = os.stderr;
    let Some(asked) = asked(os.args) else {
        return err.line(
            "usage: maze [WIDTH HEIGHT [SEED]], each a whole number, WIDTH and HEIGHT at least 1",
        );
    };
    let seed = match asked.seed {
        Some(seed) => seed,
        None => os.entropy.u64()?,
    };
    let mut rng = Rng::new(seed);
    if input.is_terminal() && out.is_terminal() {
        let mut raw = input.raw()?;
        return play::play(&mut out, &mut raw, os.clock, &mut rng, asked.size);
    }
    let (width, height) = asked.size.unwrap_or((20, 10));
    print(&mut out, &mut rng, width, height, seed)
}

/// Reads the command line: `None` if it's not as `usage` says.
fn asked(args: std::env::Args) -> Option<Asked> {
    let mut words = args.iter();
    let Some(w) = words.next() else { return Some(Asked { size: None, seed: None }) };
    let h = words.next()?;
    let size = (w.parse::<usize>().ok()?, h.parse::<usize>().ok()?);
    let seed = match words.next() {
        Some(s) => Some(s.parse::<u64>().ok()?),
        None => None,
    };
    if words.next().is_some() {
        return None;
    }
    Some(Asked { size: Some(size), seed })
}

/// Writes a maze `width` by `height` from `rng`, as text, and the way with
/// the fewest steps through it, and the quickest.
fn print(
    out: &mut Stdout,
    rng: &mut Rng,
    width: usize,
    height: usize,
    seed: u64,
) -> Result<(), Error> {
    if width == 0 || height == 0 {
        return out.line("A maze has at least one square each way.");
    }
    let Some(maze) = Maze::new(rng, width, height, LOOPS) else {
        return out.line("That maze is too big.");
    };
    let graph = maze.graph();
    out.line(&f"A maze {width} squares wide and {height} high, from seed {seed}.")?;
    let fewest = search::search(&maze, &graph, maze.start(), Kind::Fewest);
    let quickest = search::search(&maze, &graph, maze.start(), Kind::Quickest);
    show(out, &maze, &fewest)?;
    out.line(&f"The fewest steps: {fewest.steps}, taking {fewest.time}.")?;
    show(out, &maze, &quickest)?;
    let s = search::plural(quickest.steps == 1);
    out.line(&f"The quickest way: {quickest.steps} step{s}, taking {quickest.time}.")
}

/// Writes `maze` as text, with the way `found` found.
fn show(
    out: &mut Stdout,
    maze: &Maze,
    found: &{ f: Found | f.squares == maze.width() * maze.height() },
) -> Result<(), Error> {
    let lit = draw::lights(maze, Some(found), 0, 0, true);
    let mut text = String::new();
    draw::picture(&mut text, maze, &lit, maze.start(), false);
    out.put(text.as_str())
}
