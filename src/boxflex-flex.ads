--  THE ENGINE. One container, its immediate children, nothing else.
--
--  This is the seam every application drives boxflex through. A
--  toolkit, a game, a bare-metal UI: each owns its own tree and its own
--  way of measuring content. What they share is this question:
--
--    "here is a container of a given size with these flex settings, and
--     here are its children with their flex properties and the sizes
--     they would like; how big is each child and where does it go?"
--
--  Resolve answers it. No tree, no recursion, no callbacks, no
--  measurement: the caller has already turned every child into an Item.
--  Boxflex.Layout is one such caller (it walks Boxflex.Tree);
--  adapters/adi2 is another.
--
--  Everything is in main/cross axis terms, not X/Y. The caller maps
--  (Direction is only here so that Row_Reverse and Column_Reverse can
--  flip the packing order). Boxflex.Geometry has the axis helpers.
--
--  PROOF TARGET. This package is the "proven geometry" of the project.
--    P1  No fixed-point overflow.
--    P2  Every output satisfies Edges_In_Range once mapped to a Rect:
--        Pos_Main + Main and Pos_Cross + Cross stay inside Coord.
--    P3  If C.Wrap = No_Wrap and every item has Shrink > 0 and
--        Min_Main = 0, then the sum of (margins + Main) over items,
--        plus gaps, is at most C.Main. Children fit.
--    P4  Items on one line occupy pairwise disjoint main-axis intervals
--        [Pos_Main, Pos_Main + Main), for any Justify. Siblings never
--        overlap.
--  P1 and P2 are expected by month two. P3 and P4 are the year's goal.

with Boxflex.Style; use Boxflex.Style;

package Boxflex.Flex with SPARK_Mode is

   ---------------------------------------------------------------------
   --  Inputs
   ---------------------------------------------------------------------

   type Container is record
      Main, Cross   : Length         := 0.0;  --  content box of the container
      Direction     : Flex_Direction := Row;
      Wrap          : Flex_Wrap      := No_Wrap;
      Justify       : Justify_Content := Flex_Start;
      Align         : Align_Items    := Stretch;
      Lines         : Align_Content  := Stretch;
      Main_Gap      : Length         := 0.0;
      Cross_Gap     : Length         := 0.0;
   end record;

   type Item is record
      --  Flex properties
      Grow           : Ratio   := 0.0;
      Shrink         : Ratio   := 1.0;
      Basis          : Length  := 0.0;
      Basis_Definite : Boolean := False;
      --  Basis is the resolved flex base size. When Basis_Definite is
      --  False the caller could not resolve it (Auto with no size), and
      --  the engine falls back to Content_Main.
      Self           : Align_Self := Auto;

      --  Limits (min/max-width or -height, already resolved to px)
      Min_Main  : Length := 0.0;
      Max_Main  : Length := Length'Last;
      Min_Cross : Length := 0.0;
      Max_Cross : Length := Length'Last;

      --  What the child wants, measured by the caller
      Content_Main   : Length  := 0.0;
      Content_Cross  : Length  := 0.0;
      Cross_Definite : Boolean := False;
      --  True when Content_Cross came from a declared size; Stretch
      --  only applies to items that left their cross size to the layout.
      Baseline       : Length  := 0.0;
      --  Distance from the item's cross-start edge to its baseline.
      --  Only read when Align or Self is Baseline.

      --  Margins, in axis terms
      Margin_Main_Start, Margin_Main_End   : Length := 0.0;
      Margin_Cross_Start, Margin_Cross_End : Length := 0.0;

      --  Outputs, written by Resolve. Positions are relative to the
      --  container's content box, on the main and cross axis.
      Main      : Length := 0.0;
      Cross     : Length := 0.0;
      Pos_Main  : Coord  := 0.0;
      Pos_Cross : Coord  := 0.0;
   end record;

   type Item_Array is array (Positive range <>) of Item;

   ---------------------------------------------------------------------
   --  Contracts helpers
   ---------------------------------------------------------------------

   function Inputs_Unchanged (Before, After : Item) return Boolean is
     (Before.Grow = After.Grow
      and then Before.Shrink = After.Shrink
      and then Before.Basis = After.Basis
      and then Before.Basis_Definite = After.Basis_Definite
      and then Before.Self = After.Self
      and then Before.Min_Main = After.Min_Main
      and then Before.Max_Main = After.Max_Main
      and then Before.Min_Cross = After.Min_Cross
      and then Before.Max_Cross = After.Max_Cross
      and then Before.Content_Main = After.Content_Main
      and then Before.Content_Cross = After.Content_Cross
      and then Before.Cross_Definite = After.Cross_Definite
      and then Before.Baseline = After.Baseline
      and then Before.Margin_Main_Start = After.Margin_Main_Start
      and then Before.Margin_Main_End = After.Margin_Main_End
      and then Before.Margin_Cross_Start = After.Margin_Cross_Start
      and then Before.Margin_Cross_End = After.Margin_Cross_End);

   function Placed_In_Range (I : Item) return Boolean is
     (I.Pos_Main <= Max_Pos and then I.Pos_Cross <= Max_Pos);
   --  P2 in axis terms.

   ---------------------------------------------------------------------
   --  The algorithm
   ---------------------------------------------------------------------

   procedure Resolve (C : Container; Items : in out Item_Array)
     with
       Pre  => Items'Length <= Max_Nodes,
       Post => (for all K in Items'Range =>
                  Inputs_Unchanged (Items'Old (K), Items (K))
                  and then Placed_In_Range (Items (K)));
   --  Sizes and positions every item inside C. Inputs are untouched;
   --  only Main, Cross, Pos_Main, Pos_Cross change. Items keep their
   --  order: a line is always a contiguous run of the array.
   --
   --  Spec, step by step (https://www.w3.org/TR/css-flexbox-1/#layout-algorithm):
   --    1. hypothetical main size of each item: Basis (or Content_Main)
   --       clamped to Min_Main .. Max_Main,
   --    2. collect items into lines (one line if No_Wrap),
   --    3. per line, distribute free space by Grow, or negative free
   --       space by Shrink weighted by base size; freeze items that hit
   --       a limit and iterate,
   --    4. cross size of each line and item (Stretch fills the line
   --       for items with Cross_Definite = False),
   --    5. Justify along the main axis,
   --    6. Align / Self along the cross axis, Lines across lines,
   --    7. write positions.
   --
   --  Implemented so far: steps 1, 3, 4, 5 and 6 (single line) and 7.
   --  Still missing: wrap, align-content and reversed directions.

   ---------------------------------------------------------------------
   --  Pieces, exposed so they can be tested and proved one at a time
   ---------------------------------------------------------------------

   function Hypothetical_Main (I : Item) return Length
     with Post => Hypothetical_Main'Result >= I.Min_Main
                  and then (I.Max_Main < I.Min_Main
                            or else Hypothetical_Main'Result <= I.Max_Main);
   --  Basis (or Content_Main when not definite) clamped to the item's
   --  limits. Min wins over Max when they conflict, as in CSS.

   type Line is record
      First, Last : Natural := 0;
   end record;
   --  One line is the items First .. Last, inclusive.

   type Line_Array is array (Positive range <>) of Line;

   procedure Form_Lines
     (C     : Container;
      Items : Item_Array;
      Lines : out Line_Array;
      Count : out Natural)
     with
       Pre  => Items'Length <= Max_Nodes
               and then Lines'Length >= Items'Length
               and then Lines'First = 1,
       Post => Count <= Items'Length
               and then (if Items'Length > 0 then Count >= 1)
               and then (if C.Wrap = No_Wrap and then Items'Length > 0
                         then Count = 1);
   --  Step 2. Breaks at the first item that no longer fits C.Main. A
   --  line always takes at least one item, so an item wider than the
   --  container overflows its own line instead of opening an empty one.

   procedure Distribute_Grow (C : Container; Items : in out Item_Array)
     with
       Pre  => Items'Length <= Max_Nodes,
       Post => (for all K in Items'Range =>
                  Inputs_Unchanged (Items'Old (K), Items (K))
                  and then Items (K).Main >= Items'Old (K).Main);
   --  Step 3, positive free space only, for a single line. Expects each
   --  item's Main to already hold its hypothetical main size. Shares the
   --  space left on the line among the items in proportion to Grow, and
   --  hands out the leftover 1/256 px units one at a time, first item
   --  first, so the line is filled exactly. Does nothing when there is no
   --  free space or no item has Grow > 0. Max_Main is not applied yet.

   procedure Distribute_Shrink (C : Container; Items : in out Item_Array)
     with Pre => Items'Length <= Max_Nodes;
   --  Step 3, negative free space, for a single line. When the items
   --  overflow C.Main, each one gives up overflow * (Shrink * Main) /
   --  (sum of Shrink * Main). An item that would go below Min_Main is
   --  frozen at Min_Main and the rest is shared again. Leftover 1/256 px
   --  steps come off one at a time, first item first.

end Boxflex.Flex;
