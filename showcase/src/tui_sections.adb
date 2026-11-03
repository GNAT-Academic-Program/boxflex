with Ada.Characters.Latin_1;
with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Strings;              use Ada.Strings;
with Ada.Strings.Fixed;        use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;    use Ada.Strings.Unbounded;
with Ada.Strings.UTF_Encoding.Wide_Strings;
with Ada.Text_IO;
with Boxflex.Layout_Plain;
with Interfaces.C;             use Interfaces.C;
with Interfaces.C.Strings;
with System;
with System.Storage_Elements;  use System.Storage_Elements;
with Tuibox;

package body Tui_Sections is

   package CS renames Interfaces.C.Strings;

   use type Tuibox.UI_Ref;

   T     : Layout_Tree;
   Names : array (Valid_Node_Id) of Unbounded_String;

   U : Tuibox.UI_Ref := Tuibox.Null_UI;

   Hovered : Node_Id := No_Node;
   Painted : Node_Id := No_Node;
   Quit    : Boolean := False;

   Picture : Size := Zero_Size;
   --  What Run was given as Design.

   Units_Per_Column, Units_Per_Row : Long_Float := 1.0;
   --  How layout units map to cells. 1.0 unless scaling a Picture.

   --------------
   -- Add_Node --
   --------------

   procedure Add_Node (Parent : Node_Id; Style : Flex_Style; Name : String; N : out Node_Id) is
   begin
      Insert (T, Parent, Style, N);
      Names (N) := To_Unbounded_String (Name);
   end Add_Node;

   ------------------
   -- Current_Tree --
   ------------------

   function Current_Tree return Layout_Tree is (T);

   ---------------------------------------------------------------------
   --  Rendering
   ---------------------------------------------------------------------

   subtype Glyph is String (1 .. 3);
   --  Every box-drawing character is 3 bytes of UTF-8.

   function G (Code : Natural) return Glyph is
     (Ada.Strings.UTF_Encoding.Wide_Strings.Encode
        ([1 => Wide_Character'Val (Code)]));

   type Border is record
      Top_Left, Top_Right, Bottom_Left, Bottom_Right, Across, Down : Glyph;
   end record;

   Thin : constant Border :=
     (G (16#250C#), G (16#2510#), G (16#2514#), G (16#2518#), G (16#2500#), G (16#2502#));
   Bold : constant Border :=
     (G (16#2554#), G (16#2557#), G (16#255A#), G (16#255D#), G (16#2550#), G (16#2551#));

   type RGB is record
      R, G, B : Natural;
   end record;

   Fill : constant array (Valid_Node_Id range 1 .. 8) of RGB :=
     [(217, 217, 217), (163, 196, 243), (255, 229, 160), (181, 226, 181),
      (247, 183, 183), (201, 182, 242), (242, 208, 182), (182, 232, 242)];
   --  The colors of showcase.svg.

   Esc : constant Character := Ada.Characters.Latin_1.ESC;
   LF  : constant Character := Ada.Characters.Latin_1.LF;

   Reset : constant String := Esc & "[0m";

   function Img (N : Integer) return String is (Trim (N'Image, Both));

   function Fit (S : String; Width : Natural) return String is
     (if S'Length >= Width
      then S (S'First .. S'First + Width - 1)
      else S & (Width - S'Length) * ' ');
   --  S cut or space-padded to exactly Width characters.

   function Node_Of (B : Tuibox.Box_Access) return Node_Id is
     (Node_Id (To_Integer (B.Data1)));

   function Label (N : Node_Id) return String is
     (To_String (Names (N))
      & " " & Img (Integer (Layout_Of (T, N).Extent.Width))
      & "x" & Img (Integer (Layout_Of (T, N).Extent.Height)));
   --  The size is in layout units, whatever the box measures on screen.

   function Colors (N : Node_Id) return String is
      C : constant RGB := Fill (Valid_Node_Id ((Integer (N) - 1) mod Fill'Length + 1));
   begin
      return Esc & "[38;2;51;51;51;48;2;" & Img (C.R) & ";" & Img (C.G) & ";" & Img (C.B) & "m";
   end Colors;

   procedure Draw_Node (B : Tuibox.Box_Access; Output : CS.chars_ptr)
     with Convention => C;

   procedure Draw_Node (B : Tuibox.Box_Access; Output : CS.chars_ptr) is
      N     : constant Node_Id := Node_Of (B);
      W     : constant Natural := Natural (B.W);
      H     : constant Natural := Natural (B.H);
      Style : constant Border := (if N = Hovered then Bold else Thin);
      Text  : Unbounded_String;

      procedure Repeat (S : Glyph; Count : Natural) is
      begin
         for I in 1 .. Count loop
            Append (Text, S);
         end loop;
      end Repeat;

   begin
      for Row in 1 .. H loop
         Append (Text, Colors (N));
         if W < 2 or else H < 2 then
            --  No room for a frame.
            Append (Text, Fit ((if Row = 1 then Label (N) else ""), W));
         elsif Row = 1 then
            declare
               Title : constant String := " " & Label (N) & " ";
               Shown : constant Natural := Natural'Min (Title'Length, W - 2);
            begin
               Append (Text, Style.Top_Left);
               Append (Text, Fit (Title, Shown));
               Repeat (Style.Across, W - 2 - Shown);
               Append (Text, Style.Top_Right);
            end;
         elsif Row = H then
            Append (Text, Style.Bottom_Left);
            Repeat (Style.Across, W - 2);
            Append (Text, Style.Bottom_Right);
         else
            Append (Text, Style.Down);
            Append (Text, String'((W - 2) * ' '));
            Append (Text, Style.Down);
         end if;
         Append (Text, String'(Reset & LF));
      end loop;
      Tuibox.Emit (B, Output, To_String (Text));
   end Draw_Node;

   function Status_Text return String is
      Empty : Unbounded_String;
   begin
      if Hovered /= No_Node then
         declare
            R : constant Rect := Layout_Of (T, Hovered);
         begin
            return To_String (Names (Hovered))
              & ": x=" & R.Origin.X'Image & " y=" & R.Origin.Y'Image
              & " w=" & R.Extent.Width'Image & " h=" & R.Extent.Height'Image;
         end;
      end if;

      for N in 1 .. T.Count loop
         if Is_Empty (Layout_Of (T, N)) then
            Append (Empty, " " & Names (N));
         end if;
      end loop;
      return "q quits, hover for a rect. " & Img (Integer (T.Count)) & " nodes"
        & (if Empty = "" then "" else ", no area:" & To_String (Empty));
   end Status_Text;

   procedure Draw_Status (B : Tuibox.Box_Access; Output : CS.chars_ptr)
     with Convention => C;

   procedure Draw_Status (B : Tuibox.Box_Access; Output : CS.chars_ptr) is
   begin
      Tuibox.Emit (B, Output, Esc & "[7m" & Fit (Status_Text, Natural (B.W)) & Reset);
   end Draw_Status;

   ---------------------------------------------------------------------
   --  Input
   ---------------------------------------------------------------------

   procedure On_Hover_Node (B : Tuibox.Box_Access; X, Y, Mouse : int)
     with Convention => C;

   procedure On_Hover_Node (B : Tuibox.Box_Access; X, Y, Mouse : int) is
      pragma Unreferenced (Mouse);
   begin
      --  Tuibox.Contains takes in one cell too many on the far edges.
      --  Boxes come in id order, so the deepest node is the last to set this.
      if X < B.X + B.W and then Y < B.Y + B.H then
         Hovered := Node_Of (B);
      end if;
   end On_Hover_Node;

   procedure On_Hover_Status (B : Tuibox.Box_Access; X, Y, Mouse : int)
     with Convention => C;

   procedure On_Hover_Status (B : Tuibox.Box_Access; X, Y, Mouse : int) is
      pragma Unreferenced (B, X, Y, Mouse);
   begin
      Hovered := No_Node;
   end On_Hover_Status;

   procedure On_Quit with Convention => C;

   procedure On_Quit is
   begin
      Quit := True;
   end On_Quit;

   ---------------------------------------------------------------------
   --  Layout to boxes
   ---------------------------------------------------------------------

   function Cell_Column (V : Coord) return Integer is
     (Integer (Long_Float (V) / Units_Per_Column));

   function Cell_Row (V : Coord) return Integer is
     (Integer (Long_Float (V) / Units_Per_Row));

   --  Fits the current terminal size and rebuilds the boxes. The last two
   --  rows are left out: tuibox never draws on the last row of the
   --  terminal, and the row before holds the status line.

   procedure Layout_Boxes is
      Columns : constant Integer := Integer (Tuibox.Columns (U));
      Rows    : constant Integer := Integer (Tuibox.Rows (U));
      Room    : constant Integer := Integer'Max (Rows - 2, 0);
      Limit_X : Integer := 0;
      Limit_Y : Integer := 0;
      Id      : int;
   begin
      if Picture = Zero_Size then
         Boxflex.Layout_Plain.Compute
           (T, (Width => Boxflex.Length (Columns), Height => Boxflex.Length (Room)));
      elsif Columns > 0 and then Room > 0 then
         --  Keep the proportions, with cells twice as tall as they are wide.
         Units_Per_Column :=
           Long_Float'Max (Long_Float (Picture.Width) / Long_Float (Columns),
                           Long_Float (Picture.Height) / Long_Float (2 * Room));
         Units_Per_Row := 2.0 * Units_Per_Column;
      end if;

      --  Nothing shows outside the root, as nothing shows outside an SVG.
      if Columns > 0 and then Room > 0 then
         Limit_X := Integer'Min (Cell_Column (Right (Layout_Of (T, 1))), Columns);
         Limit_Y := Integer'Min (Cell_Row (Bottom (Layout_Of (T, 1))), Room);
      end if;

      Hovered := No_Node;
      Painted := No_Node;
      Tuibox.Clear_Boxes (U);

      for N in 1 .. T.Count loop
         declare
            R      : constant Rect := Layout_Of (T, N);
            --  Round the edges rather than the extents, so that boxes
            --  which touch in the layout touch on screen.
            Left   : constant Integer := Integer'Max (Cell_Column (R.Origin.X), 0);
            Top    : constant Integer := Integer'Max (Cell_Row (R.Origin.Y), 0);
            Width  : constant Integer := Integer'Min (Cell_Column (Right (R)), Limit_X) - Left;
            Height : constant Integer := Integer'Min (Cell_Row (Bottom (R)), Limit_Y) - Top;
         begin
            if Width > 0 and then Height > 0 then
               Id := Tuibox.Add
                 (X        => int (Left + 1),
                  Y        => int (Top + 1),
                  W        => int (Width),
                  H        => int (Height),
                  Screen   => 0,
                  Watch    => CS.Null_Ptr,
                  Initial  => nul,
                  Draw     => Draw_Node'Access,
                  On_Click => null,
                  On_Hover => On_Hover_Node'Access,
                  Data1    => To_Address (Integer_Address (N)),
                  Data2    => System.Null_Address,
                  U        => U);
            end if;
         end;
      end loop;

      if Rows >= 2 and then Columns >= 1 then
         Id := Tuibox.Add
           (X        => 1,
            Y        => int (Rows - 1),
            W        => int (Columns),
            H        => 1,
            Screen   => 0,
            Watch    => CS.Null_Ptr,
            Initial  => nul,
            Draw     => Draw_Status'Access,
            On_Click => null,
            On_Hover => On_Hover_Status'Access,
            Data1    => System.Null_Address,
            Data2    => System.Null_Address,
            U        => U);
      end if;

      pragma Unreferenced (Id);
      Tuibox.Draw (U);
   end Layout_Boxes;

   --  Paints over the screen. Tuibox.Draw would clear it first and flicker.

   procedure Repaint is
      Count : constant int := Tuibox.Box_Count (U);
   begin
      for I in 0 .. Count - 1 loop
         Tuibox.Draw_One (Tuibox.Get (I, U), Boolean'Pos (I = Count - 1), U);
      end loop;
      Painted := Hovered;
   end Repaint;

   ---------
   -- Run --
   ---------

   procedure Run (Design : Size := Zero_Size) is
   begin
      Picture := Design;
      if Picture /= Zero_Size then
         Boxflex.Layout_Plain.Compute (T, Picture);
      end if;

      U := Tuibox.New_UI;
      if U = Tuibox.Null_UI then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, Ada.Command_Line.Command_Name & " needs a terminal");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      Tuibox.Set_Can_Scroll (0, U);
      Tuibox.Key (CS.New_String ("q"), On_Quit'Access, U);
      Layout_Boxes;

      while not Quit loop
         case Tuibox.Next_Event (U) is
            when Tuibox.Closed =>
               Quit := True;
            when Tuibox.Resized =>
               Layout_Boxes;
            when Tuibox.Input =>
               if Hovered /= Painted then
                  Repaint;
               end if;
         end case;
      end loop;

      Tuibox.Free_UI (U);

   exception
      when E : others =>
         --  Back to a usable terminal first, or the message is lost.
         if U /= Tuibox.Null_UI then
            Tuibox.Free_UI (U);
         end if;
         Ada.Exceptions.Reraise_Occurrence (E);
   end Run;

end Tui_Sections;
