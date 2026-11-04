package body Boxflex.Flex with SPARK_Mode is

   --  Sums over many items can exceed Coord. Accumulate in units of
   --  Coord'Small in a wide integer instead.
   type Units is range -2 ** 62 .. 2 ** 62 - 1;

   Length_Unit : constant Length := Length'Small;
   Coord_Unit : constant Coord := Coord'Small;
   Ratio_Unit : constant Ratio := Ratio'Small;
   --  One step of each fixed-point type, used to convert to and from Units.

   function To_Units (L : Length) return Units is
     (Units (L / Length_Unit));

   function Grow_Units (R : Ratio) return Units is
      (Units (R / Ratio_Unit));
   --  A Ratio as a whole number of its 1/1024 steps (1.0 is 1024).

   function To_Length (U : Units) return Length is
     (Length_Unit * Integer (U))
       with Pre => U >= 0 and then U <= To_Units (Length'Last);
   --  Units back to a Length. The caller guarantees it fits.

   function Clamp (V, Lo, Hi : Length) return Length is
      (if V < Lo or else Hi < Lo then Lo elsif V > Hi then Hi else V);
   --  Min wins over max when they conflict (Hi < Lo), as in CSS.

   -----------------------
   -- Hypothetical_Main --
   -----------------------

   function Hypothetical_Main (I : Item) return Length is
     (Clamp ((if I.Basis_Definite then I.Basis else I.Content_Main),
             I.Min_Main, I.Max_Main));

   ----------------
   -- Form_Lines --
   ----------------

   procedure Form_Lines
     (C     : Container;
      Items : Item_Array;
      Lines : out Line_Array;
      Count : out Natural)
   is
      Limit : constant Units := To_Units (C.Main);
      Gap   : constant Units := To_Units (C.Main_Gap);
      Used  : Units := 0;
      Outer : Units;
   begin
      Lines := [others => (First => 0, Last => 0)];
      Count := 0;

      for K in Items'Range loop
         pragma Loop_Invariant (Count <= K - Items'First);
         pragma Loop_Invariant (Count = 0 or else Lines (Count).Last = K - 1);
         pragma Loop_Invariant (Used >= 0);

         Outer := To_Units (Items (K).Margin_Main_Start)
                  + To_Units (Hypothetical_Main (Items (K)))
                  + To_Units (Items (K).Margin_Main_End);

         if Count = 0
           or else (C.Wrap /= No_Wrap and then Used + Gap + Outer > Limit)
         then
            --  Open a new line. A line always takes at least one item.
            Count := Count + 1;
            Lines (Count) := (First => K, Last => K);
            Used := Outer;
         else
            Lines (Count).Last := K;
            Used := Used + Gap + Outer;
         end if;
      end loop;
   end Form_Lines;

   ---------------------
   -- Distribute_Grow --
   ---------------------

   procedure Distribute_Grow (C : Container; Items : in out Item_Array) is
      Max_U : constant Units := To_Units (Length'Last); --  2**30
      Step_Max : constant Units := 4 * Max_U; --  most one item adds to used
      Used : Units := 0;
      Total_Grow : Units := 0;
      Free : Units;
      Given : Units := 0;
      Share : Units;
   begin
      --  1. How much of the line is already taken, and how much grow is there?
      for K in Items'Range loop
         pragma Loop_Invariant (Used in 0 .. Units (K - Items'First) * Step_Max);
         pragma Loop_Invariant
            (Total_Grow in 0 .. Units (K - Items'First) * Grow_Units (Ratio'Last));
         Used := Used + To_Units (Items (K).Margin_Main_Start)
                        + To_Units (Items (K).Main)
                        + To_Units (Items (K).Margin_Main_End);
         if K > Items'First then
            Used := Used + To_Units (C.Main_Gap);
         end if;
         Total_Grow := Total_Grow + Grow_Units (Items (K).Grow);
      end loop;
      Free := To_Units (C.Main) - Used;
      --  Nothing to share, or nobody wants it.
      if Free <= 0 or else Total_Grow = 0 then
         return;
      end if;
      --  2. Each item gets Free * Grow / Total_Grow (integer division
      --     rounds down, so a few units may be left over).
      for K in Items'Range loop
         pragma Loop_Invariant (Given in 0 .. Free);
         pragma Loop_Invariant
            (for all J in Items'Range =>
               Inputs_Unchanged (Items'Loop_Entry (J), Items (J))
               and then Items (J).Main >= Items'Loop_Entry (J).Main);
         Share := Free * Grow_Units (Items (K).Grow) / Total_Grow;
         --  Never more than what is left, nor more than a Length holds.
         --  Neither cap changes the result for a real line.
         Share := Units'Min (Share, Free - Given);
         Share := Units'Min (Share, Max_U - To_Units (Items (K).Main));
         Items (K).Main := To_Length (To_Units (Items (K).Main) + Share);
         Given := Given + Share;
      end loop;
      --  3. Hand out the leftover units one at a time, first growing item
      --    first, until the line is filled exactly.
      for K in Items'Range loop
         pragma Loop_Invariant (Given in 0 .. Free);
         pragma Loop_Invariant
            (for all J in Items'Range =>
               Inputs_Unchanged (Items'Loop_Entry (J), Items (J))
               and then Items (J).Main >= Items'Loop_Entry (J).Main);
         exit when Given = Free;
         if Items (K).Grow > 0.0 and then Items (K).Main < Length'Last then
            Items (K).Main := To_Length (To_Units (Items (K).Main) + 1);
            Given := Given + 1;
         end if;
      end loop;
   end Distribute_Grow;

   -------------------
   -- Cross helpers --
   -------------------

   --  The item's own Self wins; Auto means "use the container's Align"
   function Effective_Align (C : Container; I : Item) return Align_Self is
      (if I.Self /= Auto then I.Self
       else (case C.Align is
               when Stretch => Stretch,
               when Flex_Start   => Flex_Start,
               when Flex_End     => Flex_End,
               when Center  => Center,
               when Baseline => Baseline));

   function Room (C : Container; I : Item) return Units is
      (To_Units (C.Cross) - To_Units (I.Margin_Cross_Start)
                          - To_Units (I.Margin_Cross_End));
   --  Cross space left for the item once its cross margins are taken
   --  Can be negative if the margins are bigger than the container.

   function Free_Cross (C : Container; I : Item) return Units is
      (Room (C, I) - To_Units (I.Cross));
   --  Room the item does not use. Negative if the item is too big.

   function Cross_Offset (C : Container; I : Item) return Units is
      (if Free_Cross (C, I) <= 0 then 0 --  too big: pin to the start for now
       else (case Effective_Align (C, I) is
               when Center     => Free_Cross (C, I) / 2,
               when Flex_End   => Free_Cross (C, I),
               when Auto | Stretch | Flex_Start | Baseline   => 0)); --  TODO: baseline alignment
   --  How far past the Margin_Cross_Start the item sits on the cross axis.
   --  Baseline is out of scope for v1 (ARCHITECTURE.md), so it acts
   --  like Flex_Start for now.

   -------------
   -- Justify --
   -------------

   function Main_Free (C : Container; Items : Item_Array) return Units
     with Pre => Items'Length <= Max_Nodes;
   --  Main-axis space the line does not use, after grow. Negative when
   --  the items overflow the container.

   function Main_Free (C : Container; Items : Item_Array) return Units is
      Used : Units := 0;
   begin
      for K in Items'Range loop
         pragma Loop_Invariant (Used in 0 .. Units (K - Items'First) * 4 * 2 ** 30);
         Used := Used + To_Units (Items (K).Margin_Main_Start)
                      + To_Units (Items (K).Main)
                      + To_Units (Items (K).Margin_Main_End);
         if K > Items'First then
            Used := Used + To_Units (C.Main_Gap);
         end if;
      end loop;
      return To_Units (C.Main) - Used;
   end Main_Free;

   -----------------------
   -- Distribute_Shrink --
   -----------------------

   procedure Distribute_Shrink (C : Container; Items : in out Item_Array) is
      Limit  : constant Units := 2 ** 22;
      --  Weights are scaled below this, so Need * weight fits in Units.
      Frozen : array (Items'Range) of Boolean;
      Free, Need, Total, Scale, Cut, Given : Units;
      Violated : Boolean;

      function Weight (I : Item) return Units is
        (Grow_Units (I.Shrink) * To_Units (I.Main));
      --  Scaled shrink factor: Shrink times the item's size (CSS 9.7).
   begin
      --  Items that cannot shrink are frozen from the start.
      for K in Items'Range loop
         Frozen (K) := Items (K).Shrink = 0.0
                       or else Items (K).Main <= Items (K).Min_Main;
      end loop;

      --  Each round either finishes or freezes at least one more item,
      --  so Items'Length rounds are always enough.
      for Round in Items'Range loop
         Free := Main_Free (C, Items);
         exit when Free >= 0;
         Need := -Free;

         Total := 0;
         for K in Items'Range loop
            if not Frozen (K) then
               Total := Total + Weight (Items (K));
            end if;
         end loop;
         exit when Total = 0;

         Scale := 1;
         while Total / Scale >= Limit loop
            Scale := Scale * 2;
         end loop;

         --  Would any item go below its minimum? Freeze those at the min.
         Violated := False;
         for K in Items'Range loop
            if not Frozen (K) then
               Cut := Need * (Weight (Items (K)) / Scale) / (Total / Scale);
               if To_Units (Items (K).Main) - Cut < To_Units (Items (K).Min_Main) then
                  Items (K).Main := Items (K).Min_Main;
                  Frozen (K) := True;
                  Violated := True;
               end if;
            end if;
         end loop;

         if not Violated then
            Given := 0;
            for K in Items'Range loop
               if not Frozen (K) then
                  Cut := Need * (Weight (Items (K)) / Scale) / (Total / Scale);
                  Items (K).Main := To_Length (To_Units (Items (K).Main) - Cut);
                  Given := Given + Cut;
               end if;
            end loop;
            --  Rounding left a few steps: take them one at a time.
            for K in Items'Range loop
               exit when Given >= Need;
               if not Frozen (K) and then Items (K).Main > Items (K).Min_Main then
                  Items (K).Main := To_Length (To_Units (Items (K).Main) - 1);
                  Given := Given + 1;
               end if;
            end loop;
            exit;
         end if;
      end loop;
   end Distribute_Shrink;

   -------------
   -- Resolve --
   -------------

   --  Steps 1, 3 (grow and shrink, single line), 4 (stretch),
   --  5 (justify, single line), 6 (align, single line) and 7.
   --  Still missing: wrap, reversed directions.

   procedure Resolve (C : Container; Items : in out Item_Array) is
      Cursor : Units := 0;
      Between : Units := 0;
      Gap    : constant Units := To_Units (C.Main_Gap);
      Max_U : constant Units := To_Units (Length'Last);
      --   Max_Pos = Coord'Last - Length'Last, and Length'Last = 2**22
      --   so a position of at most Length'Last (as a Coord) is safe

      function Pos (U : Units) return Coord is
         (if U > Max_U then Max_Pos else Coord_Unit * Integer (U))
         with Pre => U >= 0;
      --   Units to Coord, saturating at Max_Pos.

   begin
   --  Step 1: every item starts at its hypothetical main size.
      for K in Items'Range loop
         Items (K).Main := Hypothetical_Main (Items (K));
         Items (K).Cross :=
            Clamp (Items (K).Content_Cross, Items (K).Min_Cross, Items (K).Max_Cross);
      end loop;

      --   Step 3: Share free space by Grow, or overflow by Shrink
      --   (single line only for now)
      if C.Wrap = No_Wrap then
         Distribute_Grow (C, Items);
         Distribute_Shrink (C, Items);
      end if;

      --  Step 4: Stretch. No declared cross size + Stretch = fill the line.
      for K in Items'Range loop
         if Effective_Align (C, Items (K)) = Stretch
         and then not Items (K).Cross_Definite
         then
            declare
               R : constant Units := Room (C, Items (K));
            begin
               Items (K).Cross :=
                  Clamp ((if R <= 0 then 0.0 else To_Length (R)),
                         Items (K).Min_Cross, Items (K).Max_Cross);
            end;
         end if;
      end loop;

      --  Step 5: Justify. Lead = space before the first item, Between =
      --  extra space added after each gap. Single line only for now.
      declare
         Free : constant Units :=
           (if C.Wrap = No_Wrap then Main_Free (C, Items) else 0);
         N    : constant Units := Units (Items'Length);
      begin
         if Free > 0 and then N > 0 then
            case C.Justify is
               when Flex_Start => null;
               when Flex_End => Cursor := Free;
               when Center => Cursor := Free / 2;
               when Space_Between =>
                  if N > 1 then
                     Between := Free / (N - 1);
                  end if;
               when Space_Around =>
                  Between := Free / N;
                  Cursor := Between / 2;
               when Space_Evenly =>
                  Between := Free / (N + 1);
                  Cursor := Between;
            end case;
         end if;
      end;

      --  Step 7: place items one after the other along the main axis.
      for K in Items'Range loop
         pragma Loop_Invariant (Cursor >= 0);
         pragma Loop_Invariant
            (for all J in Items'First .. K - 1 => Placed_In_Range (Items (J)));

         Cursor := Cursor + To_Units (Items (K).Margin_Main_Start);
         Items (K).Pos_Main := Pos (Cursor);
         Items (K).Pos_Cross :=
            Pos (To_Units (Items (K).Margin_Cross_Start) + Cross_Offset (C, Items (K)));

         Cursor := Cursor + To_Units (Items (K).Main)
                           + To_Units (Items (K).Margin_Main_End) + Gap + Between;
      end loop;
   end Resolve;

end Boxflex.Flex;