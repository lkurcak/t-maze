//! The game, on a terminal: the maze, drawn again after each key, and
//! searches spreading over it a frame at a time.

use alloc::string::String;
use core::fmt::Write;
use core::num::{checked_mul, saturating_add};
use core::time::Duration;
use graph::Graph;
use std::io::{Error, Raw, Size, Stdout};
use std::time::Clock;

use crate::draw::{self, Lit};
use crate::keys::{self, Key};
use crate::maze::Maze;
use crate::search::{self, plural, Found, Kind};
use alloc::list::List;
use rand::Rng;
use term::Screen;

/// How many frames a search takes to reach the way out, and how long each
/// is shown, in milliseconds.
const FRAMES: u64 = 60;
const FRAME_MS: u64 = 30;

/// What the keys do, under the maze.
const HELP: &str = "arrows or hjkl: walk   b: fewest steps   d: quickest   n: new maze   q: quit";

/// Plays mazes on the terminal until you quit: each `size` squares, if
/// that's given, or as big as fits. Keys come from `raw`, and `clock`
/// times the frames.
pub fn play(
    out: &mut Stdout,
    raw: &mut Raw<'_>,
    clock: Clock,
    rng: &mut Rng,
    size: Option<(usize, usize)>,
) -> Result<(), Error> {
    let mut screen = Screen::enter(out)?;
    loop {
        let (width, height) = match size {
            Some(s) => s,
            None => fit(screen.out().size()?),
        };
        if width == 0 || height == 0 {
            screen.out().put("The terminal's too small for a maze; any key to stop.")?;
            screen.out().flush()?;
            let _ = keys::read(raw, clock)?;
            return Ok(());
        }
        let Some(maze) = Maze::new(rng, width, height, crate::LOOPS) else { return Ok(()) };
        let graph = maze.graph();
        let you = maze.start();
        let mut game = Game { maze, graph, you, steps: 0, time: 0, found: None };
        screen.clear()?;
        if !game.play(screen.out(), raw, clock)? {
            return Ok(());
        }
    }
}

/// How many squares wide and high a maze fits on a terminal `size` big,
/// with two lines under it: each square and each wall is two characters
/// wide and a line high.
fn fit(size: Size) -> (usize, usize) {
    let cols = size.cols as usize;
    let rows = size.rows as usize;
    let width = if cols >= 6 { (cols / 2 - 1) / 2 } else { 0 };
    let height = if rows >= 5 { (rows - 3) / 2 } else { 0 };
    (width, height)
}

/// A maze being played.
#[derive(Discard)]
struct Game {
    maze: Maze,
    graph: { g: Graph<(), u64> | g.node_count() == maze.width() * maze.height() },
    /// The square you're on, by number.
    you: { v: usize | v < maze.width() * maze.height() },
    /// How many steps you've taken, and how long they took.
    steps: u64,
    time: u64,
    /// What the last search found, shown until you take a step.
    found: Option<{ f: Found | f.squares == maze.width() * maze.height() }>,
}

impl Game {
    /// Plays this maze until you're out, or a key says to stop: `true` for
    /// another maze, `false` to stop.
    fn play(&mut self, out: &mut Stdout, raw: &mut Raw<'_>, clock: Clock) -> Result<bool, Error> {
        loop {
            let lit = draw::lights(&self.maze, self.found.as_ref(), 0, 0, true);
            let mut line = String::new();
            line.put(&f"Steps {self.steps}, time {self.time}.").into_ok();
            if let Some(f) = &self.found {
                line.put(
                    &f"  From here, {about(f.kind)}: {f.steps} step{plural(f.steps == 1)}, taking {f.time}.",
                ).into_ok();
            }
            self.show(out, &lit, line.as_str(), HELP)?;
            match keys::read(raw, clock)? {
                Key::Go(d) => {
                    let (x, y) = self.maze.place(self.you);
                    if let Some((x, y)) = self.maze.step(x, y, d) {
                        self.you = self.maze.number(x, y);
                        self.steps = saturating_add(self.steps, 1);
                        self.time = saturating_add(self.time, self.maze.cost(x, y));
                        self.found = None;
                        if self.you == self.maze.exit() {
                            return self.out(out, raw, clock);
                        }
                    }
                },
                Key::Fewest => {
                    if !self.search(out, raw, clock, Kind::Fewest)? {
                        return Ok(false);
                    }
                },
                Key::Quickest => {
                    if !self.search(out, raw, clock, Kind::Quickest)? {
                        return Ok(false);
                    }
                },
                Key::New => return Ok(true),
                Key::Quit => return Ok(false),
                Key::Other => {},
            }
        }
    }

    /// Searches from where you are for the way `kind` says, showing it
    /// spread out a frame at a time until it reaches the way out, then the
    /// way it found, until you take a step: `false` if a key said to stop.
    /// A key stops the spreading.
    fn search(
        &mut self,
        out: &mut Stdout,
        raw: &mut Raw<'_>,
        clock: Clock,
        kind: Kind,
    ) -> Result<bool, Error> {
        let found = search::search(&self.maze, &self.graph, self.you, kind);
        // How far the way out is: the search is done when it gets there.
        let top = found.far[self.maze.exit()].unwrap_or(0);
        // The squares it reached in the last `band` are its edge.
        let band = top / 32 + 1;
        let line = String::of(&f"Searching for {about(found.kind)}...");
        let start = clock.now();
        let mut go_on = true;
        let mut k: u64 = 1;
        while k <= FRAMES {
            let upto = match checked_mul(top, k) {
                Some(t) => t / FRAMES,
                None => top,
            };
            let since = if upto > band { upto - band } else { 0 };
            let lit = draw::lights(&self.maze, Some(&found), upto, since, false);
            self.show(out, &lit, line.as_str(), HELP)?;
            if raw.wait(start.add(Duration::from_millis(k * FRAME_MS)))? {
                go_on = keys::read(raw, clock)? != Key::Quit;
                break;
            }
            k = k + 1;
        }
        self.found = Some(found);
        Ok(go_on)
    }

    /// You're out: says how quick that was, against the quickest way,
    /// which it shows, and waits for a key: `true` for another maze,
    /// `false` to stop.
    fn out(&mut self, out: &mut Stdout, raw: &mut Raw<'_>, clock: Clock) -> Result<bool, Error> {
        let best = search::search(&self.maze, &self.graph, self.maze.start(), Kind::Quickest);
        let lit = draw::lights(&self.maze, Some(&best), 0, 0, true);
        let mut line = String::new();
        line.put(
            &f"Out, in {self.steps} step{plural(self.steps == 1)}, taking {self.time}. ",
        ).into_ok();
        if self.time <= best.time {
            line.push_str("That's as quick as it gets!");
        } else {
            line.put(
                &f"The quickest way takes {best.time}, in {best.steps} step{plural(best.steps == 1)}.",
            ).into_ok();
        }
        self.show(out, &lit, line.as_str(), "q: quit   any other key: another maze")?;
        Ok(keys::read(raw, clock)? != Key::Quit)
    }

    /// Draws the maze lit as `lit` says, and the lines `status` and `help`
    /// under it.
    fn show(
        &self,
        out: &mut Stdout,
        lit: &{ l: List<Lit> | l.len() == self.maze.width() * self.maze.height() },
        status: &str,
        help: &str,
    ) -> Result<(), Error> {
        // To the top left corner, and draw over what's there.
        let mut s = String::from("\u{1b}[H");
        draw::picture(&mut s, &self.maze, lit, self.you, true);
        s.push_str(status);
        // Clear the rest of each line.
        s.push_str("\u{1b}[K\n");
        s.push_str(help);
        s.push_str("\u{1b}[K");
        out.put(s.as_str())?;
        out.flush()
    }
}

/// What the way a search of `kind` looks for is called.
fn about(kind: Kind) -> &'static str {
    match kind {
        Kind::Fewest => "the fewest steps",
        Kind::Quickest => "the quickest way",
    }
}
