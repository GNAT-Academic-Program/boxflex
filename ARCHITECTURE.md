# Architecture

## Layers

```
adapters/adi2         Boxflex.Layout (generic on Measure)    clients
        \                 |
         \            Boxflex.Tree     bounded arena, Well_Formed
          \               |
           Boxflex.Flex   THE ENGINE: Container, Item, Resolve
                |
Boxflex.Style   Boxflex.Geometry       properties / rects and proofs
                |
             Boxflex                   Coord, Length, Ratio, Node_Id, Max_Pos
```

Dependencies point down only. `Flex` knows nothing about trees or
widgets; it sees one container and an array of items. `Layout` is the
only package that writes `Node.Layout`.

## The seam

Every application that lays things out has its own tree and its own
notion of "how big does this thing want to be": a toolkit dispatches to
widgets, a game reads sprite sizes, a text UI measures glyphs. What they
share is the question the spec answers per container:

> given a container of this size with these flex settings, and its
> children with these flex properties and preferred sizes, how big is
> each child and where does it go?

That is `Boxflex.Flex.Resolve`. It is the whole engine and the whole
proof surface. It takes plain records and returns plain records, in
main/cross axis terms, so the caller does the X/Y mapping.

`Boxflex.Layout` is the client for applications with no toolkit: it
walks `Boxflex.Tree` in id order (parents first), turns each child into
an `Item` (resolving percentages, picking margins by axis, asking the
generic `Measure` for content size), calls `Resolve`, and writes rects
back in root coordinates. `Boxflex.Layout_Plain` is the instantiation
with no measurement, for UIs made of boxes of known size.

`adapters/adi2` is the client for a toolkit that already has a tree.
adi2's `Compute_Flex_Layout` has the same shape as `Resolve`, in Float;
the adapter is a type conversion in each direction. When adi2 runs on
that adapter and its tests pass, boxflex is conformant.

## Fundamental types (`Boxflex`)

| Type | Format | Range | Purpose |
|---|---|---|---|
| `Coord` | Q23.8 fixed | +/- 2^23 px, 1/256 px steps | positions and offsets |
| `Length` | subtype of Coord | 0 .. 2^22 | extents, margins, padding, gaps |
| `Ratio` | Q10.10 fixed | 0 .. 1024 | flex-grow, flex-shrink |
| `Fraction` | subtype of Ratio | 0 .. 1 | percentages |
| `Node_Id` | integer | 0 .. Max_Nodes | 0 is `No_Node` |

Why `Length` stops at 2^22 and not 2^23: so that `Length + Length`
never overflows `Coord`, and `Coord + Length` never overflows when the
`Coord` is in the lower half of its range. Every overflow precondition
in `Geometry` follows from this one choice. If you change one, change
both.

Why fixed point: determinism. Two machines, or a machine and its proof,
must agree on every pixel. Floats do not give you that across targets.
1/256 px is finer than any display and coarse enough that Q23.8
arithmetic fits in 32 bits.

## Geometry

`Rect` is origin + extent, never two corners. Extents are `Length`, so
a rect is non-negative by construction; no code path needs to check.

Every operation that computes a far edge (`Right`, `Bottom`,
`Contains`, `Overlaps`) has `Edges_In_Range` as precondition. The layout
algorithm guarantees `Edges_In_Range` for every rect it produces
(postcondition of `Compute`), so callers of the engine can use these
operations without checking.

`Inset` is the operation that turns a border box into a content box
(subtract padding and border) or a margin box into a border box. It
clamps at zero rather than producing a negative extent. Its
postcondition (`result inside R, extent no larger than R`) is the lemma
that "children inside parent" proofs will lean on.

## Style

A transcription of the CSS flexbox spec into Ada types. Same names as
the spec. Deliberately excluded for v1: `order`, `baseline`, writing
modes, `aspect-ratio`. Add them only after the core proves.

`Dimension` is a discriminated record: `Auto`, `Fixed` (px) or
`Percent` (of the parent's content box). Resolving a `Dimension`
against a parent size is the first helper you will write in `Layout`.

## Tree

An arena: `Nodes : array (1 .. Max_Nodes) of Node`, `Count` live nodes.
Links are `Node_Id`s: `Parent`, `First_Child`, `Last_Child`,
`Next_Sibling`.

Append-only, and a child is always inserted after its parent, so:

- `Parent_Of (N) < N` for every node,
- sibling links point forward,
- node 1 is the root.

This is `Well_Formed`, and it buys you two things:

1. **No recursion.** A pass over ids in increasing order visits every
   parent before its children (top-down: distribute available space).
   A pass in decreasing order visits every child before its parent
   (bottom-up: compute content sizes). Two loops, no stack, provable
   termination.
2. **Provable walks.** Following `Next_Sibling` strictly increases the
   id, so every loop over children has a trivial `Loop_Variant`.

There is no delete. If you need to rebuild a UI, `Clear` and insert
again; at 256 nodes that is nothing.

## Flex (the work)

`Resolve (C, Items)` implements the spec's algorithm:

1. For each container, resolve each child's **flex base size**
   (`Basis`, falling back to `Width`/`Height`, falling back to content
   size), then clamp with min/max: the **hypothetical main size**.
2. Collect children into **lines** (one line if `No_Wrap`).
3. Per line, **resolve flexible lengths**: distribute free space by
   `Grow`, or negative free space by `Shrink` weighted by base size.
   Freeze items that hit min/max and iterate. This is the loop that
   needs the most care; do it in fixed point with the remainder
   handled explicitly so the sum of children equals the line exactly.
4. Cross sizes: items with `Stretch` take the line's cross size.
5. Main-axis alignment: `Justify` decides where leftover space goes.
6. Cross-axis alignment: `Align` / `Self`.
7. Positions: `Pos_Main`, `Pos_Cross` relative to the container's
   content box. The caller maps to X/Y.

`Form_Lines` (step 2) and `Hypothetical_Main` (step 1) are already
implemented and tested; they are the shape the rest should take: small,
exposed, contract-carrying, testable alone. Write step 3 for `No_Wrap`
first and check the showcase against the HTML reference. Then stretch, then
justify, then wrap, then reversed directions. Each step is a pull
request with a reference HTML and a test.

`Boxflex.Layout.Compute` is already the real tree walk. What it still
needs from the team: a bottom-up pass so auto-sized containers get their
content size from their children (today they get zero), and reversed
directions (which flip the main-axis origin at write-back).

Sums over many items overflow `Coord`, so the body accumulates in
`Units` (a 64-bit integer count of `Coord'Small`) and converts back
with saturation at `Max_Pos`. Keep that pattern: fixed point for
inputs and outputs, wide integers for sums.

### Proof plan

- P1, no overflow: comes for free once every arithmetic step is guarded
  by the `Length` bound and the `Geometry` preconditions.
- P2, `Edges_In_Range` on every output: keep it as a loop invariant
  from the start; it is already in the placeholder.
- P3, children inside parent (no wrap, shrink > 0): the sum of resolved
  main sizes is at most the container's content main size, and each
  cross size is at most the content cross size. Prove the
  sum-of-children lemma on the fixed-point distribution first; it is
  the heart of the whole thing.
- P4, siblings do not overlap: each child's main-axis start is the
  previous child's end plus gap plus margins, so intervals are
  disjoint. A ghost function `Main_Interval (N)` and a loop invariant
  "all intervals so far are ordered and disjoint" gets you there.

Prove `Geometry` fully before starting P3/P4. `gnatprove --mode=all`
should be clean on `Boxflex.Geometry` by the end of month two.

## What is deliberately not here

- No text measurement. Leaf content size comes from `Width`/`Height`
  styles; a text engine can feed those later.
- No rendering. `showcase` writes SVG because it needs nothing. The
  adi2 client comes at milestone 3.
- No incremental relayout. Recompute the whole tree; at this size it
  is faster than tracking dirt.
