#!/usr/bin/env python3
"""Run a command on a real pseudo-terminal and answer its prompts.

    drive_tty.py [--timeout SECS] [--expect REGEX ANSWER]... -- CMD ARGS...

Each --expect pair is handled in order: wait until REGEX shows up in the output,
then type ANSWER + Enter. ANSWER "" just presses Enter. After the last pair the
command runs to completion. Everything the command prints is echoed to stdout.
Exit code: the command's, or 124 when a prompt or the command times out.
Standard library only, so it runs on any VM.
"""

import os
import pty
import re
import select
import sys
import time


def main() -> int:
    args = sys.argv[1:]
    timeout = 600.0
    steps: list[tuple[re.Pattern[str], str]] = []
    while args and args[0] != "--":
        if args[0] == "--timeout":
            timeout = float(args[1])
            args = args[2:]
        elif args[0] == "--expect":
            steps.append((re.compile(args[1]), args[2]))
            args = args[3:]
        else:
            print(f"drive_tty: unknown option {args[0]}", file=sys.stderr)
            return 2
    cmd = args[1:]
    if not cmd:
        print(__doc__, file=sys.stderr)
        return 2

    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(cmd[0], cmd)

    seen = ""   # output since the last answered prompt
    deadline = time.monotonic() + timeout
    step = 0
    while True:
        if time.monotonic() > deadline:
            what = f"prompt /{steps[step][0].pattern}/" if step < len(steps) else "command"
            print(f"\ndrive_tty: timed out waiting for {what}", file=sys.stderr)
            os.kill(pid, 9)
            os.waitpid(pid, 0)
            return 124
        ready, _, _ = select.select([fd], [], [], 0.2)
        if ready:
            try:
                data = os.read(fd, 4096)
            except OSError:
                data = b""
            if not data:
                break
            text = data.decode(errors="replace")
            sys.stdout.write(text)
            sys.stdout.flush()
            seen += text
        if step < len(steps) and steps[step][0].search(seen):
            os.write(fd, (steps[step][1] + "\r").encode())
            seen = ""
            step += 1
    _, status = os.waitpid(pid, 0)
    if step < len(steps):
        print(f"\ndrive_tty: command ended before prompt /{steps[step][0].pattern}/", file=sys.stderr)
        return 125
    return os.waitstatus_to_exitcode(status)


if __name__ == "__main__":
    sys.exit(main())
