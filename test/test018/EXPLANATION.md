Test 018 verifies behaviour in a real interactive terminal (pseudo terminal created by `terminal.py`), in bash and zsh, which can't be tested with `XX_TEST_KEYS`:

- Ctrl+C pressed while a `source: true` script with `set -e` is running does not close the shell, stops the script and does not leave `set -e` switched on in the shell (before the fix next failing command was closing the terminal).
- Real arrow key and Enter (escape sequences read from `/dev/tty`) pick a command from the menu.
- Ctrl+C in the menu returns 130 and the shell stays alive with the cursor restored.

Every shell (system bash, modern bash if installed, zsh) gets its own pseudo terminal and all run at the same time. `terminal.py` never sleeps for a fixed time, it waits for the prompt or for the expected text, so the test takes about 2 seconds.
