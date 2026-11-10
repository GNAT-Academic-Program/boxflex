--  Regression tests for the fixed-point conversion and clamping changes
--  on the spark-fixes branch. These exercise the current placeholder
--  resolver; they do not assume grow, shrink, alignment or wrapping is
--  implemented by Resolve.
with Ada.Text_IO;      use Ada.Text_IO;
with Boxflex;          use Boxflex;
with Boxflex.Flex;     use Boxflex.Flex;
with Boxflex.Style;    use Boxflex.Style;

procedure Spark_Fixes_Regression (Failures : in out Natural) is
   Quantum : constant Length := Length (Coord'Small);

   procedure Check (Name : String; Condition : Boolean) is
   begin
      if Condition then
         Put_Line ("PASS  " & Name);
      else
         Put_Line ("FAIL  " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   procedure Test_Clamping is
      I : Item :=
        (Basis_Definite => True,
         Basis => 1.25,
         Min_Main => 2.25,
         Max_Main => 3.25,
         others => <>);
      C : constant Container :=
        (Main => 20.0, Cross => 20.0, others => <>);
      Items : Item_Array (1 .. 1) :=
        [1 => (Basis_Definite => True,
               Basis => 2.0,
               Content_Cross => 1.25,
               Min_Cross => 2.25,
               Max_Cross => 1.75,
               others => <>)];
   begin
      Check ("clamp: fractional minimum", Hypothetical_Main (I) = 2.25);
      I.Basis := 4.25;
      Check ("clamp: fractional maximum", Hypothetical_Main (I) = 3.25);
      I.Min_Main := 3.25;
      I.Max_Main := 2.25;
      Check ("clamp: minimum wins conflicting limits",
             Hypothetical_Main (I) = 3.25);

      I.Basis_Definite := False;
      I.Content_Main := 2.75;
      Check ("clamp: auto basis uses content and minimum",
             Hypothetical_Main (I) = 3.25);

      Resolve (C, Items);
      Check ("clamp: cross minimum wins conflicting limits",
             Items (1).Cross = 2.25);
   end Test_Clamping;

   procedure Test_Subpixel_Round_Trips is
      C : constant Container :=
        (Main => 100.0, Cross => 100.0, others => <>);
      Items : Item_Array (1 .. 1) :=
        [1 => (Basis_Definite => True, Basis => Quantum, others => <>)];
      All_Exact : Boolean := True;
   begin
      --  Every possible fractional part, with and without whole pixels.
      --  A conversion through whole-pixel rounding fails this test.
      for Whole in 0 .. 3 loop
         for Fraction in 0 .. 255 loop
            Items (1).Margin_Main_Start :=
              Length (Whole) + Quantum * Fraction;
            Items (1).Margin_Cross_Start := Quantum * (255 - Fraction);
            Resolve (C, Items);
            if Items (1).Pos_Main /= Coord (Items (1).Margin_Main_Start)
              or else Items (1).Pos_Cross /= Coord (Items (1).Margin_Cross_Start)
            then
               All_Exact := False;
            end if;
         end loop;
      end loop;
      Check ("unit conversion: all 256 fractions of a pixel", All_Exact);
   end Test_Subpixel_Round_Trips;

   procedure Test_Fractional_Siblings is
      C : constant Container :=
        (Main => 100.0, Cross => 10.0, others => <>);
      Items : Item_Array (1 .. 3) :=
        [others => (Basis_Definite => True,
                    Basis => 10.25,
                    Content_Cross => 0.25,
                    others => <>)];
   begin
      Resolve (C, Items);
      Check ("fractional siblings: bases stay at 10.25",
             (for all K in Items'Range => Items (K).Main = 10.25));
      Check ("fractional siblings: exact cumulative positions",
             Items (1).Pos_Main = 0.0
             and then Items (2).Pos_Main = 10.25
             and then Items (3).Pos_Main = 20.5);
      Check ("fractional siblings: half-open intervals do not overlap",
             Items (1).Pos_Main + Coord (Items (1).Main) <= Items (2).Pos_Main
             and then Items (2).Pos_Main + Coord (Items (2).Main)
               <= Items (3).Pos_Main);
   end Test_Fractional_Siblings;

   procedure Test_Fractional_Margins_And_Gaps is
      C : constant Container :=
        (Main => 100.0, Cross => 10.0,
         Main_Gap => 0.25, others => <>);
      Items : Item_Array (1 .. 3) :=
        [others => (Basis_Definite => True,
                    Basis => 10.25,
                    Content_Cross => 0.375,
                    Margin_Main_Start => 0.125,
                    Margin_Main_End => 0.375,
                    Margin_Cross_Start => 0.75,
                    others => <>)];
      Original : constant Item_Array := Items;
   begin
      Resolve (C, Items);
      Check ("fractional margins/gap: first position", Items (1).Pos_Main = 0.125);
      Check ("fractional margins/gap: second position", Items (2).Pos_Main = 11.125);
      Check ("fractional margins/gap: third position", Items (3).Pos_Main = 22.125);
      Check ("fractional cross: margin and size preserved",
             (for all K in Items'Range =>
                Items (K).Pos_Cross = 0.75 and then Items (K).Cross = 0.375));
      Check ("Resolve: all item inputs unchanged",
             (for all K in Items'Range =>
                Inputs_Unchanged (Original (K), Items (K))));
   end Test_Fractional_Margins_And_Gaps;

   procedure Test_Exact_Wrap_Boundary is
      C : Container :=
        (Main => 11.25, Cross => 10.0,
         Wrap => Wrap, Main_Gap => 0.25, others => <>);
      Items : constant Item_Array (1 .. 2) :=
        [others => (Basis_Definite => True,
                    Basis => 5.25,
                    Margin_Main_Start => 0.125,
                    Margin_Main_End => 0.125,
                    others => <>)];
      Lines : Line_Array (1 .. 2);
      Count : Natural;
   begin
      --  Each outer size is 5.5. Both plus 0.25 gap = 11.25.
      Form_Lines (C, Items, Lines, Count);
      Check ("wrap: exact fractional fit stays on one line",
             Count = 1 and then Lines (1) = (First => 1, Last => 2));

      C.Main := 11.25 - Quantum;
      Form_Lines (C, Items, Lines, Count);
      Check ("wrap: one 1/256-pixel short opens second line",
             Count = 2
             and then Lines (1) = (First => 1, Last => 1)
             and then Lines (2) = (First => 2, Last => 2));

      C.Wrap := Wrap_Reverse;
      Form_Lines (C, Items, Lines, Count);
      Check ("wrap-reverse: same fractional breakpoints", Count = 2);

      C.Wrap := No_Wrap;
      Form_Lines (C, Items, Lines, Count);
      Check ("no-wrap: fractional overflow remains one line", Count = 1);
   end Test_Exact_Wrap_Boundary;

   procedure Test_Nondefault_Array_Indices is
      C : constant Container :=
        (Main => 2.0, Cross => 10.0,
         Wrap => Wrap, Main_Gap => Quantum, others => <>);
      Items : constant Item_Array (3 .. 5) :=
        [others => (Basis_Definite => True, Basis => 1.0, others => <>)];
      Lines : Line_Array (1 .. 3);
      Count : Natural;
   begin
      Form_Lines (C, Items, Lines, Count);
      Check ("wrap: non-1-based item indices",
             Count = 3
             and then Lines (1) = (First => 3, Last => 3)
             and then Lines (2) = (First => 4, Last => 4)
             and then Lines (3) = (First => 5, Last => 5));
   end Test_Nondefault_Array_Indices;

   procedure Test_Max_Node_Accumulation is
      C : constant Container :=
        (Main => 2.0, Cross => 2.0,
         Main_Gap => Quantum, others => <>);
      Items : Item_Array (1 .. Max_Nodes) :=
        [others => (Basis_Definite => True, Basis => Quantum,
                    Content_Cross => Quantum, others => <>)];
      All_Exact : Boolean := True;
      Disjoint : Boolean := True;
   begin
      Resolve (C, Items);
      for K in Items'Range loop
         if Items (K).Pos_Main /= Coord'(Coord'Small) * (2 * (K - 1))
           or else Items (K).Main /= Quantum
         then
            All_Exact := False;
         end if;
         if K < Items'Last then
            if Items (K).Pos_Main + Coord (Items (K).Main)
              > Items (K + 1).Pos_Main
            then
               Disjoint := False;
            end if;
         end if;
      end loop;
      Check ("256 items: no cumulative loss of fractional units", All_Exact);
      Check ("256 items: no overlaps from fractional rounding", Disjoint);
      Check ("256 items: last position is 510/256",
             Items (Items'Last).Pos_Main = 1.9921875);
   end Test_Max_Node_Accumulation;

   procedure Test_Saturation is
      C : constant Container :=
        (Main => Length'Last, Cross => 10.0,
         Main_Gap => Quantum, others => <>);
      Items : Item_Array (1 .. 3) :=
        [1 => (Basis_Definite => True, Basis => Length'Last,
               Margin_Cross_Start => Length'Last, others => <>),
         2 => (Basis_Definite => True, Basis => 1.0, others => <>),
         3 => (Basis_Definite => True, Basis => 1.0, others => <>)];
   begin
      Resolve (C, Items);
      Check ("saturation: first item starts at zero", Items (1).Pos_Main = 0.0);
      Check ("saturation: exact limit caps at Max_Pos",
             Items (1).Pos_Cross = Max_Pos);
      Check ("saturation: beyond limit caps at Max_Pos",
             Items (2).Pos_Main = Max_Pos and then Items (3).Pos_Main = Max_Pos);
      Check ("saturation: positions remain in allowed range",
             (for all K in Items'Range => Placed_In_Range (Items (K))));
   end Test_Saturation;

begin
   Test_Clamping;
   Test_Subpixel_Round_Trips;
   Test_Fractional_Siblings;
   Test_Fractional_Margins_And_Gaps;
   Test_Exact_Wrap_Boundary;
   Test_Nondefault_Array_Indices;
   Test_Max_Node_Accumulation;
   Test_Saturation;
end Spark_Fixes_Regression;
