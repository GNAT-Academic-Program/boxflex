--  The showcase: the acceptance test for the project.
--
--  Builds a small UI tree (a toolbar over a three-column content
--  area), lays it out, prints every node's rect, and writes
--  showcase.svg so you can look at the result.
--
--  With the placeholder Boxflex.Layout, everything but the root is a
--  zero rect and the SVG is a single grey box. When the algorithm is
--  implemented, the picture should match what a browser produces for
--  the same CSS (see showcase/reference.html).

with Ada.Text_IO;      use Ada.Text_IO;
with Boxflex;          use Boxflex;
with Boxflex.Geometry; use Boxflex.Geometry;
with Boxflex.Style;    use Boxflex.Style;
with Boxflex.Tree;     use Boxflex.Tree;
with Boxflex.Layout_Plain;

procedure Showcase is

   T : Layout_Tree;

   Root, Toolbar, Content, Sidebar, Main, Panel : Node_Id;
   Button : Node_Id;

   Available : constant Size := (Width => 800.0, Height => 600.0);

   Fill : constant array (Valid_Node_Id range 1 .. 8) of String (1 .. 7) :=
     ["#d9d9d9", "#a3c4f3", "#ffe5a0", "#b5e2b5", "#f7b7b7",
      "#c9b6f2", "#f2d0b6", "#b6e8f2"];

   procedure Put (N : Node_Id) is
      R : constant Rect := Layout_Of (T, N);
   begin
      Put_Line
        ("node" & N'Image & ": x=" & R.Origin.X'Image & " y=" & R.Origin.Y'Image
         & " w=" & R.Extent.Width'Image & " h=" & R.Extent.Height'Image);
   end Put;

   procedure Write_Svg (Path : String) is
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      Put_Line (F, "<svg xmlns=""http://www.w3.org/2000/svg"" width=""800"" height=""600"">");
      for N in 1 .. T.Count loop
         declare
            R : constant Rect := Layout_Of (T, N);
            C : constant String :=
              Fill (Valid_Node_Id (((Integer (N) - 1) mod Fill'Length) + 1));
         begin
            Put_Line
              (F, "  <rect x=""" & R.Origin.X'Image & """ y=""" & R.Origin.Y'Image
               & """ width=""" & R.Extent.Width'Image
               & """ height=""" & R.Extent.Height'Image
               & """ fill=""" & C & """ stroke=""#333"" stroke-width=""1""/>");
         end;
      end loop;
      Put_Line (F, "</svg>");
      Close (F);
   end Write_Svg;

   S : Flex_Style;

begin
   --  Root: column, fills the window.
   S := Default_Style;
   S.Direction := Column;
   S.Padding   := Uniform (8.0);
   S.Gap       := 8.0;
   Insert (T, No_Node, S, Root);

   --  Toolbar: row of buttons, fixed height.
   S := Default_Style;
   S.Direction := Row;
   S.Height    := Px (40.0);
   S.Gap       := 4.0;
   S.Align     := Center;
   Insert (T, Root, S, Toolbar);

   for I in 1 .. 30 loop
      S := Default_Style;
      S.Width  := Px (80.0);
      S.Height := Px (32.0);
      Insert (T, Toolbar, S, Button);
   end loop;

   --  Content: row, takes the remaining height.
   S := Default_Style;
   S.Direction := Row;
   S.Grow      := 1.0;
   S.Gap       := 8.0;
   Insert (T, Root, S, Content);

   --  Sidebar: fixed width.
   S := Default_Style;
   S.Width := Px (200.0);
   Insert (T, Content, S, Sidebar);

   --  Main: grows twice as fast as the panel.
   S := Default_Style;
   S.Grow := 2.0;
   Insert (T, Content, S, Main);

   --  Panel: grows.
   S := Default_Style;
   S.Grow := 1.0;
   Insert (T, Content, S, Panel);

   Boxflex.Layout_Plain.Compute (T, Available);

   Put_Line ("boxflex showcase," & T.Count'Image & " nodes in 800x600");
   for N in 1 .. T.Count loop
      Put (N);
   end loop;

   Write_Svg ("showcase.svg");
   Put_Line ("wrote showcase.svg");
end Showcase;
