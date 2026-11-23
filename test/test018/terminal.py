"""
Runs interactive shell in a pseudo terminal and "types" into it, the way a human would.

    python3 terminal.py <bash|zsh> <path to shell binary> <path to xx.sh>

Prints everything the terminal showed (transcript) to stdout, test.sh looks for markers in it.
Markers are typed as "MAR""KER" so they appear joined only in the output of a command,
never in the echo of what was typed.
"""
import os
import pty
import select
import signal
import sys
import time

kind, shell, xxsh = sys.argv[1], sys.argv[2], sys.argv[3]

argv = {
    "bash": [shell, "--norc", "--noprofile", "-i"],
    "zsh": [shell, "-f", "-i"],
}[kind]

pid, fd = pty.fork()

if pid == 0:
    # test.sh starts this file in the background and non interactive bash makes its background
    # jobs ignore SIGINT. Ignored signal is inherited, the shell under test and "sleep" in it
    # would never see Ctrl+C.
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGQUIT, signal.SIG_DFL)
    os.environ["PS1"] = "P> "
    os.environ["TERM"] = "xterm"
    os.execv(argv[0], argv)

out = b""


def read(seconds):
    global out
    end = time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if ready:
            try:
                data = os.read(fd, 65536)
            except OSError:
                return False
            if not data:
                return False
            out += data
    return True


pos = 0


def wait_for(marker, seconds=15):
    """
    Waits until marker shows up in what was printed and not consumed yet,
    then consumes the output up to the end of the marker.
    Nothing here sleeps for fixed time: the test is as fast as the shell is.
    """
    global pos
    needle = marker.encode()
    end = time.time() + seconds
    while True:
        i = out.find(needle, pos)
        if i != -1:
            pos = i + len(needle)
            return True
        if time.time() > end or not read(0.02):
            return False


def send(text):
    try:
        os.write(fd, text if isinstance(text, bytes) else text.encode())
    except OSError:
        pass


PROMPT = "P> "

wait_for(PROMPT)

# 1. Ctrl+C while sourced script with "set -e" is waiting for a command
send('source "%s" slow\n' % xxsh)
wait_for("slow-started")
# "sleep" of the script has to be really running when Ctrl+C comes
read(0.3)
send(b"\x03")
wait_for(PROMPT)
send('echo "OP""TS=$-"\n')
wait_for("OPTS=", 5)
wait_for(PROMPT, 5)
send("false\n")
wait_for(PROMPT, 5)
send('echo "ALI""VE1"\n')
wait_for("ALIVE1", 5)
wait_for(PROMPT, 5)

# 2. real keys in the menu: arrow down, Enter
send('source "%s"\n' % xxsh)
wait_for("navigate")
send(b"\x1b[B")
read(0.1)
send(b"\r")
wait_for("picked-second", 5)
wait_for(PROMPT, 5)

# 3. Ctrl+C in the menu
send('source "%s"\n' % xxsh)
wait_for("navigate")
send(b"\x03")
wait_for(PROMPT, 5)
send('echo "CO""DE=$?"\n')
wait_for("CODE=", 5)
wait_for(PROMPT, 5)
send('echo "ALI""VE2"\n')
wait_for("ALIVE2", 5)
wait_for(PROMPT, 5)

# 4. lone Esc in the menu (no other byte follows it, unlike in the arrow keys)
send('source "%s"\n' % xxsh)
wait_for("navigate")
send(b"\x1b")
wait_for(PROMPT, 5)
send('echo "ESC""CODE=$?"\n')
wait_for("ESCCODE=", 5)
wait_for(PROMPT, 5)

# 5. Esc with a filter typed in
send('source "%s"\n' % xxsh)
wait_for("navigate")
send("sec")
read(0.1)
send(b"\x1b")
wait_for(PROMPT, 5)
send('echo "ESC""FILTER=$?"\n')
wait_for("ESCFILTER=", 5)
wait_for(PROMPT, 5)

send("exit\n")
read(0.1)

try:
    os.kill(pid, 9)
except OSError:
    pass

sys.stdout.write(out.decode(errors="replace"))
