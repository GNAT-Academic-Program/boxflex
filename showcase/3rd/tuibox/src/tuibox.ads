--  Ada binding to tuibox (vendor/tuibox.h), a small mouse-aware TUI
--  library. Thin: names follow the C, and Ada calls the C functions
--  directly wherever it can. tuibox_stub.c compiles the header and
--  covers the rest (macros, the fields of ui_t, the read loop).
--
--  What tuibox expects of its caller, none of it checked by the C:
--    * Coordinates are 1-based. A line is drawn only when its column is
--      below the last one and its row is below the last one, so the last
--      terminal row is never drawn on.
--    * A box's output is its lines separated by LF, each drawn at the
--      box's column. It must not run past the right edge of the terminal.
--    * Hit tests include the cell just past the right and bottom edges.
--    * Add and Text keep their string and Watch pointers: those must
--      outlive the box. Key does the same with its key string.
--    * Callbacks are called in the order boxes were added, so with nested
--      boxes the innermost one added last is called last.

with Interfaces.C;
with Interfaces.C.Strings;
with System;

package Tuibox is

   package C renames Interfaces.C;
   package CS renames Interfaces.C.Strings;

   use type C.int;

   type UI_Ref is new System.Address;
   --  A ui_t, owned by the C side.

   Null_UI : constant UI_Ref := UI_Ref (System.Null_Address);

   Center : constant C.int := -1;
   --  UI_CENTER_X, UI_CENTER_Y: as X or Y in Add, centers the box.

   ---------------------------------------------------------------------
   --  Boxes and callbacks
   ---------------------------------------------------------------------

   type Box;
   type Box_Access is access all Box with Convention => C;

   type Draw_Proc is access procedure (B : Box_Access; Output : CS.chars_ptr)
     with Convention => C;
   --  Writes the box's text to Output through Emit.

   type Mouse_Proc is access procedure (B : Box_Access; X, Y, Mouse : C.int)
     with Convention => C;
   --  Mouse is nonzero while the left button is down.

   type Key_Proc is access procedure with Convention => C;

   type Box is record
      Id       : C.int;
      X, Y     : C.int;
      W, H     : C.int;
      Screen   : C.int;
      Cache    : CS.chars_ptr;
      Watch    : CS.chars_ptr;
      Last     : C.char;
      Draw     : Draw_Proc;
      On_Click : Mouse_Proc;
      On_Hover : Mouse_Proc;
      Data1    : System.Address;
      Data2    : System.Address;
   end record
     with Convention => C;
   --  ui_box_t. Elaboration of the package body checks the size against C.

   function Contains (B : Box; X, Y : C.int) return Boolean is
     (X >= B.X and then X <= B.X + B.W and then Y >= B.Y and then Y <= B.Y + B.H);
   --  box_contains, the hit test tuibox itself uses.

   procedure Emit (B : Box_Access; Output : CS.chars_ptr; Text : String);
   --  For use in a Draw_Proc, instead of writing to Output directly. The
   --  C passes no length: after the first draw, Output only holds twice
   --  the length of the previous output, and tuibox would overflow the
   --  heap on anything longer. Emit truncates to what fits. Empty Text
   --  becomes one space, as tuibox cannot handle empty output.

   ---------------------------------------------------------------------
   --  Lifetime
   ---------------------------------------------------------------------

   function New_UI (Screen : C.int := 0) return UI_Ref
     with Import, Convention => C, External_Name => "tb_new";
   --  ui_new: raw mode, alternate screen, mouse reporting on. Also takes
   --  over SIGINT, SIGTERM and SIGWINCH, see Next_Event. Null_UI when
   --  stdin or stdout is not a terminal.

   procedure Free_UI (U : UI_Ref)
     with Import, Convention => C, External_Name => "tb_free";
   --  ui_free: frees everything and restores the terminal and the signals.

   procedure Clear (U : UI_Ref)
     with Import, Convention => C, External_Name => "ui_clear";
   --  Removes all boxes and keys, leaving and reentering the alternate
   --  screen.

   procedure Clear_Boxes (U : UI_Ref)
     with Import, Convention => C, External_Name => "tb_clear_boxes";
   --  Removes all boxes in place and restarts ids at 0. Not in tuibox.
   --  This is how to resize boxes: output sizes are fixed when a box is
   --  added (see Emit), so add them again.

   ---------------------------------------------------------------------
   --  Adding boxes and keys
   ---------------------------------------------------------------------

   function Add
     (X, Y, W, H : C.int;
      Screen     : C.int;
      Watch      : CS.chars_ptr;
      Initial    : C.char;
      Draw       : not null Draw_Proc;
      On_Click   : Mouse_Proc;
      On_Hover   : Mouse_Proc;
      Data1      : System.Address;
      Data2      : System.Address;
      U          : UI_Ref) return C.int
     with Import, Convention => C, External_Name => "ui_add";
   --  ui_add: returns the box's id, and calls Draw once before returning.
   --  With Watch set, Draw only runs again when the character it points
   --  at changes or on Redraw; with Watch null, on every draw. The box
   --  lands on the current screen, tuibox ignores Screen.

   function Text
     (X, Y     : C.int;
      Str      : CS.chars_ptr;
      Screen   : C.int;
      On_Click : Mouse_Proc;
      On_Hover : Mouse_Proc;
      U        : UI_Ref) return C.int
     with Import, Convention => C, External_Name => "ui_text";
   --  ui_text: a one-line box showing Str. Do not lengthen Str past twice
   --  its initial length.

   procedure Key (Key_String : CS.chars_ptr; F : not null Key_Proc; U : UI_Ref)
     with Import, Convention => C, External_Name => "ui_key";
   --  ui_key: calls F when input starts with Key_String.

   ---------------------------------------------------------------------
   --  Drawing
   ---------------------------------------------------------------------

   procedure Draw (U : UI_Ref)
     with Import, Convention => C, External_Name => "ui_draw";
   --  ui_draw: clears the screen and draws all boxes.

   procedure Redraw (U : UI_Ref)
     with Import, Convention => C, External_Name => "ui_redraw";
   --  ui_redraw: Draw, also calling Draw_Proc for watched boxes.

   procedure Draw_One (B : Box_Access; Flush : C.int; U : UI_Ref)
     with Import, Convention => C, External_Name => "ui_draw_one";
   --  ui_draw_one: draws over what is there, without clearing. Flush
   --  nonzero flushes stdout.

   ---------------------------------------------------------------------
   --  The event loop
   ---------------------------------------------------------------------

   type Event_Kind is (Closed, Input, Resized) with Convention => C;

   function Next_Event (U : UI_Ref) return Event_Kind
     with Import, Convention => C, External_Name => "tb_next_event";
   --  Stands in for ui_loop and ui_update. Blocks until something happens:
   --    Input:   input was read, and the mouse and key callbacks have run.
   --    Resized: the terminal changed size; Columns and Rows are current.
   --    Closed:  end of input, or SIGINT or SIGTERM. Time to call Free_UI.

   ---------------------------------------------------------------------
   --  Macros and ui_t fields
   ---------------------------------------------------------------------

   function Columns (U : UI_Ref) return C.int
     with Import, Convention => C, External_Name => "tb_columns";

   function Rows (U : UI_Ref) return C.int
     with Import, Convention => C, External_Name => "tb_rows";

   function Box_Count (U : UI_Ref) return C.int
     with Import, Convention => C, External_Name => "tb_box_count";

   function Get (Id : C.int; U : UI_Ref) return Box_Access
     with Import, Convention => C, External_Name => "tb_get";
   --  ui_get.

   procedure Set_Screen (S : C.int; U : UI_Ref)
     with Import, Convention => C, External_Name => "tb_set_screen";
   --  ui_screen: switches screen and forces the next draw to refresh.

   function Mouse (U : UI_Ref) return C.int
     with Import, Convention => C, External_Name => "tb_mouse";

   function Scroll (U : UI_Ref) return C.int
     with Import, Convention => C, External_Name => "tb_scroll";

   procedure Set_Can_Scroll (On : C.int; U : UI_Ref)
     with Import, Convention => C, External_Name => "tb_set_can_scroll";
   --  Scrolling is on after New_UI: the wheel moves all boxes vertically.

   function Center_X (W : C.int; U : UI_Ref) return C.int is
     ((Columns (U) - W) / 2);
   --  ui_center_x.

   function Center_Y (H : C.int; U : UI_Ref) return C.int is
     ((Rows (U) - H) / 2);
   --  ui_center_y.

end Tuibox;
