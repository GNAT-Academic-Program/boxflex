# boxflex

Fixed-point flexbox layout engine in Ada/SPARK, with proven geometry.

GNAT Academic Program capstone project. Proposal title: *Flexbox PAL:
Fixed-Point Layout Engine with Proven Geometry*.

## What it is

Give it a tree of boxes with CSS-flexbox styles and an available size;
it gives back a rectangle for every box. That is all a layout engine
does, and it is what every GUI toolkit needs underneath.

What makes this one different:

- **Fixed point, no floats.** Q23.8 coordinates. The same tree lays out
  bit-identically on a desktop, in a browser (wasm), and on a
  microcontroller with no FPU.
- **Bounded, no heap.** Nodes live in a fixed array; links are ids.
  Nothing is allocated, ever.
- **Proven geometry.** Rectangle operations are specified with
  contracts and proved with SPARK. The layout algorithm is written so
  that its key properties (children stay inside their parent, siblings
  never overlap) can be proved too. That is the ambitious part of the
  project.

## The seam

A layout engine has two layers. boxflex exposes both, and the inner one
is the product:

```
Boxflex.Flex.Resolve (Container, Items)      THE ENGINE
    one container, its immediate children, plain records in and out.
    No tree, no recursion, no callbacks. Any application drives this.

Boxflex.Layout.Compute (Tree, Available)     one client of the engine
    walks Boxflex.Tree, measures leaves through a generic hook, calls
    Resolve per container. What you use on bare metal.

adapters/adi2                                another client
    adi2's own flex seam has the same shape; the adapter converts and
    calls Resolve. A desktop toolkit, unchanged, running on boxflex.
```

Proofs live in `Boxflex.Flex` and `Boxflex.Geometry`. The tree walk and
the adapters are plumbing.

## What is in the seed

The architecture, the fundamental types, the contracts, the build, the
CI, the tree walk, and one demo. The engine is a placeholder that packs
items in order with no grow, shrink, wrap or alignment. Your job is to
replace the placeholder with the real algorithm and keep CI green.

```
src/boxflex.ads            Coord, Length, Ratio, Node_Id, Max_Pos       done
src/boxflex-geometry.ads   Point/Size/Rect, proven ops, axis helpers    done
src/boxflex-style.ads      flexbox properties, spec names               done
src/boxflex-tree.ads       bounded tree, Well_Formed invariant          done
src/boxflex-flex.ads       THE ENGINE: Container, Item, Resolve         PLACEHOLDER body
src/boxflex-layout.ads     generic tree walk over Flex                  done
src/boxflex-layout_plain   Layout with no content measurement           done
adapters/adi2/             adi2 seam -> Boxflex.Flex                    stub, not in CI
showcase/                  builds a small UI, writes an SVG             acceptance test
tests/                     unit tests, no framework                     extend as you go
```

Read `ARCHITECTURE.md` before touching anything.

## The acceptance test

`showcase/src/showcase.adb` builds this tree and writes `showcase.svg`:

```
root (column, padding 8, gap 8)
├── toolbar (row, height 40, gap 4, align center)
│   ├── button 80x32
│   ├── button 80x32
│   └── button 80x32
└── content (row, grow 1, gap 8)
    ├── sidebar (width 200)
    ├── main (grow 2)
    └── panel (grow 1)
```

`showcase/reference.html` is the same tree in real CSS. Open it in a
browser as a visual reference for the supported layout features.
Further work includes wrap, reversed directions, percentages against content boxes, and
the bottom-up pass so auto-sized containers hug their children, each
with a reference HTML and a test.

Milestone 2 is the proof: see the `PROOF TARGET` block at the top of
`src/boxflex-flex.ads`.

Milestone 3 is a real client on the desktop:
[adi2](https://github.com/ovenpasta/adi2) built with `adapters/adi2` in
place of its own flex code, its test suite green. adi2 is the client,
boxflex is the engine; nothing in `src/` may depend on adi2. The same
engine runs on bare metal under yarlib through `Boxflex.Layout`; that is
the point of fixed point and no heap.

## Build

Three [Alire](https://alire.ada.dev) crates, one per directory. The
showcase and the tests pin the library by path, so they always build
against the code in your checkout, never a released version.

```
boxflex/            crate boxflex           the library
boxflex/showcase/   crate boxflex_showcase  depends on boxflex, pinned to ..
boxflex/tests/      crate boxflex_tests     depends on boxflex, pinned to ..
```

Library:

```
alr build
```

Showcase (writes `showcase.svg` in `showcase/`):

```
cd showcase
alr build
alr run
```

Tests (exit code is non-zero on any failure):

```
cd tests
alr build
./bin/tests
```

SPARK, from the library directory. Flow analysis is what CI gates on;
full proof is the year's goal:

```
alr with gnatprove
alr exec -- gnatprove -P boxflex.gpr --mode=flow
alr exec -- gnatprove -P boxflex.gpr --mode=all
```

`alr with gnatprove` edits `alire.toml`; that is fine, commit it once
the team is ready to gate on proof.

Contracts are checked at runtime in every build (`-gnata`). A failing
precondition is a bug in the caller; a failing postcondition is a bug in
the callee. Do not turn them off to make something pass.

## Rules of the road

- Warnings are errors. Style checks are on. CI runs on every push.
- A merged pull request comes with a test, or a proof, or both.
- No floating point, no access types, no heap in `src/`. If you think
  you need one, open an issue first.
- Keep `Well_Formed` true. If a new operation on the tree cannot
  maintain it, the operation is wrong, not the invariant.
- Read the spec: [CSS Flexible Box Layout Module Level 1](https://www.w3.org/TR/css-flexbox-1/).
  Names in `Boxflex.Style` are the spec's names on purpose.

See `CONTRIBUTING.md` for the fork and pull request workflow.

## Contact

Olivier Henley, GAP Coordinator, AdaCore. Weekly meeting, plus the
project Discord.

## License

Apache-2.0. See `LICENSE`.
