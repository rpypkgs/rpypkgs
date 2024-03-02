# Nix flake for RPython packages

This flake offers implementations of the following languages:

Language | Attribute
---|---
Brainfuck | `bf`
Game Boy LR35902 | `pygirl`
Monte | `typhon`
Prolog | `pyrolog`
Python 2.7 | `pypy27`
Python 3.8 | `pypy38`
Python 3.9 | `pypy39`
Ruby | `topaz`

These implementations have one thing in common: they are written with RPython,
a restricted subset of Python 2.7 which is amenable to static analysis. Using
the RPython toolchain, they may be translated to efficient native interpreters
with optional JIT functionality.

## Features

This flake supports fifteen different systems covering all supported upstream
system configurations. If PyPy officially supports a system, then this flake
should support it as well.

## Limitations

This flake does not support cross-compilation. This may be a permanent
restriction, since RPython generally translates binaries for its build system
only.

## Contributions

There is not yet a contribution workflow; contact Corbin directly to send
patches or pull requests.
