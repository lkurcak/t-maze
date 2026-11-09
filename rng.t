//! Random numbers: SplitMix64, which is quick and good enough for a game,
//! from a seed, so the same seed makes the same maze.

use core::num::{wrapping_add, wrapping_mul};

/// Numbers that look random, each from the one before.
#[derive(Discard)]
pub struct Rng { state: u64 }

impl Rng {
    /// Numbers that start from `seed`.
    pub fn new(seed: u64) -> Rng { Rng { state: seed } }

    /// The next number.
    pub fn next(&mut self) -> u64 {
        self.state = wrapping_add(self.state, 0x9E3779B97F4A7C15);
        let mut z = self.state;
        z = wrapping_mul(z ^ (z >> 30), 0xBF58476D1CE4E5B9);
        z = wrapping_mul(z ^ (z >> 27), 0x94D049BB133111EB);
        z ^ (z >> 31)
    }

    /// A number less than `n`.
    pub fn below(&mut self, n: { n: usize | n > 0 }) -> { r: usize | r < n } {
        (self.next() % n as u64) as usize
    }

    /// `true` `percent` times in a hundred.
    pub fn chance(&mut self, percent: u64) -> bool { self.next() % 100 < percent }
}
