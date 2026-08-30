"""Stopwatch and the unbuffer call.

`unbuffer()` runs before anything else in build.py. Redirected stdout is
block-buffered, so without it a twenty-minute build and a hung build look
exactly the same from outside: no output either way.
"""
import sys
import time

_t0 = time.time()


def unbuffer():
    """Line-buffer stdout/stderr so progress appears as it happens."""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(line_buffering=True)
        except (AttributeError, ValueError):
            pass


def elapsed():
    return time.time() - _t0


def stamp(label):
    print("[%6.1fs] %s" % (elapsed(), label))
