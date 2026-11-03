--  Draws a boxflex layout tree on the terminal through tuibox, for the
--  showcase_tui and showcase_tuibox programs. A package rather than nested
--  in a main procedure because tuibox callbacks must be library level.

with Boxflex;          use Boxflex;
with Boxflex.Geometry; use Boxflex.Geometry;
with Boxflex.Style;    use Boxflex.Style;
with Boxflex.Tree;     use Boxflex.Tree;

package Tui_Sections is

   procedure Add_Node (Parent : Node_Id; Style : Flex_Style; Name : String; N : out Node_Id);
   --  Boxflex.Tree.Insert into the tree that Run draws. Name labels the node
   --  on screen. Same rules as Insert.

   procedure Run (Design : Size := Zero_Size);
   --  Draws the tree until q, Ctrl-C or end of input, and restores the
   --  terminal on every way out. Sets a failing exit status if not on a
   --  terminal. The tree must not be empty.
   --
   --  With Design left out, 1 layout unit is 1 cell and the layout follows
   --  the terminal size. With a Design size, the layout is computed once at
   --  that size, before anything else, and the picture is scaled to fit the
   --  terminal with its proportions kept.

   function Current_Tree return Layout_Tree;
   --  The tree, with the rects of the latest layout.

end Tui_Sections;
