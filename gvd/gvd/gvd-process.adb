-----------------------------------------------------------------------
--                   GVD - The GNU Visual Debugger                   --
--                                                                   --
--                      Copyright (C) 2000-2002                      --
--                              ACT-Europe                           --
--                                                                   --
-- GVD is free  software;  you can redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this library; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with System; use System;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Unchecked_Conversion;

with Glib; use Glib;

with Gdk.Color;           use Gdk.Color;
with Gdk.Font;            use Gdk.Font;
with Gdk.Event;           use Gdk.Event;
with Gdk.Types.Keysyms;     use Gdk.Types.Keysyms;

with Gtk;                 use Gtk;
with Gtk.Arguments;       use Gtk.Arguments;
with Gtk.Check_Menu_Item; use Gtk.Check_Menu_Item;
with Gtk.Clist;           use Gtk.Clist;
with Gtk.Dialog;          use Gtk.Dialog;
with Gtk.Enums;           use Gtk.Enums;
with Gtk.Handlers;        use Gtk.Handlers;
with Gtk.Item_Factory;    use Gtk.Item_Factory;
with Gtk.Text;            use Gtk.Text;
with Gtk.Menu;            use Gtk.Menu;
with Gtk.Menu_Item;       use Gtk.Menu_Item;
with Gtk.Widget;          use Gtk.Widget;
with Gtk.Notebook;        use Gtk.Notebook;
with Gtk.Label;           use Gtk.Label;
with Gtk.Object;          use Gtk.Object;
with Gtk.Window;          use Gtk.Window;
with Gtk.Adjustment;      use Gtk.Adjustment;
with Gtk.Scrolled_Window; use Gtk.Scrolled_Window;

with Gtk.Extra.PsFont;    use Gtk.Extra.PsFont;

with Gtkada.Canvas;       use Gtkada.Canvas;
with Gtkada.Dialogs;      use Gtkada.Dialogs;
with Gtkada.Handlers;     use Gtkada.Handlers;
with Gtkada.MDI;          use Gtkada.MDI;
with Gtkada.Types;        use Gtkada.Types;

with Ada.Characters.Handling;  use Ada.Characters.Handling;

with GNAT.Regpat; use GNAT.Regpat;
with GNAT.OS_Lib; use GNAT.OS_Lib;

with Odd_Intl;                   use Odd_Intl;
with Process_Tab_Pkg;            use Process_Tab_Pkg;
with Display_Items;              use Display_Items;
with Debugger.Gdb;               use Debugger.Gdb;
with Debugger.Jdb;               use Debugger.Jdb;
with Process_Proxies;            use Process_Proxies;
with Items.Simples;              use Items.Simples;
with Breakpoints_Editor;         use Breakpoints_Editor;
with Pixmaps_IDE;                use Pixmaps_IDE;
with String_Utils;               use String_Utils;
with Basic_Types;                use Basic_Types;
with GUI_Utils;                  use GUI_Utils;
with Dock_Paned;                 use Dock_Paned;

with GVD.Canvas;                 use GVD.Canvas;
with GVD.Code_Editors;           use GVD.Code_Editors;
with GVD.Dialogs;                use GVD.Dialogs;
with GVD.Explorer;               use GVD.Explorer;
with GVD.Main_Window;            use GVD.Main_Window;
with GVD.Preferences;            use GVD.Preferences;
with GVD.Text_Box.Source_Editor; use GVD.Text_Box.Source_Editor;
with GVD.Trace;                  use GVD.Trace;
with GVD.Types;                  use GVD.Types;
with GVD.Window_Settings;        use GVD.Window_Settings;
with Language_Handlers;          use Language_Handlers;

package body GVD.Process is

   Enable_Block_Search    : constant Boolean := False;
   --  Whether we should try to find the block of a variable when printing
   --  it, and memorize it with the item.

   Process_User_Data_Name : constant String := "gvd_editor_to_process";
   --  User data string.
   --  ??? Should use some quarks, which would be just a little bit faster.

   type Call_Stack_Record is record
      Process : Debugger_Process_Tab;
      Mask    : Stack_List_Mask;
   end record;

   package Call_Stack_Cb is new Gtk.Handlers.User_Callback
     (Gtk_Menu_Item_Record, Call_Stack_Record);

   package Canvas_Event_Handler is new Gtk.Handlers.Return_Callback
     (Debugger_Process_Tab_Record, Boolean);

   function To_Main_Debug_Window is new
     Ada.Unchecked_Conversion (System.Address, GVD_Main_Window);

   --  This pointer will keep a pointer to the C 'class record' for
   --  gtk. To avoid allocating memory for each widget, this may be done
   --  only once, and reused
   Class_Record : GObject_Class := Uninitialized_Class;

   --  Array of the signals created for this widget
   Signals : Chars_Ptr_Array :=
     "process_stopped" + "context_changed";

   Graph_Cmd_Format : constant Pattern_Matcher := Compile
     ("graph\s+(print|display)\s+(`([^`]+)`|""([^""]+)"")?(.*)",
      Case_Insensitive);
   --  Format of the graph print commands, and how to parse them

   Graph_Cmd_Type_Paren          : constant := 1;
   Graph_Cmd_Expression_Paren    : constant := 3;
   Graph_Cmd_Quoted_Paren        : constant := 4;
   Graph_Cmd_Rest_Paren          : constant := 5;
   --  Indexes of the parentheses pairs in Graph_Cmd_Format for each of the
   --  relevant fields.

   Graph_Cmd_Dependent_Format : constant Pattern_Matcher := Compile
     ("\s+dependent\s+on\s+(\d+)\s*", Case_Insensitive);
   --  Partial analyses of the last part of a graph command

   Graph_Cmd_Link_Format : constant Pattern_Matcher := Compile
     ("\s+link_name\s+(.+)", Case_Insensitive);
   --  Partial analyses of the last part of a graph command

   Graph_Cmd_Format2 : constant Pattern_Matcher := Compile
     ("graph\s+(enable|disable)\s+display\s+(.*)", Case_Insensitive);
   --  Second possible set of commands.

   Graph_Cmd_Format3 : constant Pattern_Matcher := Compile
     ("graph\s+undisplay\s+(.*)", Case_Insensitive);
   --  Third possible set of commands

   -----------------------
   -- Local Subprograms --
   -----------------------

   procedure Change_Mask
     (Widget : access Gtk_Menu_Item_Record'Class;
      Mask   : Call_Stack_Record);
   --  Toggle the display of a specific column in the Stack_List window.

   function Debugger_Contextual_Menu
     (Process  : access Debugger_Process_Tab_Record'Class)
      return Gtk.Menu.Gtk_Menu;
   --  Create (if necessary) and reset the contextual menu used in the
   --  debugger command window.

   procedure First_Text_Output_Filter
     (Descriptor : GNAT.Expect.Process_Descriptor'Class;
      Str        : String;
      Window     : System.Address);
   --  Standard handler to add gdb's output to the debugger window.
   --  Simply strip CR characters if needed and then call Text_Output_Filter

   procedure Text_Output_Filter
     (Descriptor : GNAT.Expect.Process_Descriptor'Class;
      Str        : String;
      Window     : System.Address);
   --  Real handler called by First_Text_Output_Filter

   function Debugger_Button_Press
     (Process : access Debugger_Process_Tab_Record'Class;
      Event    : Gdk.Event.Gdk_Event) return Boolean;
   --  Callback for all the button press events in the debugger command window.
   --  This is used to display the contexual menu.

   procedure Process_Graph_Cmd
     (Process : access Debugger_Process_Tab_Record'Class;
      Cmd     : String);
   --  Parse and process a "graph print" or "graph display" command

   procedure Process_View_Cmd
     (Process : access Debugger_Process_Tab_Record'Class;
      Cmd     : String);
   --  Parse and process a "view".
   --  Syntax recognized: view (source|asm|source_asm)

   procedure Preferences_Changed
     (Editor : access Gtk.Widget.Gtk_Widget_Record'Class);
   --  Called when the preferences have changed, and the editor should be
   --  redisplayed with the new setup.

   function On_Data_Paned_Delete_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean;
   --  Callback for the "delete_event" signal on the Data window.

   procedure On_Stack_List_Select_Row
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args);
   --  Callback for the "select_row" signal on the stack list.

   function On_Stack_List_Button_Press_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean;
   --  Callback for the "button_press" signal on the stack list.

   function On_Command_Scrolledwindow_Delete_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean;
   --  Callback for the "delete_event" signal on the command window.

   procedure On_Debugger_Text_Insert_Text
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args);
   --  Callback for the "insert_text" signal on the command window.

   procedure On_Debugger_Text_Delete_Text
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args);
   --  Callback for the "delete_text" signal on the command window.

   function On_Debugger_Text_Key_Press_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean;
   --  Callback for the "key_press" signal on the command window.

   procedure On_Debugger_Text_Grab_Focus
     (Object : access Gtk_Widget_Record'Class);
   --  Callback for the "grab_focus" signal on the command window.

   --------------------------------
   -- On_Data_Paned_Delete_Event --
   --------------------------------

   function On_Data_Paned_Delete_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean
   is
      pragma Unreferenced (Params);
      --  Arg1 : Gdk_Event := To_Event (Params, 1);
      Process : constant Debugger_Process_Tab :=
        Debugger_Process_Tab (Object);

   begin
      if Process.Window.Standalone then
         --  Do not delete the data window if in stand alone mode.
         return True;
      else
         Process.Data_Paned := null;
         return False;
      end if;
   end On_Data_Paned_Delete_Event;

   ------------------------------
   -- On_Stack_List_Select_Row --
   ------------------------------

   procedure On_Stack_List_Select_Row
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args)
   is
      Frame     : Gint := To_Gint (Params, 1) + 1;
      Process   : constant Debugger_Process_Tab :=
        Debugger_Process_Tab (Object);

   begin
      Stack_Frame (Process.Debugger, Positive (Frame), GVD.Types.Visible);
   end On_Stack_List_Select_Row;

   --------------------------------------
   -- On_Stack_List_Button_Press_Event --
   --------------------------------------

   function On_Stack_List_Button_Press_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean
   is
      Arg1    : Gdk_Event := To_Event (Params, 1);
      Process : constant Debugger_Process_Tab :=
        Debugger_Process_Tab (Object);

   begin
      if Get_Button (Arg1) = 3
        and then Get_Event_Type (Arg1) = Button_Press
      then
         Popup (Call_Stack_Contextual_Menu (Process),
                Button        => Gdk.Event.Get_Button (Arg1),
                Activate_Time => Gdk.Event.Get_Time (Arg1));
         Emit_Stop_By_Name (Process.Stack_List, "button_press_event");
         return True;
      end if;
      return False;
   end On_Stack_List_Button_Press_Event;

   --------------------------------------------
   -- On_Command_Scrolledwindow_Delete_Event --
   --------------------------------------------

   function On_Command_Scrolledwindow_Delete_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean
   is
      pragma Unreferenced (Params);
      --  Arg1 : Gdk_Event := To_Event (Params, 1);
      Process : constant Debugger_Process_Tab :=
        Debugger_Process_Tab (Object);

   begin
      if Process.Window.Standalone then
         --  Do not delete the command window if in stand alone mode.
         return True;
      else
         Process.Command_Scrolledwindow := null;
         return False;
      end if;
   end On_Command_Scrolledwindow_Delete_Event;

   ----------------------------------
   -- On_Debugger_Text_Insert_Text --
   ----------------------------------

   procedure On_Debugger_Text_Insert_Text
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args)
   is
      Arg1 : String := To_String (Params, 1);
      Arg2 : Gint := To_Gint (Params, 2);
      Position : Address := To_Address (Params, 3);

      Top  : constant Debugger_Process_Tab := Debugger_Process_Tab (Object);

      type Guint_Ptr is access all Guint;
      function To_Guint_Ptr is new
        Ada.Unchecked_Conversion (Address, Guint_Ptr);

      use GVD.Process;
      use String_History;

   begin
      if To_Guint_Ptr (Position).all < Top.Edit_Pos then
         --  Move the cursor back to the end of the window, so that the text
         --  is correctly inserted. This is more user friendly that simply
         --  forbidding any key.

         if Is_Graphic (Arg1 (Arg1'First)) then
            Output_Text
              (Top, Arg1 (Arg1'First .. Arg1'First + Integer (Arg2) - 1),
               Is_Command => True);
            Set_Position
              (Top.Debugger_Text, Gint (Get_Length (Top.Debugger_Text)));
         end if;

         Emit_Stop_By_Name (Top.Debugger_Text, "insert_text");

      else
         if Arg1 (Arg1'First) = ASCII.LF then
            declare
               S : constant String :=
                 Get_Chars (Top.Debugger_Text, Gint (Top.Edit_Pos));
            begin
               --  If the command is empty, then we simply reexecute the last
               --  user command. Note that, with gdb, we can't simply send
               --  LF, since some internal commands might have been executed
               --  in the middle.

               Wind (Top.Window.Command_History, Forward);

               if S'Length = 0
                 and then not Command_In_Process (Get_Process (Top.Debugger))
               then
                  begin
                     Find_Match (Top.Window.Command_History,
                                 Natural (Get_Num (Top)),
                                 Backward);
                     Process_User_Command
                       (Top, Get_Current
                        (Top.Window.Command_History).Command.all,
                        Output_Command => True,
                        Mode => User);
                  exception
                     --  No previous command => do nothing
                     when No_Such_Item =>
                        null;
                  end;

               else
                  --  Insert the newline character after the user's command.
                  Output_Text (Top, "" & ASCII.LF);

                  --  Process the command.
                  Process_User_Command (Top, S, Mode => User);
               end if;

               --  Move the cursor after the output of the command.
               if Get_Process (Top.Debugger) /= null then
                  Top.Edit_Pos := Get_Length (Top.Debugger_Text);
                  Set_Position (Top.Debugger_Text, Gint (Top.Edit_Pos));
               end if;

               --  Stop propagating this event.
               Emit_Stop_By_Name (Top.Debugger_Text, "insert_text");
            end;
         end if;
      end if;
   end On_Debugger_Text_Insert_Text;

   ----------------------------------
   -- On_Debugger_Text_Delete_Text --
   ----------------------------------

   procedure On_Debugger_Text_Delete_Text
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args)
   is
      Arg1 : Gint := To_Gint (Params, 1);
      Arg2 : Gint := To_Gint (Params, 2);
      Top  : constant Debugger_Process_Tab := Debugger_Process_Tab (Object);

   begin
      if Arg2 <= Gint (Top.Edit_Pos) then
         Emit_Stop_By_Name (Top.Debugger_Text, "delete_text");
      elsif Arg1 < Gint (Top.Edit_Pos) then
         Delete_Text (Top.Debugger_Text, Gint (Top.Edit_Pos), Arg2);
      end if;
   end On_Debugger_Text_Delete_Text;

   --------------------------------------
   -- On_Debugger_Text_Key_Press_Event --
   --------------------------------------

   function On_Debugger_Text_Key_Press_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean
   is
      Arg1  : Gdk_Event := To_Event (Params, 1);
      Top   : Debugger_Process_Tab := Debugger_Process_Tab (Object);
      use type Gdk.Types.Gdk_Key_Type;

      procedure Output (Text : String);
      --  Insert Text in using Top.Debugger_Text and Text_Font

      procedure Output (Text : String) is
      begin
         Insert
           (Top.Debugger_Text, Top.Debugger_Text_Font,
            Black (Get_System), Null_Color, Text);
      end Output;

      use String_History;

   begin
      case Get_Key_Val (Arg1) is
         when GDK_Up | GDK_Down =>
            Emit_Stop_By_Name (Top.Debugger_Text, "key_press_event");

            declare
               D : Direction;
            begin
               if Get_Key_Val (Arg1) = GDK_Up then
                  D := Backward;
               else
                  D := Forward;
               end if;

               Find_Match
                 (Top.Window.Command_History, Integer (Get_Num (Top)), D);
               Delete_Text
                 (Top.Debugger_Text,
                  Gint (Top.Edit_Pos),
                  Gint (Get_Length (Top.Debugger_Text)));
               Output_Text
                 (Top, Get_Current (Top.Window.Command_History).Command.all,
                  Is_Command => True);
               Set_Position
                 (Top.Debugger_Text, Gint (Get_Length (Top.Debugger_Text)));
               return True;

            exception
               when No_Such_Item =>
                  if D = Forward then
                     Delete_Text
                       (Top.Debugger_Text,
                        Gint (Top.Edit_Pos),
                        Gint (Get_Length (Top.Debugger_Text)));
                  end if;

                  return True;
            end;

         when GDK_Tab =>
            Emit_Stop_By_Name (Top.Debugger_Text, "key_press_event");

            declare
               C     : constant String :=
                 Get_Chars (Top.Debugger_Text, Gint (Top.Edit_Pos));
               S     : String_Array := Complete (Top.Debugger, C);
               Max   : Integer := 0;
               Min   : Integer := 0;
               Width : constant Integer := 100;
               --  Width of the console window, in number of characters;
               Num  : Integer;

            begin
               if S'First > S'Last then
                  null;
               elsif S'First = S'Last then
                  declare
                     New_Command : constant String := S (S'First).all;
                     Dummy       : Boolean;
                  begin
                     Dummy :=
                       Backward_Delete (Top.Debugger_Text, Guint (C'Length));
                     Output_Text (Top, New_Command & " ", Is_Command => True);
                     Set_Position
                       (Top.Debugger_Text,
                        Get_Position (Top.Debugger_Text) +
                          New_Command'Length + 1);
                  end;

               else
                  --  Find the lengths of the longest and shortest
                  --  words in the list;

                  Min := S (S'First)'Length;

                  for J in S'Range loop
                     if S (J)'Length > Max then
                        Max := S (J)'Length;
                     end if;

                     if S (J)'Length < Min then
                        Min := S (J)'Length;
                     end if;
                  end loop;

                  --  Compute number of words to display per line.
                  Num := Width / (Max + 2);

                  --  Print the list of possibilities.
                  Freeze (Top.Debugger_Text);
                  Output ((1 => ASCII.LF));

                  for J in S'Range loop
                     if Num = 0 then
                        --  The maximal length is greater than Width, do not
                        --  attempt to be smart.

                        if J /= S'First then
                           Output ((1 => ASCII.LF));
                        end if;

                        Output (S (J).all);
                     else
                        if (J mod Num) = 0 then
                           Output ((1 => ASCII.LF));
                        end if;

                        Output (S (J).all);

                        for K in S (J)'Length .. Max + 2 loop
                           Output (" ");
                        end loop;
                     end if;
                  end loop;

                  Output ((1 => ASCII.LF));
                  Thaw (Top.Debugger_Text);

                  --  Display the prompt and the common prefix.
                  Display_Prompt (Top.Debugger);

                  Output_Text (Top, C, Is_Command => True);
                  Set_Position
                    (Top.Debugger_Text,
                     Get_Position (Top.Debugger_Text) + C'Length);
               end if;

               Free (S);
            end;

            return True;

         when others =>
            null;
      end case;

      return False;
   end On_Debugger_Text_Key_Press_Event;

   ---------------------------------
   -- On_Debugger_Text_Grab_Focus --
   ---------------------------------

   procedure On_Debugger_Text_Grab_Focus
     (Object : access Gtk_Widget_Record'Class)
   is
      use String_History;
   begin
      Wind (Debugger_Process_Tab (Object).Window.Command_History, Forward);
   end On_Debugger_Text_Grab_Focus;

   -----------------------
   -- Add_Regexp_Filter --
   -----------------------

   procedure Add_Regexp_Filter
     (Process : access Debugger_Process_Tab_Record'Class;
      Filter  : Regexp_Filter_Function;
      Regexp  : Pattern_Matcher) is
   begin
      Process.Filters :=
        new Regexp_Filter_List_Elem'
          (Filter => Filter,
           Regexp => new Pattern_Matcher' (Regexp),
           Next   => Process.Filters);
   end Add_Regexp_Filter;

   --------------------------------
   -- Call_Stack_Contextual_Menu --
   --------------------------------

   function Call_Stack_Contextual_Menu
     (Process : access Debugger_Process_Tab_Record'Class)
      return Gtk.Menu.Gtk_Menu
   is
      Check : Gtk_Check_Menu_Item;
   begin
      --  Destroy the old menu (We need to recompute the state of the toggle
      --  buttons)

      if Process.Call_Stack_Contextual_Menu /= null then
         Destroy (Process.Call_Stack_Contextual_Menu);
      end if;

      Gtk_New (Process.Call_Stack_Contextual_Menu);
      Gtk_New (Check, Label => -"Frame Number");
      Set_Active (Check, (Process.Backtrace_Mask and Frame_Num) /= 0);
      Append (Process.Call_Stack_Contextual_Menu, Check);
      Call_Stack_Cb.Connect
        (Check, "activate",
         Call_Stack_Cb.To_Marshaller (Change_Mask'Access),
         (Debugger_Process_Tab (Process), Frame_Num));

      Gtk_New (Check, Label => -"Program Counter");
      Set_Active (Check, (Process.Backtrace_Mask and Program_Counter) /= 0);
      Append (Process.Call_Stack_Contextual_Menu, Check);
      Call_Stack_Cb.Connect
        (Check, "activate",
         Call_Stack_Cb.To_Marshaller (Change_Mask'Access),
         (Debugger_Process_Tab (Process), Program_Counter));

      Gtk_New (Check, Label => -"Subprogram Name");
      Set_Active (Check, (Process.Backtrace_Mask and Subprog_Name) /= 0);
      Append (Process.Call_Stack_Contextual_Menu, Check);
      Call_Stack_Cb.Connect
        (Check, "activate",
         Call_Stack_Cb.To_Marshaller (Change_Mask'Access),
         (Debugger_Process_Tab (Process), Subprog_Name));

      Gtk_New (Check, Label => -"Parameters");
      Set_Active (Check, (Process.Backtrace_Mask and Params) /= 0);
      Append (Process.Call_Stack_Contextual_Menu, Check);
      Call_Stack_Cb.Connect
        (Check, "activate",
         Call_Stack_Cb.To_Marshaller (Change_Mask'Access),
         (Debugger_Process_Tab (Process), Params));

      Gtk_New (Check, Label => -"File Location");
      Set_Active (Check, (Process.Backtrace_Mask and File_Location) /= 0);
      Append (Process.Call_Stack_Contextual_Menu, Check);
      Call_Stack_Cb.Connect
        (Check, "activate",
         Call_Stack_Cb.To_Marshaller (Change_Mask'Access),
         (Debugger_Process_Tab (Process), File_Location));

      Show_All (Process.Call_Stack_Contextual_Menu);
      return Process.Call_Stack_Contextual_Menu;
   end Call_Stack_Contextual_Menu;

   -----------------
   -- Change_Mask --
   -----------------

   procedure Change_Mask
     (Widget : access Gtk_Menu_Item_Record'Class;
      Mask   : Call_Stack_Record)
   is
      pragma Unreferenced (Widget);
   begin
      Mask.Process.Backtrace_Mask :=
        Mask.Process.Backtrace_Mask xor Mask.Mask;
      Show_Call_Stack_Columns (Mask.Process);
   end Change_Mask;

   -------------
   -- Convert --
   -------------

   function Convert
     (Main_Debug_Window : access GVD_Main_Window_Record'Class;
      Descriptor        : GNAT.Expect.Process_Descriptor'Class)
      return Debugger_Process_Tab
   is
      Page      : Gtk_Widget;
      Num_Pages : constant Gint :=
        Gint (Page_List.Length
          (Get_Children (Main_Debug_Window.Process_Notebook)));
      Process   : Debugger_Process_Tab;

   begin
      --  For all the process tabs in the application, check whether
      --  this is the one associated with Pid.

      for Page_Num in 0 .. Num_Pages - 1 loop
         Page := Get_Nth_Page (Main_Debug_Window.Process_Notebook, Page_Num);
         if Page /= null then
            Process := Process_User_Data.Get (Page);

            --  Note: The process might have been already killed when this
            --  function is called.

            if Get_Descriptor
              (Get_Process (Process.Debugger)).all = Descriptor
            then
               return Process;
            end if;
         end if;
      end loop;

      raise Debugger_Not_Found;

   exception
      when Constraint_Error =>
         raise Debugger_Not_Found;
   end Convert;

   -------------
   -- Convert --
   -------------

   function Convert
     (Text : access GVD.Code_Editors.Code_Editor_Record'Class)
      return Debugger_Process_Tab is
   begin
      return Process_User_Data.Get (Text, Process_User_Data_Name);
   end Convert;

   -------------
   -- Convert --
   -------------

   function Convert
     (Main_Debug_Window : access Gtk.Window.Gtk_Window_Record'Class;
      Debugger : access Debugger_Root'Class) return Debugger_Process_Tab is
   begin
      return Convert (GVD_Main_Window (Main_Debug_Window),
                      Get_Descriptor (Get_Process (Debugger)).all);
   end Convert;

   ------------------------------
   -- Debugger_Contextual_Menu --
   ------------------------------

   function Debugger_Contextual_Menu
     (Process : access Debugger_Process_Tab_Record'Class)
      return Gtk.Menu.Gtk_Menu
   is
      Mitem : Gtk_Menu_Item;
   begin
      if Process.Contextual_Menu /= null then
         return Process.Contextual_Menu;
      end if;

      Gtk_New (Process.Contextual_Menu);
      Gtk_New (Mitem, Label => -"Info");
      Set_State (Mitem, State_Insensitive);
      Append (Process.Contextual_Menu, Mitem);
      Show_All (Process.Contextual_Menu);
      return Process.Contextual_Menu;
   end Debugger_Contextual_Menu;

   -----------------
   -- Output_Text --
   -----------------

   procedure Output_Text
     (Process      : Debugger_Process_Tab;
      Str          : String;
      Is_Command   : Boolean := False;
      Set_Position : Boolean := False)
   is
      Matched : GNAT.Regpat.Match_Array (0 .. 0);
      Start   : Positive := Str'First;

   begin
      Freeze (Process.Debugger_Text);
      Set_Point (Process.Debugger_Text, Get_Length (Process.Debugger_Text));

      --  Should all the string be highlighted ?

      if Is_Command then
         Insert
           (Process.Debugger_Text,
            Process.Debugger_Text_Font,
            Process.Debugger_Text_Highlight_Color,
            Null_Color,
            Str);

      --  If not, highlight only parts of it

      else
         while Start <= Str'Last loop
            Match (Highlighting_Pattern (Process.Debugger),
                   Str (Start .. Str'Last),
                   Matched);

            if Matched (0) /= No_Match then
               if Matched (0).First - 1 >= Start then
                  Insert (Process.Debugger_Text,
                          Process.Debugger_Text_Font,
                          Black (Get_System),
                          Null_Color,
                          Str (Start .. Matched (0).First - 1));
               end if;

               Insert (Process.Debugger_Text,
                       Process.Debugger_Text_Font,
                       Process.Debugger_Text_Highlight_Color,
                       Null_Color,
                       Str (Matched (0).First .. Matched (0).Last));
               Start := Matched (0).Last + 1;

            else
               Insert (Process.Debugger_Text,
                       Process.Debugger_Text_Font,
                       Black (Get_System),
                       Null_Color,
                       Str (Start .. Str'Last));
               Start := Str'Last + 1;
            end if;
         end loop;
      end if;

      Thaw (Process.Debugger_Text);

      --  Force a scroll of the text widget. This speeds things up a lot for
      --  programs that output a lot of things, since its takes a very long
      --  time for the text widget to scroll smoothly otherwise (lots of
      --  events...)
      Set_Value (Get_Vadj (Process.Debugger_Text),
                 Get_Upper (Get_Vadj (Process.Debugger_Text)) -
                   Get_Page_Size (Get_Vadj (Process.Debugger_Text)));

      --  Note: we can not systematically modify Process.Edit_Pos in this
      --  function, since otherwise the history (up and down keys in the
      --  command window) will not work properly.

      if Set_Position then
         Process.Edit_Pos := Get_Length (Process.Debugger_Text);
         Gtk.Text.Set_Point (Process.Debugger_Text, Process.Edit_Pos);
         Gtk.Text.Set_Position
           (Process.Debugger_Text, Gint (Process.Edit_Pos));
      end if;
   end Output_Text;

   ------------------------
   -- Final_Post_Process --
   ------------------------

   procedure Final_Post_Process
     (Process : access Debugger_Process_Tab_Record'Class;
      Mode    : GVD.Types.Command_Type)
   is
      File_First  : Natural := 0;
      File_Last   : Positive;
      Line        : Natural := 0;
      First, Last : Natural := 0;
      Addr_First  : Natural := 0;
      Addr_Last   : Natural;
      Widget      : Gtk_Widget;
      Pc          : Address_Type;
      Pc_Length   : Natural := 0;
      Frame_Info  : Frame_Info_Type := Location_Not_Found;

      Call_Stack  : Gtk_Check_Menu_Item;

   begin
      if Process.Post_Processing or else Process.Current_Output = null then
         return;
      end if;

      Process.Post_Processing := True;

      if Get_Parse_File_Name (Get_Process (Process.Debugger)) then
         Found_File_Name
           (Process.Debugger,
            Process.Current_Output
              (Process.Current_Output'First .. Process.Current_Output_Pos - 1),
            File_First, File_Last, First, Last, Line,
            Addr_First, Addr_Last);

         --  We have to make a temporary copy of the address, since
         --  the call to Load_File below might modify the current_output
         --  of the process, and thus make the address inaccessible afterwards.

         if Addr_First /= 0 then
            Pc_Length := Addr_Last - Addr_First + Pc'First;
            Pc (Pc'First .. Pc_Length) :=
              Process.Current_Output (Addr_First .. Addr_Last);
         end if;
      end if;

      --  Do we have a file name or line number indication?

      if File_First /= 0 then
         --  Override the language currently defined in the editor.

         declare
            File_Name : constant String :=
              Process.Current_Output (File_First .. File_Last);
         begin
            Set_Current_Language
              (Process.Editor_Text, Get_Language_From_File
                 (Process.Window.Lang_Handler,
                  "." & File_Extension (File_Name)));

            Load_File (Process.Editor_Text, File_Name);
         end;
      end if;

      if Line /= 0
        and then Mode /= Internal
      then
         Set_Line (Process.Editor_Text, Line, Process => Gtk_Widget (Process));
      end if;

      --  Change the current assembly source displayed, before updating
      --  the breakpoints. Otherwise, they won't be correctly updated for the
      --  newly displayed frame.

      if Addr_First /= 0 then
         Set_Address
           (Process.Editor_Text,
            Pc (Pc'First .. Pc_Length));
      end if;

      Widget := Get_Widget (Process.Window.Factory, -"/Data/Call Stack");

      if Widget = null then
         --  This means that GVD is part of Glide
         Widget :=
           Get_Widget (Process.Window.Factory, -"/Debug/Data/Call Stack");
      end if;

      Call_Stack := Gtk_Check_Menu_Item (Widget);

      Found_Frame_Info (Process.Debugger,
                        Process.Current_Output.all,
                        First, Last, Frame_Info);

      if Get_Active (Call_Stack) then
         if Frame_Info = Location_Found then
            Highlight_Stack_Frame
              (Process,
               Integer'Value (Process.Current_Output (First .. Last)));
         end if;
      end if;

      if Frame_Info = No_Debug_Info then
         Show_Message (Process.Editor_Text,
                       "There is no debug information for this frame.");
      end if;

      --  Last step is to update the breakpoints once all the rest has been
      --  set up correctly.
      --  If there is no breakpoint defined, we force an update.

      if File_First /= 0 then
         if Process.Breakpoints = null then
            Update_Breakpoints (Process, Force => True);

         elsif Process.Breakpoints'Length > 0 then
            Update_Breakpoints
              (Process.Editor_Text, Process.Breakpoints.all);
         end if;
      end if;

      Process.Post_Processing := False;
      Free (Process.Current_Output);
   end Final_Post_Process;

   ------------------------------
   -- First_Text_Output_Filter --
   ------------------------------

   procedure First_Text_Output_Filter
     (Descriptor : GNAT.Expect.Process_Descriptor'Class;
      Str        : String;
      Window     : System.Address) is
   begin
      if Need_To_Strip_CR then
         Text_Output_Filter (Descriptor, Strip_CR (Str), Window);
      else
         Text_Output_Filter (Descriptor, Str, Window);
      end if;
   end First_Text_Output_Filter;

   ------------------------
   -- Text_Output_Filter --
   ------------------------

   procedure Text_Output_Filter
     (Descriptor : GNAT.Expect.Process_Descriptor'Class;
      Str        : String;
      Window     : System.Address)
   is
      Process        : constant Debugger_Process_Tab :=
        Convert (To_Main_Debug_Window (Window), Descriptor);
      Tmp_Str        : GNAT.OS_Lib.String_Access;
      Current_Filter : Regexp_Filter_List;
      Matched        : Match_Array (0 .. Max_Paren_Count);
      First, Last    : Natural := 0;
      Last_Match     : Natural := 0;
      Min_Size       : Natural;
      New_Size       : Natural;

   begin
      --  Concatenate current output

      if Process.Current_Output = null then
         Process.Current_Output := new String (1 .. 1024);
         Process.Current_Output_Pos := 1;
         Process.Last_Match := 0;
      end if;

      Min_Size := Process.Current_Output_Pos + Str'Length;

      if Process.Current_Output'Last < Min_Size then
         New_Size := Process.Current_Output'Length * 2;

         while New_Size < Min_Size loop
            New_Size := New_Size * 2;
         end loop;

         Tmp_Str := new String (1 .. New_Size);
         Tmp_Str (1 .. Process.Current_Output_Pos - 1) :=
           Process.Current_Output (1 .. Process.Current_Output_Pos - 1);
         Free (Process.Current_Output);
         Process.Current_Output := Tmp_Str;
      end if;

      Process.Current_Output
        (Process.Current_Output_Pos ..
         Process.Current_Output_Pos + Str'Length - 1) := Str;
      Process.Current_Output_Pos := Process.Current_Output_Pos + Str'Length;

      --  Process the filters

      Current_Filter := Process.Filters;

      while Current_Filter /= null loop
         Match
           (Current_Filter.Regexp.all,
            Process.Current_Output
              (Process.Last_Match + 1 .. Process.Current_Output'Last),
            Matched);

         if Matched (0) /= No_Match then
            if Matched (0).Last > Last_Match then
               Last_Match := Matched (0).Last;
            end if;

            Current_Filter.Filter
              (Process, Process.Current_Output.all, Matched);
         end if;

         Current_Filter := Current_Filter.Next;
      end loop;

      if Last_Match /= 0 then
         Process.Last_Match := Last_Match;
      end if;

      --  Do not show the output if we have an internal or hidden command

      case Get_Command_Mode (Get_Process (Process.Debugger)) is
         when User | GVD.Types.Visible =>
            --  Strip every line starting with ^Z^Z.
            --  Note that this is GDB specific ???

            Outer_Loop :
            for J in Str'First + 1 .. Str'Last loop
               if Str (J) = ASCII.SUB and then Str (J - 1) = ASCII.SUB then
                  First := J - 1;

                  for K in J + 1 .. Str'Last loop
                     if Str (K) = ASCII.LF then
                        Last := K;
                        exit Outer_Loop;
                     end if;
                  end loop;

                  Last := Str'Last;
                  exit Outer_Loop;
               end if;
            end loop Outer_Loop;

            if First = 0 then
               Output_Text (Process, Str, Set_Position => True);
            else
               Output_Text (Process, Str (Str'First .. First - 1));
               Output_Text
               (Process, Str (Last + 1 .. Str'Last), Set_Position => True);
            end if;

         when Hidden | Internal =>
            null;
      end case;
   end Text_Output_Filter;

   ---------------------------
   -- Debugger_Button_Press --
   ---------------------------

   function Debugger_Button_Press
     (Process : access Debugger_Process_Tab_Record'Class;
      Event    : Gdk.Event.Gdk_Event) return Boolean is
   begin
      if Get_Button (Event) = 3 then
         Popup (Debugger_Contextual_Menu (Process),
                Button        => Get_Button (Event),
                Activate_Time => Get_Time (Event));
         Emit_Stop_By_Name (Process.Debugger_Text, "button_press_event");

         return True;
      end if;

      return False;
   end Debugger_Button_Press;

   -------------
   -- Gtk_New --
   -------------

   procedure Gtk_New
     (Process : out Debugger_Process_Tab;
      Window  : access GVD.Main_Window.GVD_Main_Window_Record'Class;
      Source  : GVD.Text_Box.Source_Editor.Source_Editor) is
   begin
      Process := new Debugger_Process_Tab_Record;
      Initialize (Process, Window, Source);
   end Gtk_New;

   -----------------------
   -- Setup_Data_Window --
   -----------------------

   procedure Setup_Data_Window
     (Process : access Debugger_Process_Tab_Record'Class)
   is
      Label : Gtk_Label;
      Child : MDI_Child;
   begin
      Gtk_New_Hpaned (Process.Data_Paned);
      Set_Position (Process.Data_Paned, 200);
      Set_Size_Request (Process.Data_Paned, 100, 100);
      Gtkada.Handlers.Return_Callback.Object_Connect
        (Process.Data_Paned, "delete_event",
         On_Data_Paned_Delete_Event'Access, Process);

      Gtk_New (Process.Stack_Scrolledwindow);
      Set_Policy
        (Process.Stack_Scrolledwindow, Policy_Automatic, Policy_Automatic);
      Add (Process.Data_Paned, Process.Stack_Scrolledwindow);

      Gtk_New (Process.Stack_List, 5);
      Set_Selection_Mode (Process.Stack_List, Selection_Single);
      Set_Show_Titles (Process.Stack_List, True);
      Set_Events (Process.Stack_List,
        Button_Press_Mask or
        Button_Release_Mask);
      Process.Stack_List_Select_Id :=
        Widget_Callback.Object_Connect
          (Process.Stack_List, "select_row",
           On_Stack_List_Select_Row'Access, Process);
      Gtkada.Handlers.Return_Callback.Object_Connect
        (Process.Stack_List, "button_press_event",
         On_Stack_List_Button_Press_Event'Access, Process);
      Add (Process.Stack_Scrolledwindow, Process.Stack_List);

      Gtk_New (Label, -("Num"));
      Set_Column_Widget (Process.Stack_List, 0, Label);

      Gtk_New (Label, -("PC"));
      Set_Column_Widget (Process.Stack_List, 1, Label);

      Gtk_New (Label, -("Subprogram"));
      Set_Column_Widget (Process.Stack_List, 2, Label);

      Gtk_New (Label, -("Parameters"));
      Set_Column_Widget (Process.Stack_List, 3, Label);

      Gtk_New (Label, -("Location"));
      Set_Column_Widget (Process.Stack_List, 4, Label);

      Gtk_New (Process.Data_Scrolledwindow);
      Set_Policy
        (Process.Data_Scrolledwindow, Policy_Automatic, Policy_Automatic);
      Add (Process.Data_Paned, Process.Data_Scrolledwindow);

      --  Create the canvas for this process tab.

      Gtk_New (GVD_Canvas (Process.Data_Canvas),
               Process.Window.Main_Accel_Group);
      Add (Process.Data_Scrolledwindow, Process.Data_Canvas);
      Set_Process (GVD_Canvas (Process.Data_Canvas), Process);
      Widget_Callback.Connect
        (Process.Data_Canvas, "background_click",
         Widget_Callback.To_Marshaller (On_Background_Click'Access));
      Widget_Callback.Object_Connect
        (Process.Window, "preferences_changed",
         Widget_Callback.To_Marshaller
           (GVD.Canvas.Preferences_Changed'Access),
         Process.Data_Canvas);
      Align_On_Grid (Process.Data_Canvas, True);

      --  Initialize the call stack list

      Show_Call_Stack_Columns (Process);

      --  Initialize the canvas

      Configure
        (Process.Data_Canvas,
         Annotation_Height => Get_Pref (Annotation_Font_Size));

      Child := Put (Process.Process_Mdi, Process.Data_Paned);
      Set_Title (Child, "Debugger Data");
      Set_Dock_Side (Child, Top);
      Dock_Child (Child);
   end Setup_Data_Window;

   --------------------------
   -- Setup_Command_Window --
   --------------------------

   procedure Setup_Command_Window
     (Process : access Debugger_Process_Tab_Record'Class)
   is
      Child : MDI_Child;
   begin
      Gtk_New (Process.Command_Scrolledwindow);
      Set_Policy (Process.Command_Scrolledwindow, Policy_Never, Policy_Always);
      Gtkada.Handlers.Return_Callback.Object_Connect
        (Process.Command_Scrolledwindow, "delete_event",
         On_Command_Scrolledwindow_Delete_Event'Access, Process);

      Gtk_New (Process.Debugger_Text);
      Set_Editable (Process.Debugger_Text, True);
      Widget_Callback.Object_Connect
        (Process.Debugger_Text, "insert_text",
         On_Debugger_Text_Insert_Text'Access, Process);
      Process.Delete_Text_Handler_Id := Widget_Callback.Object_Connect
        (Process.Debugger_Text, "delete_text",
         On_Debugger_Text_Delete_Text'Access, Process);
      Gtkada.Handlers.Return_Callback.Object_Connect
        (Process.Debugger_Text, "key_press_event",
         On_Debugger_Text_Key_Press_Event'Access, Process);
      Widget_Callback.Object_Connect
        (Process.Debugger_Text, "grab_focus",
         Widget_Callback.To_Marshaller (On_Debugger_Text_Grab_Focus'Access),
         Process);
      Add (Process.Command_Scrolledwindow, Process.Debugger_Text);

      --  Set up the command window for the contextual menus

      Add_Events (Process.Debugger_Text, Button_Press_Mask);
      Canvas_Event_Handler.Object_Connect
        (Process.Debugger_Text, "button_press_event",
         Canvas_Event_Handler.To_Marshaller (Debugger_Button_Press'Access),
         Process);

      --  Add debugger console and source viewer

      Child := Put (Process.Process_Mdi, Process.Command_Scrolledwindow);
      Set_Title (Child, "Debugger Console");
      Set_Dock_Side (Child, Bottom);
      Dock_Child (Child);
   end Setup_Command_Window;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize
     (Process : access Debugger_Process_Tab_Record'Class;
      Window  : access GVD.Main_Window.GVD_Main_Window_Record'Class;
      Source  : GVD.Text_Box.Source_Editor.Source_Editor)
   is
      Menu_Item     : Gtk_Menu_Item;
      Label         : Gtk_Label;
      Debugger_List : Debugger_List_Link;
      Debugger_Num  : Natural := 1;
      Length        : Guint;
      Widget        : Gtk_Widget;

   begin
      --  Process.Window needs to be set before calling Initialize which
      --  might need to reference it.

      Process.Window := Window.all'Access;
      Process_Tab_Pkg.Initialize (Process);
      Initialize_Class_Record
        (Process, Signals, Class_Record,
         Type_Name => "GvdDebuggerProcessTab");

      Menu_Item :=
        Gtk_Menu_Item (Get_Widget (Window.Factory, '/' & (-"Window")));
      Set_Submenu (Menu_Item, Create_Menu (Process.Process_Mdi));

      Widget_Callback.Connect
        (Process, "process_stopped",
         Widget_Callback.To_Marshaller (On_Canvas_Process_Stopped'Access));
      Widget_Callback.Connect
        (Process, "context_changed",
         Widget_Callback.To_Marshaller (On_Canvas_Process_Stopped'Access));
      Widget_Callback.Connect
        (Process, "process_stopped",
         Widget_Callback.To_Marshaller (On_Stack_Process_Stopped'Access));
      Widget_Callback.Connect
        (Process, "context_changed",
         Widget_Callback.To_Marshaller (On_Stack_Process_Stopped'Access));
      Widget_Callback.Connect
        (Process, "process_stopped",
         Widget_Callback.To_Marshaller (On_Task_Process_Stopped'Access));
      Widget_Callback.Connect
        (Process, "process_stopped",
         Widget_Callback.To_Marshaller (On_Thread_Process_Stopped'Access));

      --  Connect the various components so that they are refreshed when the
      --  preferences are changed

      Widget_Callback.Object_Connect
        (Process.Window, "preferences_changed",
         Widget_Callback.To_Marshaller
           (GVD.Code_Editors.Preferences_Changed'Access),
         Process.Editor_Text);

      Widget_Callback.Object_Connect
        (Process.Window, "preferences_changed",
         Widget_Callback.To_Marshaller
           (GVD.Process.Preferences_Changed'Access),
         Process);

      if Process.Window.Standalone then
         Widget_Callback.Object_Connect
           (Process,
            "executable_changed",
            Widget_Callback.To_Marshaller
              (GVD.Code_Editors.On_Executable_Changed'Access),
            Process.Editor_Text);

         Widget_Callback.Object_Connect
           (Process.Window, "preferences_changed",
            Widget_Callback.To_Marshaller
              (GVD.Explorer.Preferences_Changed'Access),
            Get_Explorer (Process.Editor_Text));
      end if;

      --  Allocate the colors for highlighting. This needs to be done before
      --  Initializing the debugger, since some file name might be output at
      --  that time.

      Process.Debugger_Text_Highlight_Color :=
        Get_Pref (Debugger_Highlight_Color);

      Process.Debugger_Text_Font :=
        Get_Gdkfont (Get_Pref (Debugger_Font), Get_Pref (Debugger_Font_Size));

      Process.Separate_Data := False;
      --  ??? Should use MDI.Save/Load_Desktop instead

      --  Add a new page to the notebook

      Gtk_New (Label);

      Append_Page (Window.Process_Notebook, Process.Process_Mdi, Label);

      Show_All (Window.Process_Notebook);
      Set_Page (Window.Process_Notebook, -1);

      Length := Page_List.Length (Get_Children (Window.Process_Notebook));

      if Length > 1 then
         Set_Show_Tabs (Window.Process_Notebook, True);
      elsif Length /= 0 then
         Widget := Get_Item (Window.Factory, -"/File/Open Program...");

         if Widget /= null then
            Set_Sensitive (Widget, True);
         end if;
      end if;

      --  Set the user data, so that we can easily convert afterwards.

      Process_User_Data.Set
        (Process.Editor_Text, Process.all'Access, Process_User_Data_Name);
      Process_User_Data.Set (Process.Process_Mdi, Process.all'Access);

      --  Initialize the code editor.
      --  This should be done before initializing the debugger, in case the
      --  debugger outputs a file name that should be displayed in the editor.
      --  The language of the editor will automatically be set by the output
      --  filter.

      Configure
        (Process.Editor_Text,
         Source,
         Get_Pref (Editor_Font),
         Get_Pref (Editor_Font_Size),
         arrow_xpm, stop_xpm,
         Strings_Color  => Get_Pref (Strings_Color),
         Keywords_Color => Get_Pref (Keywords_Color));

      if Window.First_Debugger = null then
         Process.Debugger_Num := Debugger_Num;
         Window.First_Debugger := new Debugger_List_Node'
           (Next     => null,
            Debugger => Gtk_Widget (Process));
      else
         Debugger_Num := Debugger_Num + 1;
         Debugger_List := Window.First_Debugger;

         while Debugger_List.Next /= null loop
            Debugger_Num := Debugger_Num + 1;
            Debugger_List := Debugger_List.Next;
         end loop;

         Process.Debugger_Num := Debugger_Num;
         Debugger_List.Next := new Debugger_List_Node'
           (Next     => null,
            Debugger => Gtk_Widget (Process));
      end if;
   end Initialize;

   ---------------
   -- Configure --
   ---------------

   procedure Configure
     (Process         : access Debugger_Process_Tab_Record'Class;
      Kind            : Debugger_Type;
      Executable      : String;
      Debugger_Args   : Argument_List;
      Executable_Args : String;
      Remote_Host     : String := "";
      Remote_Target   : String := "";
      Remote_Protocol : String := "";
      Debugger_Name   : String := "")
   is
      Child         : MDI_Child;
      Widget        : Gtk_Widget;
      Call_Stack    : Gtk_Check_Menu_Item;
      Window        : constant GVD_Main_Window :=
        GVD_Main_Window (Process.Window);
      Geometry_Info : Process_Tab_Geometry;
      Buttons       : Message_Dialog_Buttons;

   begin
      pragma Assert (Process.Command_Scrolledwindow = null);
      pragma Assert (Process.Data_Paned = null);

      Setup_Command_Window (Process);
      Setup_Data_Window (Process);

      if Window.Standalone then
         Child := Put (Process.Process_Mdi, Process.Editor_Text);
         Set_Title (Child, "Editor");
         Maximize_Children (Process.Process_Mdi);
      end if;

      --  Remove the stack window if needed.

      Widget := Get_Widget (Window.Factory, -"/Data/Call Stack");

      if Widget = null then
         --  This means that GVD is part of Glide
         Widget := Get_Widget (Window.Factory, -"/Debug/Data/Call Stack");
      end if;

      Call_Stack := Gtk_Check_Menu_Item (Widget);

      if not Get_Active (Call_Stack) then
         Ref (Process.Stack_Scrolledwindow);
         Dock_Remove (Process.Data_Paned, Process.Stack_Scrolledwindow);
      end if;

      --  Set the graphical parameters.

      if Window.Standalone
        and then Is_Regular_File
          (Window.Home_Dir.all
           & Directory_Separator
           & "window_settings")
      then
         --  ??? Should use MDI.Save/Load_Desktop instead

         Geometry_Info := Get_Process_Tab_Geometry
           (Page_Num (Window.Process_Notebook, Process.Process_Mdi));

         if Get_Active (Call_Stack) then
            Set_Position (Process.Data_Paned, Geometry_Info.Stack_Width);
            Process.Backtrace_Mask :=
              Stack_List_Mask (Geometry_Info.Stack_Mask);
            Show_Call_Stack_Columns (Process);
            Set_Column_Width (Process.Stack_List, 0,
                              Geometry_Info.Stack_Num_Width);
            Set_Column_Width (Process.Stack_List, 1,
                              Geometry_Info.Stack_PC_Width);
            Set_Column_Width (Process.Stack_List, 2,
                              Geometry_Info.Stack_Subprogram_Width);
            Set_Column_Width (Process.Stack_List, 3,
                              Geometry_Info.Stack_Parameters_Width);
            Set_Column_Width (Process.Stack_List, 4,
                              Geometry_Info.Stack_Location_Width);
         end if;
      end if;

      --  Initialize the pixmaps and colors for the canvas
      Realize (Process.Data_Canvas);
      Init_Graphics (GVD_Canvas (Process.Data_Canvas));

      Process.Descriptor.Debugger := Kind;
      Process.Descriptor.Remote_Host := new String' (Remote_Host);

      if Remote_Protocol = "" then
         Process.Descriptor.Remote_Target := new String' ("");
         Process.Descriptor.Protocol := new String' ("");
      else
         Process.Descriptor.Remote_Target := new String' (Remote_Target);
         Process.Descriptor.Protocol := new String' (Remote_Protocol);
      end if;

      Process.Descriptor.Program := new String' (Executable);
      Process.Descriptor.Debugger_Name := new String' (Debugger_Name);

      case Kind is
         when Gdb_Type =>
            Process.Debugger := new Gdb_Debugger;
         when Jdb_Type =>
            Process.Debugger := new Jdb_Debugger;
         when others =>
            raise Debugger_Not_Supported;
      end case;

      --  Spawn the debugger.

      if Remote_Host /= "" or else Is_Regular_File (Executable) then
         Spawn
           (Process.Debugger,
            Executable,
            Debugger_Args,
            Executable_Args,
            new Gui_Process_Proxy,
            Process.Window.all'Access,
            Remote_Host,
            Remote_Target,
            Remote_Protocol,
            Debugger_Name);
      else
         Spawn
           (Process.Debugger, "", Debugger_Args, Executable_Args,
            new Gui_Process_Proxy,
            Process.Window.all'Access, Remote_Host, Remote_Target,
            Remote_Protocol, Debugger_Name);

         if Executable /= "" then
            Output_Error
              (Process.Window, (-" Could not find file: ") & Executable);
         end if;
      end if;

      --  Set the output filter, so that we output everything in the Gtk_Text
      --  window.

      Add_Filter
        (Get_Descriptor (Get_Process (Process.Debugger)).all,
         First_Text_Output_Filter'Access, Output, Process.Window.all'Address);

      --  Initialize the debugger, and possibly get the name of the initial
      --  file.

      Initialize (Process.Debugger);

   exception
      when Process_Died =>
         Buttons :=
           Message_Dialog
             (-"Could not launch the debugger", Error, Button_OK, Button_OK);
   end Configure;

   ---------------------
   -- Context_Changed --
   ---------------------

   procedure Context_Changed
     (Debugger : access Debugger_Process_Tab_Record'Class) is
   begin
      --  If the context has changed, it means that the debugger has started
      Set_Is_Started (Debugger.Debugger, True);

      --  Emit the signal
      Widget_Callback.Emit_By_Name (Gtk_Widget (Debugger), "context_changed");
   end Context_Changed;

   ------------------------
   -- Executable_Changed --
   ------------------------

   procedure Executable_Changed
     (Debugger        : access Debugger_Process_Tab_Record'Class;
      Executable_Name : String)
   is
      Debug : constant String :=
        Debugger_Type'Image (Debugger.Descriptor.Debugger);
      Label : Gtk_Widget;

   begin
      --  Change the title of the tab for that debugger

      Label := Get_Tab_Label
        (Debugger.Window.Process_Notebook, Debugger.Process_Mdi);
      Set_Text (Gtk_Label (Label),
                Debug (1 .. Debug'Last - 5) & " - "
                & Base_File_Name (Executable_Name));

      --  Emit the signal

      Widget_Callback.Emit_By_Name
        (Gtk_Widget (Debugger), "executable_changed");
   end Executable_Changed;

   ---------------------
   -- Process_Stopped --
   ---------------------

   procedure Process_Stopped
     (Debugger : access Debugger_Process_Tab_Record'Class) is
   begin
      --  ??? Will not work when commands like "step" are sent before
      --  e.g "run".
      Set_Is_Started (Debugger.Debugger, True);
      Widget_Callback.Emit_By_Name (Gtk_Widget (Debugger), "process_stopped");
   end Process_Stopped;

   -----------------------
   -- Process_Graph_Cmd --
   -----------------------

   procedure Process_Graph_Cmd
     (Process : access Debugger_Process_Tab_Record'Class;
      Cmd     : String)
   is
      Matched   : Match_Array (0 .. 10);
      Matched2  : Match_Array (0 .. 10);
      Item      : Display_Item;
      Index,
      Last      : Positive;
      Enable    : Boolean;
      First     : Natural;
      Link_Name : Basic_Types.String_Access;
      Link_From : Display_Item;
      Dependent_On_First : Natural := Natural'Last;
      Link_Name_First    : Natural := Natural'Last;

   begin
      --  graph (print|display) expression [dependent on display_num]
      --        [link_name name]
      --  graph (print|display) `command`
      --  graph enable display display_num [display_num ...]
      --  graph disable display display_num [display_num ...]
      --  graph undisplay display_num

      Match (Graph_Cmd_Format, Cmd, Matched);

      if Matched (0) /= No_Match then
         Enable := Cmd (Matched (Graph_Cmd_Type_Paren).First) = 'd'
           or else Cmd (Matched (Graph_Cmd_Type_Paren).First) = 'D';

         --  Do we have any 'dependent on' expression ?

         if Matched (Graph_Cmd_Rest_Paren).First >= Cmd'First then
            Match (Graph_Cmd_Dependent_Format,
                   Cmd (Matched (Graph_Cmd_Rest_Paren).First
                        .. Matched (Graph_Cmd_Rest_Paren).Last),
                   Matched2);

            if Matched2 (1) /= No_Match then
               Dependent_On_First := Matched2 (0).First;
               Link_From := Find_Item
                 (Process.Data_Canvas,
                  Integer'Value
                  (Cmd (Matched2 (1).First .. Matched2 (1).Last)));
            end if;
         end if;

         --  Do we have any 'link name' expression ?

         if Matched (Graph_Cmd_Rest_Paren).First >= Cmd'First then
            Match (Graph_Cmd_Link_Format,
                   Cmd (Matched (Graph_Cmd_Rest_Paren).First
                        .. Matched (Graph_Cmd_Rest_Paren).Last),
                   Matched2);

            if Matched2 (0) /= No_Match then
               Link_Name_First := Matched2 (0).First;
               Link_Name := new String'
                 (Cmd (Matched2 (1).First .. Matched2 (1).Last));
            end if;
         end if;

         --  A general expression (graph print `cmd`)
         if Matched (Graph_Cmd_Expression_Paren) /= No_Match then
            declare
               Expr : constant String := Cmd
                 (Matched (Graph_Cmd_Expression_Paren).First ..
                  Matched (Graph_Cmd_Expression_Paren).Last);
               Entity : Items.Generic_Type_Access := New_Debugger_Type (Expr);

            begin
               Set_Value
                 (Debugger_Output_Type (Entity.all),
                  Send (Process.Debugger,
                        Refresh_Command (Debugger_Output_Type (Entity.all)),
                        Mode => Internal));

               --  No link ?

               if Dependent_On_First = Natural'Last then
                  Gtk_New
                    (Item,
                     Variable_Name  => Expr,
                     Debugger       => Process,
                     Auto_Refresh   => Enable,
                     Default_Entity => Entity);
                  Put (Process.Data_Canvas, Item);

               else
                  Gtk_New
                    (Item,
                     Variable_Name  => Expr,
                     Debugger       => Process,
                     Auto_Refresh   => Enable,
                     Default_Entity => Entity,
                     Link_From      => Link_From,
                     Link_Name      => Link_Name.all);
               end if;

               if Item /= null then
                  Show_Item (Process.Data_Canvas, Item);
               end if;
            end;

         --  A quoted name or standard name

         else
            --  Quoted

            if Matched (Graph_Cmd_Quoted_Paren) /= No_Match then
               First := Matched (Graph_Cmd_Quoted_Paren).First;
               Last  := Matched (Graph_Cmd_Quoted_Paren).Last;

            --  Standard

            else
               First := Matched (Graph_Cmd_Rest_Paren).First;
               Last  := Natural'Min (Link_Name_First, Dependent_On_First);

               if Last = Natural'Last then
                  Last := Matched (Graph_Cmd_Rest_Paren).Last;
               else
                  Last := Last - 1;
               end if;
            end if;

            --  If we don't want any link:

            if Dependent_On_First = Natural'Last then
               if Enable_Block_Search then
                  Gtk_New
                    (Item,
                     Variable_Name =>
                       Variable_Name_With_Frame
                         (Process.Debugger, Cmd (First .. Last)),
                     Debugger      => Process,
                     Auto_Refresh  =>
                       Cmd (Matched (Graph_Cmd_Type_Paren).First) = 'd');
               end if;

               --  If we could not get the variable with the block, try
               --  without, since some debuggers (gdb most notably) can have
               --  more efficient algorithms to find the variable.

               if Item = null then
                  Gtk_New
                    (Item,
                     Variable_Name => Cmd (First .. Last),
                     Debugger      => Process,
                     Auto_Refresh  =>
                       Cmd (Matched (Graph_Cmd_Type_Paren).First) = 'd');
               end if;

               if Item /= null then
                  Put (Process.Data_Canvas, Item);
                  Show_Item (Process.Data_Canvas, Item);
                  Recompute_All_Aliases
                    (Process.Data_Canvas, Recompute_Values => False);
               end if;

            --  Else if we have a link

            else
               if Link_Name = null then
                  Link_Name := new String' (Cmd (First .. Last));
               end if;

               if Enable_Block_Search then
                  Gtk_New
                    (Item,
                     Variable_Name => Variable_Name_With_Frame
                     (Process.Debugger, Cmd (First .. Last)),
                     Debugger      => Process,
                     Auto_Refresh  => Enable,
                     Link_From     => Link_From,
                     Link_Name     => Link_Name.all);
               end if;

               if Item = null then
                  Gtk_New
                    (Item,
                     Variable_Name => Cmd (First .. Last),
                     Debugger      => Process,
                     Auto_Refresh  => Enable,
                     Link_From     => Link_From,
                     Link_Name     => Link_Name.all);
               end if;

               if Item /= null then
                  Show_Item (Process.Data_Canvas, Item);
               end if;
            end if;
         end if;

         Free (Link_Name);

      else
         --  Is this an enable/disable command ?

         Match (Graph_Cmd_Format2, Cmd, Matched);

         if Matched (2) /= No_Match then
            Index := Matched (2).First;
            Enable := Cmd (Matched (Graph_Cmd_Type_Paren).First) = 'e'
              or else Cmd (Matched (Graph_Cmd_Type_Paren).First) = 'E';

            while Index <= Cmd'Last loop
               Last := Index;
               Skip_To_Blank (Cmd, Last);
               Set_Auto_Refresh
                 (Find_Item
                    (Process.Data_Canvas,
                     Integer'Value (Cmd (Index .. Last - 1))),
                  Get_Window (Process),
                  Enable,
                  Update_Value => True);
               Index := Last + 1;
               Skip_Blanks (Cmd, Index);
            end loop;

         --  Third possible set of commands

         else
            Match (Graph_Cmd_Format3, Cmd, Matched);
            if Matched (1) /= No_Match then
               Index := Matched (1).First;
               while Index <= Cmd'Last loop
                  Last := Index;
                  Skip_To_Blank (Cmd, Last);
                  Free
                    (Find_Item
                      (Process.Data_Canvas,
                       Integer'Value (Cmd (Index .. Last - 1))));
                  Index := Last + 1;
                  Skip_Blanks (Cmd, Index);
               end loop;
            end if;
         end if;
      end if;

   exception
      when Constraint_Error =>
         --  Usually because Find_Item returned a null value.
         Output_Error (Process.Window, (-" Invalid command: ") & Cmd);
   end Process_Graph_Cmd;

   ----------------------
   -- Process_View_Cmd --
   ----------------------

   procedure Process_View_Cmd
     (Process : access Debugger_Process_Tab_Record'Class;
      Cmd     : String)
   is
      Mode : View_Mode;
   begin
      Mode := View_Mode'Value (Cmd (Cmd'First + 5 .. Cmd'Last));

      if Mode /= Source
        and then Command_In_Process (Get_Process (Process.Debugger))
      then
         return;
      end if;

      if Get_Mode (Process.Editor_Text) /= Mode then
         Apply_Mode (Process.Editor_Text, Mode);
      end if;

   exception
      when Constraint_Error =>
         Output_Error (Process.Window, (-" Invalid command: ") & Cmd);
   end Process_View_Cmd;

   --------------------
   -- Close_Debugger --
   --------------------

   procedure Close_Debugger (Debugger : Debugger_Process_Tab) is
      Top      : constant GVD_Main_Window := Debugger.Window;
      Notebook : constant Gtk_Notebook := Debugger.Window.Process_Notebook;
      Length   : Guint;
      use String_History;

   begin
      if Debugger.Exiting then
         return;
      end if;

      Debugger.Exiting := True;

      --  Switch to another page before removing the debugger.
      --  Otherwise, "switch_page" would be emitted after the debugger is dead,
      --  and Update_Dialogs would be called with a non-existent debugger.
      Next_Page (Notebook);

      Close (Debugger.Debugger);
      Remove_Page (Notebook, Page_Num (Notebook, Debugger.Process_Mdi));
      Destroy (Debugger);

      --  If the last notebook page was destroyed, disable "Open Program"
      --  in the menu.

      Length := Page_List.Length (Get_Children (Notebook));

      if Length = 1 then
         Set_Show_Tabs (Notebook, False);
      elsif Length = 0 then
         Set_Sensitive
           (Get_Item (Top.Factory, -"/File/Open Program..."), False);
      end if;
   end Close_Debugger;

   --------------------------
   -- Process_User_Command --
   --------------------------

   procedure Process_User_Command
     (Debugger       : Debugger_Process_Tab;
      Command        : String;
      Output_Command : Boolean := False;
      Mode           : Visible_Command := GVD.Types.Visible)
   is
      Lowered_Command : constant String := To_Lower (Command);
      First           : Natural := Lowered_Command'First;
      Data            : History_Data;
      use String_History;

      procedure Pre_User_Command;
      --  handle all the set up for a user command (logs, history, ...)

      procedure Pre_User_Command is
      begin
         Output_Message (Debugger, Command, Mode);
         Data.Mode := Mode;
         Data.Debugger_Num := Integer (Get_Num (Debugger));
         Skip_Blanks (Command, First);
         Data.Command := new String' (Command);
         Append (Debugger.Window.Command_History, Data);
         Set_Busy (Debugger);
      end Pre_User_Command;

   begin
      if Output_Command then
         Output_Text (Debugger, Command & ASCII.LF, Is_Command => True);
      end if;

      --  ??? Should forbid commands that modify the configuration of the
      --  debugger, like "set annotate" for gdb, otherwise we can't be sure
      --  what to expect from the debugger.

      --  Command has been converted to lower-cases, but the new version
      --  should be used only to compare with our standard list of commands.
      --  We should pass the original string to the debugger, in case we are
      --  in a case-sensitive language.

      --  Ignore the blanks at the beginning of lines

      Skip_Blanks (Lowered_Command, First);

      if Looking_At (Lowered_Command, First, "graph") then
         Pre_User_Command;
         Process_Graph_Cmd (Debugger, Command);
         Display_Prompt (Debugger.Debugger);
         Set_Busy (Debugger, False);

      elsif Looking_At (Lowered_Command, First, "view") then
         Pre_User_Command;
         Process_View_Cmd (Debugger, Command);
         Display_Prompt (Debugger.Debugger);
         Set_Busy (Debugger, False);

      elsif Lowered_Command = "quit" then
         if Debugger.Window.Standalone then
            Close_Debugger (Debugger);
         else
            Display_Prompt (Debugger.Debugger);
         end if;

      else
         --  Regular debugger command, send it.
         --  If a dialog is currently displayed, do not wait for the debugger
         --  prompt, since the prompt won't be displayed before the user
         --  answers the question... Same thing when the debugger is busy,
         --  since the command might actually be an input for the program being
         --  debugged.

         if (Command_In_Process (Get_Process (Debugger.Debugger))
             and then
               Get_Command_Mode (Get_Process (Debugger.Debugger)) /= Internal)
           or else Debugger.Registered_Dialog /= null
         then
            Send
              (Debugger.Debugger, Command,
               Wait_For_Prompt => False, Mode => Mode);
         else
            Send (Debugger.Debugger, Command, Mode => Mode);
         end if;
      end if;
   end Process_User_Command;

   ---------------------
   -- Register_Dialog --
   ---------------------

   procedure Register_Dialog
     (Process : access Debugger_Process_Tab_Record;
      Dialog  : access Gtk.Dialog.Gtk_Dialog_Record'Class) is
   begin
      if Process.Registered_Dialog /= null then
         raise Program_Error;
      end if;

      Process.Registered_Dialog := Gtk_Dialog (Dialog);
   end Register_Dialog;

   -----------------------
   -- Unregister_Dialog --
   -----------------------

   procedure Unregister_Dialog
     (Process : access Debugger_Process_Tab_Record) is
   begin
      if Process.Registered_Dialog /= null then
         Destroy (Process.Registered_Dialog);
         Process.Registered_Dialog := null;
      end if;
   end Unregister_Dialog;

   ------------------------
   -- Update_Breakpoints --
   ------------------------

   procedure Update_Breakpoints
     (Object : access Gtk.Widget.Gtk_Widget_Record'Class;
      Force  : Boolean)
   is
      Process : constant Debugger_Process_Tab := Debugger_Process_Tab (Object);
   begin
      --  We only need to update the list of breakpoints when we have a
      --  temporary breakpoint (since its status might be changed upon
      --  reaching the line).

      if Force or else Process.Has_Temporary_Breakpoint then
         Free (Process.Breakpoints);
         Process.Breakpoints := new Breakpoint_Array'
           (List_Breakpoints (Process.Debugger));

         --  Check whether there is any temporary breakpoint

         Process.Has_Temporary_Breakpoint := False;

         for J in Process.Breakpoints'Range loop
            if Process.Breakpoints (J).Disposition /= Keep
              and then Process.Breakpoints (J).Enabled
            then
               Process.Has_Temporary_Breakpoint := True;
               exit;
            end if;
         end loop;

         --  Update the breakpoints in the editor
         Update_Breakpoints (Process.Editor_Text, Process.Breakpoints.all);

         --  Update the breakpoints dialog if necessary
         if Process.Window.Breakpoints_Editor /= null
           and then Mapped_Is_Set (Process.Window.Breakpoints_Editor)
         then
            Update_Breakpoint_List
              (Breakpoint_Editor_Access (Process.Window.Breakpoints_Editor));
         end if;
      end if;
   end Update_Breakpoints;

   -----------------------------
   -- Toggle_Breakpoint_State --
   -----------------------------

   function Toggle_Breakpoint_State
     (Process        : access Debugger_Process_Tab_Record;
      Breakpoint_Num : Breakpoint_Identifier) return Boolean is
   begin
      --  ??? Maybe we should also update the icons in the code_editor to have
      --  an icon of a different color ?

      if Process.Breakpoints /= null then
         for J in Process.Breakpoints'Range loop
            if Process.Breakpoints (J).Num = Breakpoint_Num then
               Process.Breakpoints (J).Enabled :=
                 not Process.Breakpoints (J).Enabled;
               Enable_Breakpoint
                 (Process.Debugger, Breakpoint_Num,
                  Process.Breakpoints (J).Enabled,
                  Mode => GVD.Types.Visible);
               return Process.Breakpoints (J).Enabled;
            end if;
         end loop;
      end if;

      return False;
   end Toggle_Breakpoint_State;

   -------------------------
   -- Get_Current_Process --
   -------------------------

   function Get_Current_Process
     (Main_Window : access Gtk.Widget.Gtk_Widget_Record'Class)
      return Debugger_Process_Tab
   is
      Process : constant Gtk_Notebook :=
        GVD_Main_Window (Main_Window).Process_Notebook;
      Page    : constant Gint := Get_Current_Page (Process);

   begin
      if Page = -1 then
         return null;
      else
         return Process_User_Data.Get (Get_Nth_Page (Process, Page));
      end if;
   end Get_Current_Process;

   --------------
   -- Set_Busy --
   --------------

   procedure Set_Busy
     (Debugger      : access Debugger_Process_Tab_Record;
      Busy          : Boolean := True;
      Force_Refresh : Boolean := False) is
   begin
      Set_Busy_Cursor (Get_Window (Debugger.Window), Busy, Force_Refresh);
   end Set_Busy;

   -------------
   -- Get_Num --
   -------------

   function Get_Num (Tab : Debugger_Process_Tab) return Gint is
   begin
      return Gint (Tab.Debugger_Num);
   end Get_Num;

   -------------------------
   -- Preferences_Changed --
   -------------------------

   procedure Preferences_Changed
     (Editor : access Gtk.Widget.Gtk_Widget_Record'Class)
   is
      Process : constant Debugger_Process_Tab := Debugger_Process_Tab (Editor);
      Str     : constant String := Get_Chars (Process.Debugger_Text);
      F       : constant Gdk_Font :=
        Get_Gdkfont (Get_Pref (Debugger_Font), Get_Pref (Debugger_Font_Size));
      C       : constant Gdk_Color := Get_Pref (Debugger_Highlight_Color);

      use Gdk;
   begin
      if F /= Process.Debugger_Text_Font
        or else Process.Debugger_Text_Highlight_Color /= C
      then
         Process.Debugger_Text_Font := F;
         Process.Debugger_Text_Highlight_Color := C;

         --  Redraw the text. Note that we are loosing the colors in any case,
         --  since there is no way with the current Gtk_Text to get that
         --  information.
         Freeze (Process.Debugger_Text);
         Handler_Block (Process.Debugger_Text, Process.Delete_Text_Handler_Id);
         Delete_Text (Process.Debugger_Text);
         Handler_Unblock
           (Process.Debugger_Text, Process.Delete_Text_Handler_Id);
         Insert
           (Process.Debugger_Text,
            Process.Debugger_Text_Font,
            Black (Get_System),
            Null_Color,
            Str);
         Thaw (Process.Debugger_Text);
      end if;
   end Preferences_Changed;

   -------------------------
   -- Update_Editor_Frame --
   -------------------------

   procedure Update_Editor_Frame
     (Process : access Debugger_Process_Tab_Record) is
   begin
      if Process.Window.Standalone then
         --  Set the label text.
         Set_Title
           (Find_MDI_Child (Process.Process_Mdi, Process.Editor_Text),
            Base_File_Name (Get_Current_File (Process.Editor_Text)));
      end if;
   end Update_Editor_Frame;

   ---------------------------------
   -- Set_Current_Source_Location --
   ---------------------------------

   procedure Set_Current_Source_Location
     (Process : access Debugger_Process_Tab_Record;
      File    : String;
      Line    : Integer) is
   begin
      Free (Process.Current_File);
      Process.Current_File := new String' (File);
      Process.Current_Line := Line;
   end Set_Current_Source_Location;

   -----------------------------
   -- Get_Current_Source_File --
   -----------------------------

   function Get_Current_Source_File
     (Process : access Debugger_Process_Tab_Record)
     return String is
   begin
      if Process.Current_File = null then
         return "";
      else
         return Process.Current_File.all;
      end if;
   end Get_Current_Source_File;

   -----------------------------
   -- Get_Current_Source_Line --
   -----------------------------

   function Get_Current_Source_Line
     (Process : access Debugger_Process_Tab_Record)
     return Integer is
   begin
      return Process.Current_Line;
   end Get_Current_Source_Line;

end GVD.Process;
