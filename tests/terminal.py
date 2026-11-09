"""Plays the game on a pseudo-terminal: walks, searches both ways, starts
a new maze, gets out of a small one, and quits; then checks that it
stopped cleanly and put the terminal back as it was.

    python3 -I tests/terminal.py tests/maze
"""

import fcntl
import os
import pty
import re
import select
import struct
import sys
import termios
import time

ESC = "\x1b"


def play(argv, keys, rows=24, cols=80):
    """Runs `argv` on a terminal `cols` by `rows`, typing `keys`, each a
    string, or a number of seconds to wait; gives its output, and how it
    stopped, and the terminal's settings before and after."""
    pid, fd = pty.fork()
    if pid == 0:
        os.execv(argv[0], argv)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    before = termios.tcgetattr(fd)
    out = b""

    def read_for(seconds):
        nonlocal out
        end = time.time() + seconds
        while time.time() < end:
            ready, _, _ = select.select([fd], [], [], 0.05)
            if ready:
                try:
                    data = os.read(fd, 1 << 16)
                except OSError:
                    return
                if not data:
                    return
                out += data

    read_for(0.5)
    for k in keys:
        if isinstance(k, (int, float)):
            read_for(k)
        else:
            os.write(fd, k.encode())
            read_for(0.2)
    deadline = time.time() + 10
    while True:
        done, status = os.waitpid(pid, os.WNOHANG)
        if done:
            break
        if time.time() > deadline:
            os.kill(pid, 9)
            sys.exit("FAIL: the game didn't stop when told to")
        read_for(0.1)
    read_for(0.2)
    after = termios.tcgetattr(fd)
    os.close(fd)
    return out.decode("utf-8", "replace"), status, before, after


def frames(text):
    """The frames drawn, without colours: each starts at the top left."""
    plain = [re.sub(ESC + r"\[[0-9;?]*[A-Za-z]", "", f) for f in text.split(ESC + "[H")]
    return plain[1:]


def check(what, ok):
    if not ok:
        sys.exit("FAIL: " + what)


def main():
    exe = sys.argv[1]
    up, down, right = ESC + "[A", ESC + "[B", ESC + "[C"
    # A big maze: walk, watch both searches (a key cuts the second short),
    # then a new maze, and quit.
    text, status, before, after = play(
        [exe, "12", "6", "42"], [right, down, "l", up, "b", 2.5, "d", 0.5, "x", "n", "q"]
    )
    check("it stopped cleanly", os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0)
    check("it used the other screen", ESC + "[?1049h" in text)
    check("it went back to the first screen", text.rstrip().endswith(ESC + "[?1049l"))
    check("it showed the cursor again", ESC + "[?25h" in text)
    check("the terminal's as it was", before == after)
    shown = frames(text)
    check("it drew frames", len(shown) > 10)
    check("it said how far the fewest steps are", any("the fewest steps:" in f for f in shown))
    check("it searched for the quickest way", any("Searching for the quickest way" in f for f in shown))
    check("a new maze starts afresh", "Steps 0, time 0." in shown[-1])
    # A maze two squares wide and one high: one step east is the way out.
    text, status, _, after = play([exe, "2", "1", "3"], [right, "q"])
    check("it stopped cleanly", os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0)
    check("it said you're out", any("Out, in 1 step, taking 1." in f for f in frames(text)))
    check("the terminal's as it was", before == after)
    print("terminal ok")


main()
