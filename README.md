# Nix flake for RPython packages

This flake offers Nix expressions building implementations of the following
languages:

Language | Attribute
---|---
1 Billion Rows Challenge | `r1brc`
Brainfuck | `bf`
DIVSPL | `divspl`
LR35902 "Game Boy" | `pygirl`
Kernel Lisp | `icbink`, `plang`
Pixie Lisp | `pixie`
Prolog | `pyrolog`
Python 2.7 | `pypy2`
Python 3.10 | `pypy3`
SOM Smalltalk | `pysom`
Ruby | `topaz`

And its helpers are used by the following flakes:

Language | Downstream
---|---
Cammy | [`cammy`](https://osdn.net/users/corbin/pf/cammy/)
Monte | [`typhon`](https://github.com/monte-language/typhon/)
Nix | [`regiux`](https://osdn.net/users/corbin/pf/regiux/)

These implementations have one thing in common: they are written with RPython,
a restricted subset of Python 2.7 which is amenable to static analysis. Using
the RPython toolchain, they may be translated to efficient native interpreters
with optional JIT functionality.

To be fair, not all expressions build working interpreters. This flake also
offers checks for the following interpreters:

Language | Attribute
---|---
DIVSPL | `divspl`
SOM Smalltalk | `pysom`
Python 2.7 | `pypy2`
Python 3.10 | `pypy3`

## Features

This flake supports fifteen different systems covering all supported upstream
system configurations. If PyPy officially supports a system, then this flake
should support it as well.

This flake bootstraps RPython semi-independently of `nixpkgs`. It uses `stdenv`
to build a CPython for Python 2.7, then uses CPython to build PyPy for Python
2.7 with minimal dependencies. This PyPy is then used to run RPython for all
other builds.

A Cachix cache is available; it is in the public namespace, as
[`rpypkgs`](https://app.cachix.org/cache/rpypkgs). It is automatically
populated on push by GitHub Actions.

## Limitations

This flake does not support cross-compilation. This may be a permanent
restriction, since RPython generally translates binaries for its build system
only.

## Contributions

Pull requests are welcome.
