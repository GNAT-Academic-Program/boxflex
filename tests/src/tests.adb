--  Unit tests. Plain Ada, no framework: each Check prints PASS/FAIL
--  and the program exits non-zero if anything failed. Add a test for
--  every behaviour you implement; CI runs this on every push.
--
--  Tests marked "pending" document the expected result once
--  Boxflex.Layout_Plain.Compute is implemented. Un-comment them as you go.

with Ada.Command_Line;
with Ada.Text_IO;      use Ada.Text_IO;
with Boxflex;          use Boxflex;
with Boxflex.Geometry; use Boxflex.Geometry;
with Boxflex.Style;    use Boxflex.Style;
with Boxflex.Tree;     use Boxflex.Tree;
with Boxflex.Flex;
with Boxflex.Layout_Plain;
with Spark_Fixes_Regression;

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

      --  Testing of fractional units
      It (1) := 
         (Basis_Definite => False,
         Content_Main => 50.0,
         Margin_Main_Start => 2.25,
         Margin_Main_End => 2.75,
         others => <>);
      
      Resolve (C, It);
      Check ("resolve: fractional sizing", It (1).Main = 50.0 and then It (2).Main = 80.0);
      Check ("resolve: fractional margin", It (1).Pos_Main = 2.25 and then It (2).Pos_Main = 55.0);
      --  pending, once grow is implemented:
      --  It (1).Grow := 1.0; It (2).Grow := 1.0; It (2).Max_Main := Length'Last;
      --  Resolve (C, It);
      --  Check ("grow splits free space", It (1).Main = 72.5 and It (2).Main = 122.5);
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

      --  pending: two equal growers split the main axis
      --  Check ("A is left half",  Layout_Of (T, A) = Make (0.0,   0.0, 100.0, 100.0));
      --  Check ("B is right half", Layout_Of (T, B) = Make (100.0, 0.0, 100.0, 100.0));
      --  Check ("siblings do not overlap",
      --         not Overlaps (Layout_Of (T, A), Layout_Of (T, B)));
      --  Check ("children inside parent",
      --         Contains (Layout_Of (T, R), Layout_Of (T, A))
      --         and Contains (Layout_Of (T, R), Layout_Of (T, B)));
   end Test_Layout;

begin
   Test_Geometry;
   Test_Tree;
   Test_Flex;
   Spark_Fixes_Regression (Failures);
   Test_Layout;

   New_Line;
   if Failures = 0 then
      Put_Line ("all tests passed");
   else
      Put_Line (Failures'Image & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Tests;
