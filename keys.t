//! What the keys do, from t-libs' `term`, which reads them.

use std::io::{Error, Raw};
use std::time::Clock;
use term::Key::{self as Pressed, Char, Ctrl};

use crate::maze::Dir;

/// What a key says to do.
#[derive(Copy, Discard, Eq)]
pub enum Key {
    /// Take a step: an arrow, or `k`, `j`, `l` or `h`, as in vi.
    Go(Dir),
    /// Search for the way with the fewest steps: `b`, for breadth first.
    Fewest,
    /// Search for the quickest way: `d`, for Dijkstra.
    Quickest,
    /// A new maze: `n`.
    New,
    /// Stop: `q`, escape, or Ctrl-C.
    Quit,
    Other,
}

/// What the next key pressed says to do.
pub fn read(raw: &mut Raw<'_>, clock: Clock) -> Result<Key, Error> {
    Ok(match term::read(raw, clock)? {
        Pressed::Up | Char('k') => Key::Go(Dir::Up),
        Pressed::Down | Char('j') => Key::Go(Dir::Down),
        Pressed::Right | Char('l') => Key::Go(Dir::Right),
        Pressed::Left | Char('h') => Key::Go(Dir::Left),
        Char('b') => Key::Fewest,
        Char('d') => Key::Quickest,
        Char('n') => Key::New,
        Char('q') | Ctrl('c') | Pressed::Escape => Key::Quit,
        _ => Key::Other,
    })
}
