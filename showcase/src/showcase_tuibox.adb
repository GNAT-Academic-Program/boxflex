--  The showcase, drawn on the terminal through tuibox instead of written
--  to showcase.svg: same tree, same 800x600 layout, same node colors and
--  same printed rects. The picture is scaled to fit the terminal, so it
--  gets sharper as the terminal gets bigger. The rects are printed on the
--  way out, once the terminal is back.
--
--  Keep the tree in step with showcase.adb.

with Ada.Text_IO;      use Ada.Text_IO;
with Boxflex;          use Boxflex;
with Boxflex.Geometry; use Boxflex.Geometry;
with Boxflex.Style;    use Boxflex.Style;
with Boxflex.Tree;     use Boxflex.Tree;
with Tui_Sections;     use Tui_Sections;

procedure Showcase_Tuibox is

   Root, Toolbar, Content, Sidebar, Main, Panel : Node_Id;
   Button : Node_Id;

   Available : constant Size := (Width => 800.0, Height => 600.0);

   S : Flex_Style;

begin
   --  Root: column, fills the window.
   S := Default_Style;
   S.Direction := Column;
   S.Padding   := Uniform (8.0);
   S.Gap       := 8.0;
   Add_Node (No_Node, S, "root", Root);

   --  Toolbar: row of buttons, fixed height.
   S := Default_Style;
   S.Direction := Row;
   S.Height    := Px (40.0);
   S.Gap       := 4.0;
   S.Align     := Center;
   Add_Node (Root, S, "toolbar", Toolbar);

   for I in 1 .. 5 loop
      S := Default_Style;
      S.Width  := Px (80.0);
      S.Height := Px (32.0);
      Add_Node (Toolbar, S, "button" & I'Image, Button);
   end loop;

   --  Content: row, takes the remaining height.
   S := Default_Style;
   S.Direction := Row;
   S.Grow      := 1.0;
   S.Gap       := 8.0;
   Add_Node (Root, S, "content", Content);

   --  Sidebar: fixed width.
   S := Default_Style;
   S.Width := Px (200.0);
   Add_Node (Content, S, "sidebar", Sidebar);

   --  Main: grows twice as fast as the panel.
   S := Default_Style;
   S.Grow := 2.0;
   Add_Node (Content, S, "main", Main);

   --  Panel: grows.
   S := Default_Style;
   S.Grow := 1.0;
   Add_Node (Content, S, "panel", Panel);

   Run (Design => Available);

   declare
      T : constant Layout_Tree := Current_Tree;
   begin
      Put_Line ("boxflex showcase," & T.Count'Image & " nodes in 800x600");
      for N in 1 .. T.Count loop
         declare
            R : constant Rect := Layout_Of (T, N);
         begin
            Put_Line
              ("node" & N'Image & ": x=" & R.Origin.X'Image & " y=" & R.Origin.Y'Image
               & " w=" & R.Extent.Width'Image & " h=" & R.Extent.Height'Image);
         end;
      end loop;
   end;
end Showcase_Tuibox;
