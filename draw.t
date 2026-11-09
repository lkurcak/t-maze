//! Drawing the maze: in colour, on a terminal, or as plain text.
//!
//! The picture is `2 * width + 1` places wide and `2 * height + 1` high:
//! a square at each odd column of each odd row, and between them a wall,
//! or a passage, which looks like the squares it joins. Corners are
//! always walls. On a terminal each place is two characters wide, so it's
//! about as wide as it's high.

use alloc::list::List;
use alloc::string::String;
use core::cmp::min;

use crate::maze::Maze;
use crate::search::Found;

/// How far a search has got at a square, as it's shown: in order, so a
/// passage is shown as the lesser of the squares it joins.
#[derive(Copy, Discard, Eq, Ord)]
pub enum Lit {
    /// Not reached.
    Dark,
    /// Reached in the last frame: where the search has got to.
    Edge,
    /// Reached before.
    Seen,
    /// On the way the search found.
    Way,
}

/// What's drawn at a place in the picture.
#[derive(Copy, Discard, Eq)]
enum Look { Wall, Floor, Mud, Seen, SeenMud, Edge, Way, WayMud, You, Out }

/// How each square is lit, by number, for `found`, if it's shown: the
/// squares it reached in no more than `upto`, those reached in more than
/// `since` as its edge; and if `way`, the way it found.
pub fn lights(
    maze: &Maze,
    found: Option<&{ f: Found | f.squares == maze.width() * maze.height() }>,
    upto: u64,
    since: u64,
    way: bool,
) -> { l: List<Lit> | l.len() == maze.width() * maze.height() } with alloc {
    let n = maze.squares();
    let mut lit = List::filled(n, Lit::Dark);
    let Some(f) = found else { return lit };
    for v in 0..n invariant lit.len() == n {
        if let Some(d) = f.far[v] {
            if d <= upto {
                lit.set(v, if d > since { Lit::Edge } else { Lit::Seen });
            }
        }
    }
    if way {
        for v in f.way.iter() {
            lit.set(*v, Lit::Way);
        }
    }
    lit
}

/// Draws `maze` into `out`, its squares lit as `lit` says, with you on
/// square `you`; in colour for a terminal if `colour`, or else as text.
/// Each line of the picture ends with a newline.
pub fn picture(
    out: &mut String,
    maze: &Maze,
    lit: &{ l: List<Lit> | l.len() == maze.width() * maze.height() },
    you: { v: usize | v < maze.width() * maze.height() },
    colour: bool,
) with alloc {
    let mut p = Painter { out, colour, last: None };
    let w = maze.width();
    let h = maze.height();
    // The wall along the top.
    p.put(Look::Wall);
    for _ in 0..w {
        p.put(Look::Wall);
        p.put(Look::Wall);
    }
    p.end();
    for y in 0..h {
        // The squares of row `y`, and the walls or passages east of each.
        p.put(Look::Wall);
        for x in 0..w {
            let v = maze.number(x, y);
            let s = maze.square(x, y);
            p.put(if v == you {
                Look::You
            } else if v == maze.exit() {
                Look::Out
            } else {
                look(lit[v], s.mud)
            });
            // The east edge has no passage east; the checker can't know
            // that of `s`.
            if s.east && x + 1 < w {
                let e = maze.number(x + 1, y);
                p.put(look(min(lit[v], lit[e]), s.mud && maze.square(x + 1, y).mud));
            } else {
                p.put(Look::Wall);
            }
        }
        p.end();
        // The walls or passages south of each square of row `y`, and the
        // corners between them; the wall along the bottom, after the last
        // row.
        p.put(Look::Wall);
        for x in 0..w {
            let s = maze.square(x, y);
            if s.south && y + 1 < h {
                let v = maze.number(x, y);
                let b = maze.number(x, y + 1);
                p.put(look(min(lit[v], lit[b]), s.mud && maze.square(x, y + 1).mud));
            } else {
                p.put(Look::Wall);
            }
            p.put(Look::Wall);
        }
        p.end();
    }
}

/// How a square or passage lit `l` looks, if it's `mud` or not.
fn look(l: Lit, mud: bool) -> Look {
    match l {
        Lit::Dark => if mud { Look::Mud } else { Look::Floor },
        Lit::Edge => Look::Edge,
        Lit::Seen => if mud { Look::SeenMud } else { Look::Seen },
        Lit::Way => if mud { Look::WayMud } else { Look::Way },
    }
}

/// Puts places of the picture in a string, one after another.
#[derive(Discard)]
struct Painter<'a> {
    out: &'a mut String,
    /// In colour, for a terminal? Or as text?
    colour: bool,
    /// The look of the place before on this line, in colour: a place that
    /// looks the same needs no new colour.
    last: Option<Look>,
}

impl<'a> Painter<'a> {
    /// Puts a place that looks like `l`.
    fn put(&mut self, l: Look) with alloc {
        if !self.colour {
            self.out.push(text(l));
            return;
        }
        if self.last != Some(l) {
            // Escape, `[48;5;N m`: the background is colour `N` of 256.
            self.out.push_str("\u{1b}[48;5;");
            self.out.push_str(colour(l));
            self.out.push('m');
            self.last = Some(l);
        }
        self.out.push_str("  ");
    }

    /// Ends a line of the picture, in colour back to the terminal's own.
    fn end(&mut self) with alloc {
        if self.colour {
            // Back to the terminal's own colours, and clear the rest of
            // the line, which may hold what was drawn before.
            self.out.push_str("\u{1b}[0m\u{1b}[K");
            self.last = None;
        }
        self.out.push('\n');
    }
}

/// The character a place that looks like `l` is, as text.
fn text(l: Look) -> char {
    match l {
        Look::Wall => '#',
        Look::Floor => ' ',
        Look::Mud => '~',
        Look::Seen => '.',
        Look::SeenMud => ':',
        Look::Edge => '+',
        Look::Way => 'o',
        Look::WayMud => 'O',
        Look::You => '@',
        Look::Out => 'E',
    }
}

/// The number of the background colour, of the terminal's 256, a place
/// that looks like `l` is.
fn colour(l: Look) -> &'static str {
    match l {
        Look::Wall => "250",
        Look::Floor => "236",
        Look::Mud => "94",
        Look::Seen => "24",
        Look::SeenMud => "61",
        Look::Edge => "51",
        Look::Way => "220",
        Look::WayMud => "172",
        Look::You => "46",
        Look::Out => "196",
    }
}
