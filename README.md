## HPC-enabled stack

This is our fork of stack which is built against a recent (unreleased) Cabal to
protect against [Cabal bug #2870](https://github.com/haskell/cabal/issues/2870).

For some background, see also
[GHC ticket #10952](https://ghc.haskell.org/trac/ghc/ticket/10952).

This version of stack is only needed on jenkins; developers may continue to use
normal stack.
