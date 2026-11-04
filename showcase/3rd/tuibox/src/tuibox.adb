with Ada.Characters.Latin_1;
with Ada.Unchecked_Conversion;

package body Tuibox is

   function Draw_Capacity (B : Box_Access; Output : CS.chars_ptr) return C.int
     with Import, Convention => C, External_Name => "tb_draw_capacity";

   function Sizeof_Box return C.int
     with Import, Convention => C, External_Name => "tb_sizeof_box";

   function To_Address is new Ada.Unchecked_Conversion (CS.chars_ptr, System.Address);

   ----------
   -- Emit --
   ----------

   procedure Emit (B : Box_Access; Output : CS.chars_ptr; Text : String) is
      Capacity : constant Natural := Natural (Draw_Capacity (B, Output));
      Shown    : constant String := (if Text = "" then " " else Text);
      Count    : constant Natural := Natural'Min (Shown'Length, Capacity - 1);
      Target   : String (1 .. Count + 1)
        with Import, Address => To_Address (Output);
   begin
      Target (1 .. Count) := Shown (Shown'First .. Shown'First + Count - 1);
      Target (Count + 1)  := Ada.Characters.Latin_1.NUL;
   end Emit;

begin
   if Box'Object_Size /= Natural (Sizeof_Box) * System.Storage_Unit then
      raise Program_Error with "Tuibox.Box does not match ui_box_t";
   end if;
end Tuibox;
