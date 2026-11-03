--  Draws the boxflex sections of a small UI on the terminal, through the
--  tuibox binding. The tree of the showcase with sizes that make sense in
--  cells (an 80x32 button would not fit on most terminals), and 1 unit =
--  1 cell. The layout follows the terminal size; hover a section for its
--  rect.
--
--  With the placeholder Boxflex.Flex.Resolve, what does not get an area
--  (grow, stretch) is not drawn, and the status line names it.

with Boxflex;       use Boxflex;
with Boxflex.Style; use Boxflex.Style;
with Tui_Sections;  use Tui_Sections;

procedure Showcase_Tui is

   Root, Toolbar, Content, Unused : Node_Id;
   S : Flex_Style;

begin
   --  Root: column, fills the terminal.
   S := Default_Style;
   S.Direction := Column;
   S.Padding   := Uniform (1.0);
   S.Gap       := 1.0;
   Add_Node (No_Node, S, "root", Root);

   --  Toolbar: row of buttons, fixed height.
   S := Default_Style;
   S.Direction := Row;
   S.Height    := Px (5.0);
   S.Gap       := 1.0;
   S.Align     := Center;
   Add_Node (Root, S, "toolbar", Toolbar);

   for I in 1 .. 3 loop
      S := Default_Style;
      S.Width  := Px (12.0);
      S.Height := Px (3.0);
      Add_Node (Toolbar, S, "button" & I'Image, Unused);
   end loop;

   --  Content: row, takes the remaining height.
   S := Default_Style;
   S.Direction := Row;
   S.Grow      := 1.0;
   S.Gap       := 1.0;
   Add_Node (Root, S, "content", Content);

   --  Sidebar: fixed width.
   S := Default_Style;
   S.Width := Px (20.0);
   Add_Node (Content, S, "sidebar", Unused);

   --  Main: grows twice as fast as the panel.
   S := Default_Style;
   S.Grow := 2.0;
   Add_Node (Content, S, "main", Unused);

   --  Panel: grows.
   S := Default_Style;
   S.Grow := 1.0;
   Add_Node (Content, S, "panel", Unused);

   Run;
end Showcase_Tui;
