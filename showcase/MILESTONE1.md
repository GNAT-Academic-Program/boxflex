# Milestone 1 target rectangles

The browser numbers come from opening `showcase/reference.html` in Chrome and
printing `getBoundingClientRect()` for each `div` in the DevTools console.
The "Engine before stretch/align" numbers come from `cd showcase && alr build
&& alr run` on `main` on Oct 21 (after flex-grow and the SPARK conversion fix,
before stretch and alignment). The "Engine now" numbers come from the same
command on a later `main`.

Milestone 1 is reached: every row matches, where "matches" means equal to the
rule-computed value and within one step of the browser (see Rounding below).

| Node | Box | Browser x, y, w, h | Engine before stretch/align (Oct 21) | Engine now (main, 56e2a12) | Match? |
|---|---|---|---|---|---|
| 1 | root | 0, 0, 800, 600 | 0, 0, 800, 600 | 0, 0, 800, 600 | yes |
| 2 | toolbar | 8, 8, 784, 40 | 8, 8, 0, 40 | 8, 8, 784, 40 | yes |
| 3 | button 1 | 8, 12, 80, 32 | 8, 8, 80, 32 | 8, 12, 80, 32 | yes |
| 4 | button 2 | 92, 12, 80, 32 | 92, 8, 80, 32 | 92, 12, 80, 32 | yes |
| 5 | button 3 | 176, 12, 80, 32 | 176, 8, 80, 32 | 176, 12, 80, 32 | yes |
| 6 | content | 8, 56, 784, 536 | 8, 56, 0, 536 | 8, 56, 784, 536 | yes |
| 7 | sidebar | 8, 56, 200, 536 | 8, 56, 200, 0 | 8, 56, 200, 536 | yes |
| 8 | main | 216, 56, 378.667, 536 | 216, 56, 0, 0 | 216, 56, 378.668, 536 | within 1 step |
| 9 | panel | 602.667, 56, 189.333, 536 | 224, 56, 0, 0 | 602.668, 56, 189.332, 536 | within 1 step |

Exact browser values for nodes 8 and 9: main w = 378.66668701171875,
panel x = 602.6666870117188, panel w = 189.3333282470703.

## Why each row did not match before PR #7 and #8

- **Node 2 (toolbar), w 0 vs 784:** there was no `align-items: stretch` yet. The toolbar
  is a child of the root column, so its cross axis is its width, and it had
  no declared width to fall back on.
- **Nodes 3-5 (buttons), y 8 vs 12:** there was no `align-items: center` yet. The 32 px
  buttons sat at the top of the 40 px toolbar instead of 4 px down.
- **Node 6 (content), w 0 vs 784:** there was no stretch, same as the toolbar. Its
  height of 536 already matched, because flex-grow worked.
- **Node 7 (sidebar), h 0 vs 536:** there was no stretch. It had a fixed width of 200
  but no height, so it should have filled the row's height.
- **Node 8 (main), w 0 h 0 vs 378.667 x 536:** grow worked, but content was
  0 wide (node 6), so there was no free space to share. Once content was 784
  wide, grow 2:1 gave main and panel their widths. Its height needed stretch.
- **Node 9 (panel), x 224 vs 602.667:** same cause as node 8. Main was 0 wide,
  so panel was packed right after it (216 + 0 + 8 gap = 224).

## Rounding

The engine works in whole 1/256 px steps. With stretch and grow in place it
gives main w = 378.668 and panel x = 602.668, w = 189.332 (printed to three
decimals; exactly 96939/256, 154283/256 and 48469/256). The exact value,
2/3 of 568 px, is not a whole number of steps, so it cannot be matched exactly.

Per Olivier, "correct" is defined by the engine's rules, not by the browser:
free space is shared as Free * Grow / Total_Grow rounded down, leftover steps
go to growers in order, nothing is lost, and each size is within one step of
the exact fraction. `Test_Showcase` in `tests/src/tests.adb` computes every
rect from those rules and requires an exact match. The browser numbers above
are a secondary check only: each engine value must be within one step
(1/256 px) of them.
