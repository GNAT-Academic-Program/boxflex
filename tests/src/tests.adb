--  Unit tests. Plain Ada, no framework: each Check prints PASS/FAIL
--  and the program exits non-zero if anything failed. Add a test for
--  every behaviour you implement; CI runs this on every push.

with Ada.Command_Line;
with Ada.Text_IO;      use Ada.Text_IO;
with Boxflex;          use Boxflex;
with Boxflex.Geometry; use Boxflex.Geometry;
with Boxflex.Style;    use Boxflex.Style;
with Boxflex.Tree;     use Boxflex.Tree;
with Boxflex.Flex;
with Boxflex.Layout_Plain;

procedure Tests is

   Failures : Natural := 0;

   procedure Check (Name : String; Condition : Boolean) is
   begin
      if Condition then
         Put_Line ("PASS  " & Name);
      else
         Put_Line ("FAIL  " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   ---------------------------------------------------------------------
   --  Geometry
   ---------------------------------------------------------------------

   procedure Test_Geometry is
      A : constant Rect := Make (0.0, 0.0, 100.0, 50.0);
      B : constant Rect := Make (10.0, 10.0, 20.0, 20.0);
      C : constant Rect := Make (100.0, 0.0, 10.0, 10.0);
      I : constant Rect := Inset (A, 5.0, 5.0, 5.0, 5.0);
      J : constant Rect := Inset (B, 15.0, 0.0, 15.0, 0.0);
   begin
      Check ("Right",           Right (A) = 100.0);
      Check ("Bottom",          Bottom (A) = 50.0);
      Check ("Contains",        Contains (A, B));
      Check ("not Contains",    not Contains (B, A));
      Check ("Overlaps",        Overlaps (A, B));
      Check ("touching edges do not overlap", not Overlaps (A, C));
      Check ("Inset origin",    I.Origin = (X => 5.0, Y => 5.0));
      Check ("Inset extent",    I.Extent = (Width => 90.0, Height => 40.0));
      Check ("Inset clamps at zero", J.Extent.Width = 0.0);
      Check ("Inset stays inside", Contains (A, I));
      Check ("Translate",
             Translate (B, 5.0, -5.0).Origin = (X => 15.0, Y => 5.0));
      Check ("fixed point resolution",
             Coord'Small = Precision and Coord'Succ (0.0) = Coord (Precision));
   end Test_Geometry;

   ---------------------------------------------------------------------
   --  Tree
   ---------------------------------------------------------------------

   procedure Test_Tree is
      T : Layout_Tree;
      R, A, B, C : Node_Id;
   begin
      Check ("empty tree is well formed", Well_Formed (T));
      Insert (T, No_Node, Default_Style, R);
      Check ("root is node 1", R = 1);
      Insert (T, R, Default_Style, A);
      Insert (T, R, Default_Style, B);
      Insert (T, A, Default_Style, C);
      Check ("count", T.Count = 4);
      Check ("parent links", Parent_Of (T, C) = A and Parent_Of (T, A) = R);
      Check ("first child", First_Child_Of (T, R) = A);
      Check ("sibling", Next_Sibling_Of (T, A) = B);
      Check ("last sibling", Next_Sibling_Of (T, B) = No_Node);
      Check ("child count root", Child_Count (T, R) = 2);
      Check ("child count leaf", Child_Count (T, B) = 0);
      Check ("well formed after inserts", Well_Formed (T));
      Clear (T);
      Check ("clear", Is_Empty (T));
   end Test_Tree;

   ---------------------------------------------------------------------
   --  Flex (the engine)
   ---------------------------------------------------------------------

   procedure Test_Flex is
      use Boxflex.Flex;
      C  : Container := (Main => 200.0, Cross => 100.0, others => <>);
      It : Item_Array (1 .. 2) :=
        [1 => (Basis => 50.0, Basis_Definite => True, Content_Cross => 20.0,
               Margin_Main_Start => 5.0, others => <>),
         2 => (Basis => 300.0, Basis_Definite => True, Min_Main => 0.0,
               Max_Main => 80.0, others => <>)];
      L  : Line_Array (1 .. 2);
      N  : Natural;
   begin
      Check ("hypothetical: basis",  Hypothetical_Main (It (1)) = 50.0);
      Check ("hypothetical: clamped", Hypothetical_Main (It (2)) = 80.0);

      -- Hypothetical_Main edge cases
      declare
         H: constant Item_Array (1 .. 3) :=
            [1 => (Content_Main => 40.0, others => <>),
            2 => (Basis => 10.0, Basis_Definite => True, Min_Main => 30.0, others => <>),
            3 => (Basis => 70.0, Basis_Definite => True, Min_Main => 100.0,
                  Max_Main => 50.0, others => <>)];

      begin
         Check ("hypothetical: content when basis not defined",
               Hypothetical_Main (H (1)) = 40.0);
         Check ("hypothetical: raised to min", Hypothetical_Main (H (2)) = 30.0);
         Check ("hypothetical: min wins over max", Hypothetical_Main (H (3)) = 100.0);
      end;
      Form_Lines (C, It, L, N);
      Check ("no wrap: one line", N = 1 and then L (1) = (First => 1, Last => 2));

      C.Wrap := Wrap;
      C.Main := 100.0;
      Form_Lines (C, It, L, N);
      Check ("wrap: two lines", N = 2 and then L (2) = (First => 2, Last => 2));

      C.Wrap := No_Wrap;
      C.Main := 200.0;
      Resolve (C, It);
      Check ("resolve: sizes",      It (1).Main = 50.0 and then It (2).Main = 80.0);
      Check ("resolve: margin",     It (1).Pos_Main = 5.0);
      Check ("resolve: packed",     It (2).Pos_Main = 55.0);
      Check ("resolve: in range",   Placed_In_Range (It (1)) and Placed_In_Range (It (2)));

      --  grow: 200 - (5 + 50 + 80) = 65 px free, split evenly (32.5 each)
      declare
         G : Item_Array (1 .. 2) :=
             [1 => (Basis => 50.0, Basis_Definite => True, Grow => 1.0,
                     Margin_Main_Start => 5.0, others => <>),
              2 => (Basis => 80.0, Basis_Definite => True, Grow => 1.0,
                     others => <>)];
      begin
         Resolve (C, G);
         Check ("grow: sizes", G (1).Main = 82.5 and then G (2).Main = 112.5);
         Check ("grow: positions", G (1).Pos_Main = 5.0 and then G (2).Pos_Main = 87.5);
         Check ("grow: fills the line", G (2).Pos_Main + G (2).Main = 200.0);
      end;

      -- grow 2:1 90 px free, so 60 and 30
      declare
         G : Item_Array (1 .. 2) :=
             [1 => (Grow => 2.0, others => <>),
              2 => (Grow => 1.0, others => <>)];
      begin
         Resolve ((Main => 90.0, Cross => 10.0, others => <>), G);
         Check ("grow 2:1: sizes", G (1).Main = 60.0 and then G (2).Main = 30.0);
      end;

      -- grow with an uneven split: 100 px / 3 leaves one 1/256 px unit over
      declare
         G : Item_Array (1 .. 3) := [others => (Grow => 1.0, others => <>)];
      begin
         Resolve ((Main => 100.0, Cross => 10.0, others => <>), G);
         Check ("grow: remainder keeps the line exact",
                  G (1).Main + G (2).Main + G (3).Main = 100.0);
         Check ("grow: leftover goes to the first item", G (1).Main > G (2).Main and then G (2).Main = G (3).Main);
      end;

      --  no grow: free space stays unused
      declare
         G : Item_Array (1 .. 1) :=
             [1 => (Basis => 50.0, Basis_Definite => True,  others => <>)];
      begin
         Resolve (C, G);
         Check ("grow: zero grow leaves the size alone", G (1).Main = 50.0);
      end;

      --  stretch: container 300 x 100, default Align is Stretch
      declare
         SC : constant Container := (Main => 300.0, Cross => 100.0, others => <>);
         S  : Item_Array (1 .. 4) :=
               [1 => (others => <>),
                2 => (Margin_Cross_Start => 5.0, Margin_Cross_End => 5.0, others => <>),
                3 => (Content_Cross => 20.0, Cross_Definite => True, others => <>),
                4 => (Max_Cross => 60.0, others => <>)];
      begin
         Resolve (SC, S);
         Check ("stretch: fills the cross axis", S (1).Cross = 100.0 and then S (1).Pos_Cross = 0.0);
         Check ("stretch: minus cross margins", S (2).Cross = 90.0 and then S (2).Pos_Cross = 5.0);
         Check ("stretch: declared size is kept", S (3).Cross = 20.0);
         Check ("stretch: max wins", S (4).Cross = 60.0);
      end;

      --  cross-axis alignment: 32 px item in a 100 px line
      declare
         AC : Container := (Main => 300.0, Cross => 100.0, others => <>);
         A  : Item_Array (1 .. 1) :=
            [1 => (Content_Cross => 32.0, Cross_Definite => True, Self => Center, others => <>)];
      begin
         Resolve (AC, A);
         Check ("align: self center", A (1).Pos_Cross = 34.0);

         AC.Align := Flex_End;
         A (1).Self := Auto;
         Resolve (AC, A);
         Check ("align: container flex-end", A (1).Pos_Cross = 68.0);

         A (1).Self := Flex_Start;
         Resolve (AC, A);
         Check ("align: self overrides container", A (1).Pos_Cross = 0.0);

         --  Auto inherits the container's Center: (100 - 32) / 2 = 34
         AC.Align := Center;
         A (1).Self := Auto;
         Resolve (AC, A);
         Check ("align: auto inherits container center", A (1).Pos_Cross = 34.0);
      end;

      --  Self => Stretch still stretches inside a Flex_Start container
      declare
         SS : Item_Array (1 .. 1) := [1 => (Self => Stretch, others => <>)];
      begin
         Resolve ((Main => 300.0, Cross => 100.0, Align => Flex_Start, others => <>), SS);
         Check ("align: self stretch overrides container flex-start",
                  SS (1).Cross = 100.0 and then SS (1).Pos_Cross = 0.0);
      end;

      --  justify-content with a single item
      declare
         J1 : Item_Array (1 .. 1) :=
           [1 => (Basis => 40.0, Basis_Definite => True, others => <>)];
      begin
         Resolve ((Main => 100.0, Cross => 10.0, Justify => Space_Between,
                   others => <>), J1);
         Check ("justify: space-between with one item acts like flex-start",
                J1 (1).Pos_Main = 0.0);
         Resolve ((Main => 100.0, Cross => 10.0, Justify => Space_Around,
                   others => <>), J1);
         Check ("justify: space-around with one item centers it",
                J1 (1).Pos_Main = 30.0);
      end;
   end Test_Flex;

   ---------------------------------------------------------------------
   --  Layout (the tree walk)
   ---------------------------------------------------------------------

   procedure Test_Layout is
      T : Layout_Tree;
      R, A, B : Node_Id;
      S : Flex_Style;
   begin
      S := Default_Style;
      S.Direction := Row;
      Insert (T, No_Node, S, R);

      S := Default_Style;
      S.Grow := 1.0;
      Insert (T, R, S, A);
      Insert (T, R, S, B);

      Boxflex.Layout_Plain.Compute (T, (Width => 200.0, Height => 100.0));

      Check ("root fills available",
             Layout_Of (T, R) = Make (0.0, 0.0, 200.0, 100.0));
      Check ("structure untouched", Child_Count (T, R) = 2);
      Check ("children placed", Placed (Layout_Of (T, A)) and Placed (Layout_Of (T, B)));

      Check ("growers split the width",
             Layout_Of (T, A). Extent.Width = 100.0
             and Layout_Of (T, B). Extent.Width = 100.0
             and Layout_Of (T, B).Origin.X = 100.0);

      --  pending: two equal growers split the main axis
        Check ("A is left half",  Layout_Of (T, A) = Make (0.0,   0.0, 100.0, 100.0));
        Check ("B is right half", Layout_Of (T, B) = Make (100.0, 0.0, 100.0, 100.0));
        Check ("siblings do not overlap",
               not Overlaps (Layout_Of (T, A), Layout_Of (T, B)));
        Check ("children inside parent",
               Contains (Layout_Of (T, R), Layout_Of (T, A))
              and Contains (Layout_Of (T, R), Layout_Of (T, B)));
   end Test_Layout;

   ---------------------------------------------------------------------
   --  Rules: expected values are worked out from the engine's rules in
   --  whole 1/256 px steps, never copied from a browser. The browser
   --  numbers in showcase/MILESTONE1.md are only a secondary check.
   ---------------------------------------------------------------------

   type Steps is range -2 ** 62 .. 2 ** 62 - 1;
   Step : constant Coord := Coord'Small;  --  one step = 1/256 px

   function To_Steps (X : Coord) return Steps is (Steps (X / Step));
   function From_Steps (S : Steps) return Coord is (Step * Integer (S));

   --  The browser reports 32-bit floats. Below 1024 px every such value
   --  is an exact multiple of 2**(-16) px, so this type holds them with
   --  no rounding (and no floating point).
   type Browser_Px is delta 2.0 ** (-16) range 0.0 .. 1024.0
     with Small => 2.0 ** (-16);

   function Near (Engine : Coord; Browser : Browser_Px) return Boolean is
     (abs (Browser_Px (Engine) - Browser) <= Browser_Px (Step));
   --  Secondary check: within one engine step of the browser.

   procedure Test_Showcase is
      T : Layout_Tree;
      S : Flex_Style;
      Root, Toolbar, Content, Sidebar, Main, Panel : Node_Id;
      Buttons : array (1 .. 3) of Node_Id;
   begin
      --  The same tree as showcase/src/showcase.adb.
      S := Default_Style;
      S.Direction := Column;
      S.Padding := Uniform (8.0);
      S.Gap := 8.0;
      Insert (T, No_Node, S, Root);

      S := Default_Style;
      S.Direction := Row;
      S.Height := Px (40.0);
      S.Gap := 4.0;
      S.Align := Center;
      Insert (T, Root, S, Toolbar);

      for K in Buttons'Range loop
         S := Default_Style;
         S.Width := Px (80.0);
         S.Height := Px (32.0);
         Insert (T, Toolbar, S, Buttons (K));
      end loop;

      S := Default_Style;
      S.Direction := Row;
      S.Grow := 1.0;
      S.Gap := 8.0;
      Insert (T, Root, S, Content);

      S := Default_Style;
      S.Width := Px (200.0);
      Insert (T, Content, S, Sidebar);

      S := Default_Style;
      S.Grow := 2.0;
      Insert (T, Content, S, Main);

      S := Default_Style;
      S.Grow := 1.0;
      Insert (T, Content, S, Panel);

      Boxflex.Layout_Plain.Compute (T, (Width => 800.0, Height => 600.0));

      declare
         Pad : constant Length := 8.0;               --  root padding
         Gap : constant Length := 8.0;               --  root and content gap
         W   : constant Length := 800.0 - 2 * Pad;   --  root inner width
         H   : constant Length := 600.0 - 2 * Pad;   --  root inner height

         --  Root column: the toolbar is fixed, content is the only grower,
         --  so it takes all the free height.
         Content_Y : constant Coord  := Pad + 40.0 + Gap;
         Content_H : constant Length := H - 40.0 - Gap;

         --  Toolbar row, align center: offset = free cross / 2, rounded down.
         Button_Y : constant Coord :=
           Pad + From_Steps ((To_Steps (40.0) - To_Steps (32.0)) / 2);

         --  Content row: free = line - sidebar - two gaps.
         Free : constant Steps :=
           To_Steps (W) - To_Steps (200.0) - 2 * To_Steps (Gap);
         --  Each grower gets Free * Grow / Total_Grow, rounded down.
         Main_Share  : constant Steps := Free * 2 / 3;
         Panel_Share : constant Steps := Free * 1 / 3;
         --  Leftover steps go to growers in order, one each. Two
         --  round-downs lose less than 2 steps, so main (first) gets it.
         Leftover : constant Steps := Free - Main_Share - Panel_Share;
         Main_W   : constant Length := From_Steps (Main_Share + Leftover);
         Panel_W  : constant Length := From_Steps (Panel_Share);
         Main_X   : constant Coord  := Pad + 200.0 + Gap;
         Panel_X  : constant Coord  := Main_X + Main_W + Gap;
      begin
         --  Primary: exact equality with the rule-computed rects.
         Check ("showcase: root", Layout_Of (T, Root) = Make (0.0, 0.0, 800.0, 600.0));
         Check ("showcase: toolbar stretched",
                Layout_Of (T, Toolbar) = Make (Pad, Pad, W, 40.0));
         for K in Buttons'Range loop
            Check ("showcase: button" & K'Image & " centered",
                   Layout_Of (T, Buttons (K))
                     = Make (Pad + (K - 1) * (80.0 + 4.0), Button_Y, 80.0, 32.0));
         end loop;
         Check ("showcase: content grows",
                Layout_Of (T, Content) = Make (Pad, Content_Y, W, Content_H));
         Check ("showcase: sidebar stretched",
                Layout_Of (T, Sidebar) = Make (Pad, Content_Y, 200.0, Content_H));
         Check ("showcase: main follows the grow rule",
                Layout_Of (T, Main) = Make (Main_X, Content_Y, Main_W, Content_H));
         Check ("showcase: panel follows the grow rule",
                Layout_Of (T, Panel) = Make (Panel_X, Content_Y, Panel_W, Content_H));

         --  The rounding stays honest: nothing lost, nothing invented,
         --  and main is within one step of the exact 2/3 of Free
         --  (|3 * main - 2 * Free| < 3, written without fractions).
         Check ("showcase: remainder conserved",
                To_Steps (Main_W) + To_Steps (Panel_W) = Free);
         Check ("showcase: main within one step of 2/3",
                abs (3 * To_Steps (Main_W) - 2 * Free) < 3);
      end;

      --  Secondary: Chrome's getBoundingClientRect values, copied from
      --  showcase/MILESTONE1.md (nodes 8 and 9 written out in full).
      declare
         type Box is record
            X, Y, W, H : Browser_Px;
         end record;
         Browser : constant array (Node_Id range 1 .. 9) of Box :=
           [(0.0, 0.0, 800.0, 600.0),
            (8.0, 8.0, 784.0, 40.0),
            (8.0, 12.0, 80.0, 32.0),
            (92.0, 12.0, 80.0, 32.0),
            (176.0, 12.0, 80.0, 32.0),
            (8.0, 56.0, 784.0, 536.0),
            (8.0, 56.0, 200.0, 536.0),
            (216.0, 56.0, 378.66668701171875, 536.0),
            (602.66668701171875, 56.0, 189.3333282470703125, 536.0)];
      begin
         for N in Browser'Range loop
            declare
               R : constant Rect := Layout_Of (T, N);
               B : constant Box := Browser (N);
            begin
               Check ("browser: node" & N'Image & " within one step",
                      Near (R.Origin.X, B.X) and then Near (R.Origin.Y, B.Y)
                      and then Near (R.Extent.Width, B.W)
                      and then Near (R.Extent.Height, B.H));
            end;
         end loop;
      end;
   end Test_Showcase;

   --  Center with an odd number of free steps: the half step must round
   --  down, and still land within one step of the true middle.
   procedure Test_Center_Rounding is
      use Boxflex.Flex;
      C : constant Container := (Main => 100.0, Cross => 100.0, others => <>);
      A : Item_Array (1 .. 1) :=
        [1 => (Content_Cross => 33.0 + Step, Cross_Definite => True,
               Self => Center, others => <>)];
      Free : constant Steps := To_Steps (100.0) - To_Steps (33.0 + Step);
   begin
      Resolve (C, A);
      Check ("center: free / 2 rounded down", To_Steps (A (1).Pos_Cross) = Free / 2);
      Check ("center: within one step of the middle",
             abs (2 * To_Steps (A (1).Pos_Cross) - Free) < 2);
   end Test_Center_Rounding;

   procedure Test_Edge_Cases is
      use Boxflex.Flex;
   begin
      --  No items at all: Resolve must simply do nothing.
      declare
         E : Item_Array (1 .. 0);
      begin
         Resolve ((Main => 100.0, Cross => 100.0, others => <>), E);
         Check ("edge: empty line resolves", E'Length = 0);
      end;

      --  Cross margins bigger than the container: stretch gives 0, not
      --  a negative size, and the item still starts after its margin.
      declare
         M : Item_Array (1 .. 1) :=
           [1 => (Margin_Cross_Start => 8.0, Margin_Cross_End => 8.0,
                  others => <>)];
      begin
         Resolve ((Main => 100.0, Cross => 10.0, others => <>), M);
         Check ("edge: margins wider than the line stretch to 0",
                M (1).Cross = 0.0 and then M (1).Pos_Cross = 8.0);
      end;

      --  Items already overflow the line: there is no free space, so
      --  grow changes nothing, and shrink cuts 30 px from each.
      declare
         O : Item_Array (1 .. 2) :=
           [others => (Basis => 80.0, Basis_Definite => True, Grow => 1.0,
                       others => <>)];
      begin
         Resolve ((Main => 100.0, Cross => 10.0, others => <>), O);
         Check ("edge: overflowing items shrink instead of growing",
                O (1).Main = 50.0 and then O (2).Main = 50.0);
         Check ("edge: shrunk items fill the line exactly",
                O (2).Pos_Main = 50.0);
      end;

      --  A zero-size container: growers stay at 0.
      declare
         Z : Item_Array (1 .. 2) :=
           [others => (Grow => 1.0, others => <>)];
      begin
         Resolve ((Main => 0.0, Cross => 0.0, others => <>), Z);
         Check ("edge: zero-size container",
                Z (1).Main = 0.0 and then Z (2).Main = 0.0
                and then Z (2).Pos_Main = 0.0);
      end;

      --  Min_Cross above Max_Cross: min wins, as in CSS.
      declare
         X : Item_Array (1 .. 1) :=
           [1 => (Min_Cross => 50.0, Max_Cross => 20.0, others => <>)];
      begin
         Resolve ((Main => 100.0, Cross => 100.0, others => <>), X);
         Check ("edge: min cross wins over max cross",
                X (1).Cross = 50.0);
      end;

      --  Same conflict on the main axis, with a basis above both limits.
      declare
         H : constant Item :=
           (Basis => 120.0, Basis_Definite => True,
            Min_Main => 100.0, Max_Main => 50.0, others => <>);
      begin
         Check ("edge: min main wins when basis is above both",
                Hypothetical_Main (H) = 100.0);
      end;

      --  Grow remainder, computed from the rule: 1 px = 256 steps over
      --  three growers is 85 each with 1 step left over. The leftover
      --  goes to the first item that grows, skipping the Grow = 0 item.
      declare
         R : Item_Array (1 .. 4) :=
           [1      => (Grow => 0.0, others => <>),
            2 .. 4 => (Grow => 1.0, others => <>)];
         Free  : constant Steps := To_Steps (1.0);
         Share : constant Steps := Free / 3;
      begin
         Resolve ((Main => 1.0, Cross => 10.0, others => <>), R);
         Check ("edge: zero-grow item gets nothing",
                R (1).Main = 0.0);
         Check ("edge: leftover step goes to the first grower",
                To_Steps (R (2).Main) = Share + 1);
         Check ("edge: other growers get the rounded-down share",
                To_Steps (R (3).Main) = Share
                and then To_Steps (R (4).Main) = Share);
         Check ("edge: remainder conserved",
                To_Steps (R (2).Main) + To_Steps (R (3).Main)
                + To_Steps (R (4).Main) = Free);
      end;
   end Test_Edge_Cases;

   procedure Test_Justify_Rounding is
      use Boxflex.Flex;
      --  space-evenly with 2 items: 100 px free over 3 spaces is 33.33 px,
      --  which is not a whole number of steps. Each space rounds down.
      J    : Item_Array (1 .. 2) :=
        [others => (Basis => 50.0, Basis_Definite => True, others => <>)];
      Free : constant Steps := To_Steps (100.0);
      Space : constant Steps := Free / 3;
   begin
      Resolve ((Main => 200.0, Cross => 10.0, Justify => Space_Evenly,
                others => <>), J);
      Check ("justify: evenly, first space rounds down",
             To_Steps (J (1).Pos_Main) = Space);
      Check ("justify: evenly, second item after one more space",
             To_Steps (J (2).Pos_Main) = 2 * Space + To_Steps (50.0));
   end Test_Justify_Rounding;

   procedure Test_Shrink_Rounding is
      use Boxflex.Flex;
      --  Three 100 px items in 200 px: 100 px too much over 3 equal
      --  weights is 33.33 px each, not a whole number of steps. Each cut
      --  rounds down, and the leftover step comes off the first item.
      K    : Item_Array (1 .. 3) :=
        [others => (Basis => 100.0, Basis_Definite => True, others => <>)];
      Need : constant Steps := To_Steps (100.0);
      Cut  : constant Steps := Need / 3;
   begin
      Resolve ((Main => 200.0, Cross => 10.0, others => <>), K);
      Check ("shrink: cuts round down, leftover step from the first item",
             To_Steps (K (1).Main) = To_Steps (100.0) - Cut - 1
             and then To_Steps (K (2).Main) = To_Steps (100.0) - Cut
             and then To_Steps (K (3).Main) = To_Steps (100.0) - Cut);
      Check ("shrink: rounded line is exactly full",
             To_Steps (K (1).Main) + To_Steps (K (2).Main)
             + To_Steps (K (3).Main) = To_Steps (200.0));
   end Test_Shrink_Rounding;

begin
   Test_Geometry;
   Test_Tree;
   Test_Flex;
   Test_Layout;
   Test_Showcase;
   Test_Center_Rounding;
   Test_Edge_Cases;
   Test_Justify_Rounding;
   Test_Shrink_Rounding;

   New_Line;
   if Failures = 0 then
      Put_Line ("all tests passed");
   else
      Put_Line (Failures'Image & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Tests;
