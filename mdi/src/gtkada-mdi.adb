--  It would have been nice to be able to use a Gtk_Layout. However, the
--  layout doesn't give any information about the location of its children.
--  Moreover, it is not easily possible to raise or lower a child

with Glib;             use Glib;
with Gdk.Color;        use Gdk.Color;
with Gdk.Cursor;       use Gdk.Cursor;
with Gdk.Drawable;     use Gdk.Drawable;
with Gdk.Event;        use Gdk.Event;
with Gdk.Font;         use Gdk.Font;
with Gdk.GC;           use Gdk.GC;
with Gdk.Main;         use Gdk.Main;
with Gdk.Rectangle;    use Gdk.Rectangle;
with Gdk.Types;        use Gdk.Types;
with Gdk.Window;       use Gdk.Window;
with Gtk.Adjustment;   use Gtk.Adjustment;
with Gtk.Arguments;    use Gtk.Arguments;
with Gtk.Box;          use Gtk.Box;
with Gtk.Button;       use Gtk.Button;
with Gtk.Enums;        use Gtk.Enums;
with Gtk.Extra.PsFont; use Gtk.Extra.PsFont;
with Gtk.Event_Box;    use Gtk.Event_Box;
with Gtk.Handlers;
with Gtk.Layout;       use Gtk.Layout;
with Gtk.Style;        use Gtk.Style;
with Gtk.Widget;       use Gtk.Widget;
with Gtk.Window;       use Gtk.Window;
with Gtkada.Handlers;  use Gtkada.Handlers;

with GNAT.OS_Lib; use GNAT.OS_Lib;
with Text_IO; use Text_IO;

package body Gtkada.MDI is

   Title_Bar_Focus_Color : constant String := "#000088";
   --  <preference> Color to use for the title bar of the child that has
   --  the focus

   Title_Bar_Color : constant String := "#AAAAAA";
   --  <preference> Color to use for the title bar of children that do not
   --  have the focus.

   Title_Bar_Height : constant Gint := 15;
   --  <preference> Height of the title bar for the children

   Border_Thickness : constant Gint := 4;
   --  <preference> Thickness of the windows in the MDI

   Title_Font_Name : constant String := "Helvetica";
   --  <preference> Name of the font to use in the title bar

   Title_Font_Height : constant Gint := 10;
   --  <preference> Height of the font to use in the title bar

   Icons_Width : constant Gint := 100;
   --  <preference> Width to use for icons

   Opaque_Resize : constant Boolean := False;
   --  <preference> True if the contents of windows should be displayed while
   --  resizing widgets.

   Do_Grabs : constant Boolean := True;
   --  Should be set to False when debugging, so that pointer grabs are not
   --  done.

   Min_Width : constant Gint := 40;
   Min_Height : constant Gint := 2 * Border_Thickness + Title_Bar_Height;
   --  Minimal size for all windows

   use Widget_List;

   function Button_Pressed
     (Child : access Gtk_Widget_Record'Class;
      Event  : Gdk_Event) return Boolean;
   --  Called when the user has pressed the mouse button in the canvas.
   --  This tests whether an item was selected.

   function Button_Release
     (Child : access Gtk_Widget_Record'Class;
      Event  : Gdk_Event) return Boolean;
   --  Called when the user has released the mouse button.
   --  If an item was selected, this refreshed the canvas.

   function Button_Motion
     (Child : access Gtk_Widget_Record'Class;
      Event  : Gdk_Event) return Boolean;
   --  Called when the user moves the mouse while a button is pressed.
   --  If an item was selected, the item is moved.

   function Leave_Child
     (Child : access Gtk_Widget_Record'Class;
      Event  : Gdk_Event) return Boolean;
   --  The pointer has left the mouse

   function Side
     (Child : access MDI_Child_Record'Class; X, Y  : Gint)
      return Gdk_Cursor_Type;
   --  Return the cursor to use depending on the coordinates (X, Y) inside
   --  child.

   function Delete_Child
     (Child : access Gtk_Widget_Record'Class;
      Event : Gdk_Event) return Boolean;
   --  Forwards a delete_event from the toplevel window to the child.

   procedure Destroy_Child (Child : access Gtk_Widget_Record'Class);
   --  A child is destroyed, and memory should be freed

   procedure Iconify_Child (Child : access Gtk_Widget_Record'Class);
   --  Iconify a child

   procedure Close_Child (Child : access Gtk_Widget_Record'Class);
   --  A child should be destroyed (we first check with the application)

   procedure Remove_Child (C : access Gtk_Widget_Record'Class);
   --  Remove C from its MDI window, and destroy it.

   procedure Draw_Child
     (Child : access MDI_Child_Record'Class; Area : Gdk_Rectangle);
   procedure Draw_Child
     (Child : access Gtk_Widget_Record'Class; Params : Gtk_Args);
   function Draw_Child
     (Child : access Gtk_Widget_Record'Class; Event : Gdk_Event)
      return Boolean;
   --  Draw the child (and the title bar)

   procedure Realize_MDI (MDI : access Gtk_Widget_Record'Class);
   --  Called when the child is realized.

   procedure Activate_Child
     (MDI : access MDI_Window_Record'Class;
      Child : access MDI_Child_Record'Class);
   --  Make Child the active widget, and raise it at the top.

   function Constrain_X (MDI : access MDI_Window_Record'Class; X : Gint)
      return Gint;
   function Constrain_Y (MDI : access MDI_Window_Record'Class; Y : Gint)
      return Gint;
   --  Constrain the possible values of coordinates for an item in MDI.

   -------------
   -- Gtk_New --
   -------------

   procedure Gtk_New (MDI : out MDI_Window) is
   begin
      MDI := new MDI_Window_Record;
      Initialize (MDI);
   end Gtk_New;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (MDI : access MDI_Window_Record'Class) is
   begin
      Gtk.Layout.Initialize (MDI, Null_Adjustment, Null_Adjustment);
      Widget_Callback.Connect
        (MDI, "realize",
         Widget_Callback.To_Marshaller (Realize_MDI'Access));
   end Initialize;

   -------------------
   -- Realize_MDI --
   -------------------

   procedure Realize_MDI (MDI : access Gtk_Widget_Record'Class) is
      M : MDI_Window := MDI_Window (MDI);
      Color : Gdk_Color;
      List : Widget_List.Glist := Children (M);
      Tmp : Widget_List.Glist := First (List);
      Child_Req : Gtk_Requisition;
      Child : MDI_Child;
   begin
      Gdk_New (M.GC, Get_Window (MDI));
      Color := Parse (Title_Bar_Color);
      Alloc (Get_Default_Colormap, Color);
      Set_Foreground (M.GC, Color);

      Gdk_New (M.Focus_GC, Get_Window (MDI));
      Color := Parse (Title_Bar_Focus_Color);
      Alloc (Get_Default_Colormap, Color);
      Set_Foreground (M.Focus_GC, Color);

      Gdk_New (M.Resize_GC, Get_Window (MDI));
      Set_Function (M.Resize_GC, Gdk_Xor);
      Set_Foreground (M.Resize_GC, White (Get_Default_Colormap));

      M.Title_GC := Get_White_GC (Get_Style (MDI));

      --  Initialize the size of all children.
      --  This couldn't be done earlier since the child would have requested
      --  a size of 0x0
      while Tmp /= Null_List loop
         Child := MDI_Child (Get_Data (Tmp));
         Size_Request (Child, Child_Req);
         Child.Uniconified_Width := Child_Req.Width;
         Child.Uniconified_Height := Child_Req.Height;
         Tmp := Next (Tmp);
      end loop;
      Free (List);
   end Realize_MDI;

   -------------------
   -- Iconify_Child --
   -------------------

   procedure Iconify_Child (Child : access Gtk_Widget_Record'Class) is
      C : MDI_Child := MDI_Child (Child);
   begin
      Minimize_Child (C, not (C.State = Iconified));
   end Iconify_Child;

   -----------------
   -- Close_Child --
   -----------------

   procedure Close_Child (Child : access Gtk_Widget_Record'Class) is
      C : MDI_Child := MDI_Child (Child);
      Event : Gdk_Event;
   begin
      Allocate (Event, Delete, Get_Window (C));

      --  For a top-level window, we must rebuild the initial widget

      if C.Initial.all in Gtk_Window_Record'Class then
         Reparent (C.Initial_Child, Gtk_Window (C.Initial));
         if not Return_Callback.Emit_By_Name
           (C.Initial, "delete_event", Event)
         then
            Destroy (C);  --  Automatically removes C from MDI
         else
            Reparent (C.Initial_Child, Gtk_Box (Get_Child (C)));
         end if;
      else
         if not Return_Callback.Emit_By_Name
           (C.Initial, "delete_event", Event)
         then
            Destroy (C);  --  Automatically removes C from MDI
         end if;
      end if;
      Free (Event);
   end Close_Child;

   -------------------
   -- Destroy_Child --
   -------------------

   procedure Destroy_Child (Child : access Gtk_Widget_Record'Class) is
   begin
      Free (MDI_Child (Child).Name);
      Destroy (MDI_Child (Child).Initial);
   end Destroy_Child;

   ----------------
   -- Draw_Child --
   ----------------

   procedure Draw_Child
     (Child : access MDI_Child_Record'Class; Area : Gdk_Rectangle)
   is
      MDI : MDI_Window := MDI_Window (Get_Parent (Child));
      F : Gdk_Font := Get_Gdkfont (Title_Font_Name, Title_Font_Height);
      GC : Gdk_GC := MDI.GC;
   begin
      if MDI.Focus_Child = MDI_Child (Child) then
         GC := MDI.Focus_GC;
      end if;

      Draw_Rectangle
        (Get_Window (Child),
         GC,
         True,
         Border_Thickness,
         Border_Thickness,
         Gint (Get_Allocation_Width (Child)) - 2 * Border_Thickness,
         Gint (Get_Allocation_Height (Child)) - 2 * Border_Thickness);

      Draw_Shadow
        (Get_Style (Child),
         Get_Window (Child),
         State_Normal,
         Shadow_Out,
         1, 1,
         Gint (Get_Allocation_Width (Child)) - 1,
         Gint (Get_Allocation_Height (Child)) - 1);

      Draw_Text
        (Get_Window (Child),
         F,
         MDI.Title_GC,
         Border_Thickness + 3,
         Border_Thickness +
         (Title_Bar_Height + Get_Ascent (F) - Get_Descent (F)) / 2,
         Child.Name.all);
   end Draw_Child;

   ----------------
   -- Draw_Child --
   ----------------

   procedure Draw_Child
     (Child : access Gtk_Widget_Record'Class; Params : Gtk_Args) is
   begin
      Draw_Child (MDI_Child (Child), Full_Area);
      Gtk.Handlers.Emit_Stop_By_Name (Child, "draw");
   end Draw_Child;

   ----------------
   -- Draw_Child --
   ----------------

   function Draw_Child
     (Child : access Gtk_Widget_Record'Class; Event : Gdk_Event)
      return Boolean is
   begin
      Draw_Child (MDI_Child (Child), Get_Area (Event));
      Gtk.Handlers.Emit_Stop_By_Name (Child, "expose_event");
      return True;
   end Draw_Child;

   -----------------
   -- Constrain_X --
   -----------------

   function Constrain_X (MDI : access MDI_Window_Record'Class; X : Gint)
      return Gint is
   begin
      --  ??? Shouldn't constrain if we are in a scrolled window
      return Gint'Max
        (0, Gint'Min (X, Gint (Get_Allocation_Width (MDI)) - Min_Width));
   end Constrain_X;

   -----------------
   -- Constrain_Y --
   -----------------

   function Constrain_Y (MDI : access MDI_Window_Record'Class; Y : Gint)
      return Gint is
   begin
      --  ??? Shouldn't constrain if we are in a scrolled window
      return Gint'Max
        (0, Gint'Min (Y, Gint (Get_Allocation_Height (MDI)) - Min_Height));
   end Constrain_Y;

   --------------------
   -- Button_Pressed --
   --------------------

   function Button_Pressed
     (Child : access Gtk_Widget_Record'Class;
      Event  : Gdk_Event) return Boolean
   is
      MDI : MDI_Window := MDI_Window (Get_Parent (Child));
      C : MDI_Child := MDI_Child (Child);
      Cursor : Gdk.Cursor.Gdk_Cursor;
      Tmp : Boolean;
      Curs : Gdk_Cursor_Type;
   begin
      Activate_Child (MDI, C);
      MDI.X_Root := Gint (Get_X_Root (Event));
      MDI.Y_Root := Gint (Get_Y_Root (Event));
      MDI.Initial_Width := Gint (Get_Allocation_Width (Child));
      MDI.Initial_Height := Gint (Get_Allocation_Height (Child));
      MDI.Current_W := MDI.Initial_Width;
      MDI.Current_H := MDI.Initial_Height;
      MDI.Current_X := C.X;
      MDI.Current_Y := C.Y;

      Curs := Side (C, Gint (Get_X (Event)), Gint (Get_Y (Event)));
      MDI.Current_Cursor := Curs;
      if Curs = Left_Ptr then
         Curs := Fleur;
      end if;

      --  Iconified windows can only be moved, not resized.
      --  Docked items can never be moved
      if (Curs = Fleur and then C.State /= Docked)
        or else (Curs /= Fleur and then C.State /= Iconified)
      then
         if Do_Grabs then
            Gdk_New (Cursor, Curs);
            Tmp := Pointer_Grab
              (Get_Window (C),
               False,
               Button_Press_Mask or Button_Motion_Mask or Button_Release_Mask,
               Cursor => Cursor,
               Time => 0);
            Destroy (Cursor);
         end if;

         MDI.Selected_Child := C;

         if not Opaque_Resize and then MDI.Current_Cursor /= Left_Ptr then
            Draw_Rectangle
              (Get_Bin_Window (MDI),
               MDI.Resize_GC,
               Filled => False,
               X => MDI.Current_X,
               Y => MDI.Current_Y,
               Width => MDI.Current_W,
               Height => MDI.Current_H);
         end if;
      end if;
      return True;
   end Button_Pressed;

   --------------------
   -- Button_Release --
   --------------------

   function Button_Release
     (Child : access Gtk_Widget_Record'Class;
      Event  : Gdk_Event) return Boolean
   is
      MDI : MDI_Window := MDI_Window (Get_Parent (Child));
   begin
      if MDI.Selected_Child /= null then
         if Do_Grabs then
            Pointer_Ungrab (Time => 0);
         end if;

         if not Opaque_Resize and then MDI.Current_Cursor /= Left_Ptr then
            Draw_Rectangle
              (Get_Bin_Window (MDI),
               MDI.Resize_GC,
               Filled => False,
               X => MDI.Current_X,
               Y => MDI.Current_Y,
               Width => MDI.Current_W,
               Height => MDI.Current_H);
            Set_USize (MDI.Selected_Child, MDI.Current_W, MDI.Current_H);
            if MDI.Selected_Child.State /= Docked then
               MDI.Selected_Child.Uniconified_Width := MDI.Current_W;
               MDI.Selected_Child.Uniconified_Height := MDI.Current_H;
            end if;
            Move (MDI, MDI.Selected_Child, MDI.Current_X, MDI.Current_Y);
         end if;

         MDI.Selected_Child.X := MDI.Current_X;
         MDI.Selected_Child.Y := MDI.Current_Y;

         MDI.Selected_Child := null;
      end if;
      return True;
   end Button_Release;

   -------------------
   -- Button_Motion --
   -------------------

   function Button_Motion
     (Child : access Gtk_Widget_Record'Class;
      Event  : Gdk_Event) return Boolean
   is
      MDI : MDI_Window := MDI_Window (Get_Parent (Child));
      C : MDI_Child := MDI_Child (Child);
      Delta_X, Delta_Y : Gint;
      Cursor : Gdk_Cursor;
      Curs : Gdk_Cursor_Type;
      W, H : Gint;
   begin
      --  A button_motion event ?
      if (Get_State (Event) and Button1_Mask) /= 0 then
         if MDI.Selected_Child /= null then
            C := MDI.Selected_Child;

            if not Opaque_Resize and then MDI.Current_Cursor /= Left_Ptr then
               Draw_Rectangle
                 (Get_Bin_Window (MDI),
                  MDI.Resize_GC,
                  Filled => False,
                  X => MDI.Current_X,
                  Y => MDI.Current_Y,
                  Width => MDI.Current_W,
                  Height => MDI.Current_H);
            end if;

            Delta_X := Gint (Get_X_Root (Event)) - MDI.X_Root;
            Delta_Y := Gint (Get_Y_Root (Event)) - MDI.Y_Root;
            W := MDI.Initial_Width;
            H := MDI.Initial_Height;
            MDI.Current_X := C.X;
            MDI.Current_Y := C.Y;

            case MDI.Current_Cursor is
               when Left_Ptr =>
                  MDI.Current_X := Delta_X + C.X;
                  MDI.Current_Y := Delta_Y + C.Y;

               when Left_Side =>
                  W := Gint'Max (Min_Width, W - Delta_X);
                  MDI.Current_X := C.X + MDI.Initial_Width - W;

               when Right_Side =>
                  W := Gint'Max (Min_Width, W + Delta_X);

               when Top_Side =>
                  H := Gint'Max (Min_Height, H - Delta_Y);
                  MDI.Current_Y := C.Y + MDI.Initial_Height - H;

               when Bottom_Side =>
                  H := Gint'Max (Min_Height, H + Delta_Y);

               when Top_Left_Corner =>
                  W := Gint'Max (Min_Width, W - Delta_X);
                  H := Gint'Max (Min_Height, H - Delta_Y);
                  MDI.Current_X := C.X + MDI.Initial_Width - W;
                  MDI.Current_Y := C.Y + MDI.Initial_Height - H;

               when Top_Right_Corner =>
                  W := Gint'Max (Min_Width, W + Delta_X);
                  H := Gint'Max (Min_Height, H - Delta_Y);
                  MDI.Current_Y := C.Y + MDI.Initial_Height - H;

               when Bottom_Left_Corner =>
                  W := Gint'Max (Min_Width, W - Delta_X);
                  H := Gint'Max (Min_Height, H + Delta_Y);
                  MDI.Current_X := C.X + MDI.Initial_Width - W;

               when Bottom_Right_Corner =>
                  W := Gint'Max (Min_Width, W + Delta_X);
                  H := Gint'Max (Min_Height, H + Delta_Y);

               when others => null;
            end case;

            MDI.Current_X := Constrain_X (MDI, MDI.Current_X);
            MDI.Current_Y := Constrain_Y (MDI, MDI.Current_Y);

            if MDI.Current_Cursor = Left_Ptr
              or else Opaque_Resize
            then
               Move (MDI, C, MDI.Current_X, MDI.Current_Y);
            end if;

            if MDI.Current_Cursor /= Left_Ptr
              and then Opaque_Resize
              and then (W /= Gint (Get_Allocation_Width (C))
                        or else H /= Gint (Get_Allocation_Height (C)))
            then
               if C.State /= Docked then
                  C.Uniconified_Width := W;
                  C.Uniconified_Height := H;
               end if;
               Set_USize (C, W, H);
            end if;

            if MDI.Current_Cursor /= Left_Ptr then
               MDI.Current_W := W;
               MDI.Current_H := H;
               Draw_Rectangle
                 (Get_Bin_Window (MDI),
                  MDI.Resize_GC,
                     Filled => False,
                  X => MDI.Current_X,
                  Y => MDI.Current_Y,
                  Width => MDI.Current_W,
                  Height => MDI.Current_H);
            end if;

         end if;

      --  A motion_event ?
      elsif C.State = Normal or else C.State = Docked then
         Delta_X := Gint (Get_X (Event));
         Delta_Y := Gint (Get_Y (Event));
         Curs := Side (C, Delta_X, Delta_Y);
         if Curs /= MDI.Current_Cursor then
            MDI.Current_Cursor := Curs;
            Gdk_New (Cursor, MDI.Current_Cursor);
            Set_Cursor (Get_Window (Child), Cursor);
            Destroy (Cursor);
         end if;
      end if;
      return True;
   end Button_Motion;

   -----------------
   -- Leave_Child --
   -----------------

   function Leave_Child
     (Child : access Gtk_Widget_Record'Class;
      Event  : Gdk_Event) return Boolean
   is
      MDI : MDI_Window := MDI_Window (Get_Parent (Child));
      Cursor : Gdk_Cursor;
   begin
      if Get_State (Event) = 0
        and then MDI.Current_Cursor /= Left_Ptr
      then
         MDI.Current_Cursor := Left_Ptr;
         Gdk_New (Cursor, MDI.Current_Cursor);
         Set_Cursor (Get_Window (Child), Cursor);
         Destroy (Cursor);
      end if;
      return False;
   end Leave_Child;

   ----------
   -- Side --
   ----------

   function Side
     (Child : access MDI_Child_Record'Class; X, Y  : Gint)
      return Gdk_Cursor_Type
   is
      X_Side, Y_Side : Gint;
   begin
      if X < Border_Thickness then
         X_Side := -1;
      elsif X > Gint (Get_Allocation_Width (Child)) - Border_Thickness then
         X_Side := 1;
      else
         X_Side := 0;
      end if;

      if Y < Border_Thickness then
         Y_Side := -1;
      elsif Y > Gint (Get_Allocation_Height (Child)) - Border_Thickness then
         Y_Side := 1;
      else
         Y_Side := 0;
      end if;

      if X_Side = -1 then
         if Y_Side = -1 then
            if Child.State /= Docked then
               return Top_Left_Corner;
            end if;
         elsif Y_Side = 0 then
            if Child.State /= Docked or else Child.Dock = Right then
               return Left_Side;
            end if;
         elsif Child.State /= Docked then
            return Bottom_Left_Corner;
         end if;

      elsif X_Side = 0 then
         if Y_Side = -1 then
            if Child.State /= Docked or else Child.Dock = Bottom then
               return Top_Side;
            end if;
         elsif Y_Side = 0 then
            return Left_Ptr;
         elsif Child.State /= Docked or else Child.Dock = Top then
            return Bottom_Side;
         end if;

      else
         if Y_Side = -1 then
            if Child.State /= Docked then
               return Top_Right_Corner;
            end if;
         elsif Y_Side = 0 then
            if Child.State /= Docked or else Child.Dock = Left then
               return Right_Side;
            end if;
         elsif Child.State /= Docked then
            return Bottom_Right_Corner;
         end if;
      end if;
      return Left_Ptr;
   end Side;

   -------------
   -- Gtk_New --
   -------------

   procedure Gtk_New (Child : out MDI_Child;
                      Widget : access Gtk.Widget.Gtk_Widget_Record'Class) is
   begin
      Child := new MDI_Child_Record;
      Initialize (Child, Widget);
   end Gtk_New;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (Child : access MDI_Child_Record;
                         Widget : access Gtk.Widget.Gtk_Widget_Record'Class)
   is
      Button : Gtk_Button;
      Box, Box2 : Gtk_Box;
   begin
      Gtk.Event_Box.Initialize (Child);
      Child.Initial := Gtk_Widget (Widget);

      Add_Events (Child, Button_Press_Mask
                  or Button_Motion_Mask
                  or Button_Release_Mask
                  or Pointer_Motion_Mask);
      Return_Callback.Connect
        (Child, "button_press_event",
         Return_Callback.To_Marshaller (Button_Pressed'Access));
      Return_Callback.Connect
        (Child, "button_release_event",
         Return_Callback.To_Marshaller (Button_Release'Access));
      Return_Callback.Connect
        (Child, "motion_notify_event",
         Return_Callback.To_Marshaller (Button_Motion'Access));
      Widget_Callback.Connect (Child, "draw", Draw_Child'Access);
      Widget_Callback.Connect
        (Child, "destroy",
         Widget_Callback.To_Marshaller (Destroy_Child'Access));
      Return_Callback.Connect
        (Child, "leave_notify_event",
         Return_Callback.To_Marshaller (Leave_Child'Access));
      Return_Callback.Connect
        (Child, "expose_event",
         Return_Callback.To_Marshaller (Draw_Child'Access));

      Gtk_New_Vbox (Box, Homogeneous => False, Spacing => 0);
      Add (Child, Box);

      --  Buttons in the title bar

      Gtk_New_Hbox (Box2, Homogeneous => False);
      Pack_Start (Box, Box2, Expand => False, Fill => False);
      Set_Border_Width (Box, Border_Thickness);
      Set_USize (Box2, -1, Title_Bar_Height);

      Gtk_New (Button, "x");
      Pack_End (Box2, Button, Expand => False, Fill => False);
      Widget_Callback.Object_Connect
        (Button, "clicked",
         Widget_Callback.To_Marshaller (Close_Child'Access), Child);

      Gtk_New (Button, "_");
      Pack_End (Box2, Button, Expand => False, Fill => False);
      Widget_Callback.Object_Connect
        (Button, "clicked",
         Widget_Callback.To_Marshaller (Iconify_Child'Access), Child);

      --  The child widget

      if Widget.all in Gtk_Window_Record'Class then
         pragma Assert (Get_Child (Gtk_Window (Widget)) /= null);
         Child.Initial_Child := Get_Child (Gtk_Window (Widget));
         Reparent (Child.Initial_Child, Box);
      else
         Child.Initial := Gtk_Widget (Widget);
         Child.Initial_Child := Gtk_Widget (Widget);
         Pack_Start
           (Box, Widget, Expand => True, Fill => True, Padding => 0);
      end if;

      Widget_Callback.Object_Connect
        (Child.Initial_Child, "destroy",
         Widget_Callback.To_Marshaller (Remove_Child'Access), Child);
   end Initialize;

   ---------
   -- Add --
   ---------

   procedure Put (MDI : access MDI_Window_Record;
                  Child : access Gtk.Widget.Gtk_Widget_Record'Class;
                  Name : String)
   is
      C : MDI_Child;
      X, Y : Gint;
   begin
      Gtk_New (C, Child);

      --  ??? Should have a better algorithm for automatic placement
      X := 10;
      Y := 10;

      C.X := X;
      C.Y := Y;
      C.Name := new String' (Name);
      Gtk.Layout.Put (Gtk_Layout_Record (MDI.all)'Access, C, X, Y);
      Activate_Child (MDI, C);
   end Put;

   -------------------
   -- Get_MDI_Child --
   -------------------

   function Find_MDI_Child
     (MDI : access MDI_Window_Record;
      Widget : access Gtk.Widget.Gtk_Widget_Record'Class)
      return MDI_Child
   is
      Found : MDI_Child;

      procedure Action (W : access Gtk_Widget_Record'Class);
      --  Executed for each child in MDI

      ------------
      -- Action --
      ------------

      procedure Action (W : access Gtk_Widget_Record'Class) is
      begin
         if Found = null
           and then MDI_Child (W).Initial = Gtk_Widget (Widget)
         then
            Found := MDI_Child (W);
         end if;
      end Action;
   begin
      Forall (MDI, Action'Unrestricted_Access);
      return Found;
   end Find_MDI_Child;

   -----------------
   -- Raise_Child --
   -----------------

   procedure Raise_Child (Child : access MDI_Child_Record'Class) is
   begin
      Gdk_Raise (Get_Window (Child));
   end Raise_Child;

   --------------------
   -- Activate_Child --
   --------------------

   procedure Activate_Child
     (MDI : access MDI_Window_Record'Class;
      Child : access MDI_Child_Record'Class)
   is
      Old : MDI_Child := MDI.Focus_Child;
   begin
      MDI.Focus_Child := MDI_Child (Child);

      if Old /= null and then Realized_Is_Set (Old) then
         Draw_Child (Old, Full_Area);
      end if;

      if Realized_Is_Set (Child) then
         Raise_Child (Child);
         Draw_Child (Child, Full_Area);
      end if;
   end Activate_Child;

   ----------------------
   -- Cascade_Children --
   ----------------------

   procedure Cascade_Children (MDI : access MDI_Window_Record) is
      W : constant Gint := Gint (Get_Allocation_Width (MDI));
      H : constant Gint := Gint (Get_Allocation_Height (MDI));
      List : Widget_List.Glist := Children (MDI);
      C : MDI_Child;
      Tmp : Widget_List.Glist;
      Level : Gint := 0;
   begin
      Tmp := First (List);
      while Tmp /= Null_List loop
         C := MDI_Child (Get_Data (Tmp));
         if C.State = Normal and then C /= MDI.Focus_Child then
            C.X := Level;
            C.Y := Level;
            Move (MDI, C, C.X, C.Y);
            C.Uniconified_Width := W - Level;
            C.Uniconified_Height := H - Level;
            Set_USize (C, C.Uniconified_Width, C.Uniconified_Height);

            Level := Level + Title_Bar_Height;
         end if;
         Tmp := Next (Tmp);
      end loop;

      if MDI.Focus_Child /= null then
         C := MDI.Focus_Child;
         C.X := Level;
         C.Y := Level;
         Move (MDI, C, C.X, C.Y);
         C.Uniconified_Width := W - Level;
         C.Uniconified_Height := H - Level;
         Set_USize (C, C.Uniconified_Width, C.Uniconified_Height);
      end if;
      Free (List);
      Queue_Resize (MDI);
   end Cascade_Children;

   -----------------------
   -- Tile_Horizontally --
   -----------------------

   procedure Tile_Horizontally (MDI : access MDI_Window_Record) is
      W : constant Gint := Gint (Get_Allocation_Width (MDI));
      H : constant Gint := Gint (Get_Allocation_Height (MDI));
      List : Widget_List.Glist := Children (MDI);
      C : MDI_Child;
      Tmp : Widget_List.Glist;
      Level : Gint := 0;
      Num_Children : Gint := 0;
   begin
      Tmp := First (List);
      while Tmp /= Null_List loop
         if MDI_Child (Get_Data (Tmp)).State = Normal then
            Num_Children := Num_Children + 1;
         end if;
         Tmp := Next (Tmp);
      end loop;

      Tmp := First (List);
      while Tmp /= Null_List loop
         C := MDI_Child (Get_Data (Tmp));
         if C.State = Normal then
            C.X := Level;
            C.Y := 0;
            Move (MDI, C, C.X, C.Y);
            C.Uniconified_Width := W / Num_Children;
            C.Uniconified_Height := H;
            Set_USize (C, C.Uniconified_Width, C.Uniconified_Height);
            Level := Level + (W / Num_Children);
         end if;
         Tmp := Next (Tmp);
      end loop;
      Free (List);
      Queue_Resize (MDI);
   end Tile_Horizontally;

   ---------------------
   -- Tile_Vertically --
   ---------------------

   procedure Tile_Vertically (MDI : access MDI_Window_Record) is
      W : constant Gint := Gint (Get_Allocation_Width (MDI));
      H : constant Gint := Gint (Get_Allocation_Height (MDI));
      List : Widget_List.Glist := Children (MDI);
      C : MDI_Child;
      Tmp : Widget_List.Glist;
      Level : Gint := 0;
      Num_Children : Gint := 0;
   begin
      Tmp := First (List);
      while Tmp /= Null_List loop
         if MDI_Child (Get_Data (Tmp)).State = Normal then
            Num_Children := Num_Children + 1;
         end if;
         Tmp := Next (Tmp);
      end loop;

      Tmp := First (List);
      while Tmp /= Null_List loop
         C := MDI_Child (Get_Data (Tmp));
         if C.State = Normal then
            C.X := 0;
            C.Y := Level;
            Move (MDI, C, C.X, C.Y);
            C.Uniconified_Width := W;
            C.Uniconified_Height := H / Num_Children;
            Set_USize (C, C.Uniconified_Width, C.Uniconified_Height);
            Level := Level + (H / Num_Children);
         end if;
         Tmp := Next (Tmp);
      end loop;
      Free (List);
      Queue_Resize (MDI);
   end Tile_Vertically;

   ------------------
   -- Delete_Child --
   ------------------

   function Delete_Child
     (Child : access Gtk_Widget_Record'Class;
      Event : Gdk_Event) return Boolean is
   begin
      --  Gtk_Window children are handled differently (see Float_Child)
      pragma Assert
        (not (MDI_Child (Child).Initial.all in Gtk_Window_Record'Class));
      return Return_Callback.Emit_By_Name
        (MDI_Child (Child).Initial, "delete_event", Event);
   end Delete_Child;

   ------------------
   -- Remove_Child --
   ------------------

   procedure Remove_Child (C : access Gtk_Widget_Record'Class) is
   begin
      if Get_Parent (C) /= null then
         Remove (MDI_Window (Get_Parent (C)), C);
      end if;
   end Remove_Child;

   -----------------
   -- Float_Child --
   -----------------

   procedure Float_Child
     (Child : access MDI_Child_Record'Class;
      Float : Boolean)
   is
      Win : Gtk_Window;
   begin
      if Child.State /= Floating and then Float then
         Minimize_Child (Child, False);
         Dock_Child (Child, False);
         if Child.Initial.all in Gtk_Window_Record'Class then
            Reparent (Child.Initial_Child, Gtk_Window (Child.Initial));
            Show_All (Child.Initial);
         else
            Gtk_New (Win, Window_Toplevel);
            Reparent (Child.Initial_Child, Win);
            Set_Title (Win, Child.Name.all);
            Show_All (Win);

            --  Delete_Event should be forwarded to the child, not to the
            --  toplevel window
            Return_Callback.Object_Connect
              (Win, "delete_event",
               Return_Callback.To_Marshaller (Delete_Child'Access), Child);
         end if;
         Hide (Child);
         Child.State := Floating;

      elsif Child.State = Floating and then not Float then
         Win := Gtk_Window (Get_Parent (Child.Initial_Child));
         Reparent (Child.Initial_Child, Gtk_Box (Get_Child (Child)));
         if Child.Initial.all in Gtk_Window_Record'Class then
            Hide (Child.Initial);
         else
            Destroy (Win);
         end if;
         Show_All (Child);
         Child.State := Normal;
      end if;
   end Float_Child;

   -----------------
   -- Is_Floating --
   -----------------

   function Is_Floating
     (Child : access MDI_Child_Record'Class) return Boolean is
   begin
      return Child.State = Floating;
   end Is_Floating;

   ----------------
   -- Dock_Child --
   ----------------

   procedure Dock_Child
     (Child : access MDI_Child_Record'Class;
      Dock : Boolean := True)
   is
      MDI : MDI_Window := MDI_Window (Get_Parent (Child));
      W, H : Gint;
   begin
      if Child.State /= Docked and then Dock and then Child.Dock /= None then
         Float_Child (Child, False);
         Minimize_Child (Child, False);

         Child.State := Docked;
         Child.Uniconified_X := Child.X;
         Child.Uniconified_Y := Child.Y;
         W := Child.Uniconified_Width;
         H := Child.Uniconified_Height;
         case Child.Dock is
            when None => null;
            when Left =>
               Child.X := 0;
               Child.Y := 0;
               H := Gint (Get_Allocation_Height (MDI));
            when Right =>
               Child.X := Gint (Get_Allocation_Width (MDI)) -
                 Child.Uniconified_Width;
               Child.Y := 0;
               H := Gint (Get_Allocation_Height (MDI));
            when Top =>
               Child.X := 0;
               Child.Y := 0;
               W := Gint (Get_Allocation_Width (MDI));
            when Bottom =>
               Child.X := 0;
               Child.Y := Gint (Get_Allocation_Height (MDI)) -
                 Child.Uniconified_Height;
               W := Gint (Get_Allocation_Width (MDI));
         end case;
         --  Do not change Uniconified_{Width,Height}, since we want the
         --  widget to go back to its default size
         Set_USize (Child, W, H);
         Move (MDI, Child, Child.X, Child.Y);

      elsif Child.State = Docked and then not Dock then
         Child.State := Normal;
         Set_USize (Child, Child.Uniconified_Width, Child.Uniconified_Height);
         Child.X := Child.Uniconified_X;
         Child.Y := Child.Uniconified_Y;
         Move (MDI, Child, Child.X, Child.Y);
      end if;
   end Dock_Child;

   -------------------
   -- Set_Dock_Side --
   -------------------

   procedure Set_Dock_Side
     (Child : access MDI_Child_Record'Class; Side  : Dock_Side) is
   begin
      Child.Dock := Side;
   end Set_Dock_Side;

   --------------------
   -- Minimize_Child --
   --------------------

   procedure Minimize_Child
     (Child : access MDI_Child_Record'Class; Minimize : Boolean)
   is
      MDI : MDI_Window := MDI_Window (Get_Parent (Child));
      Icon_Height : constant Gint := Title_Bar_Height + 2 * Border_Thickness;
   begin
      if Child.State /= Iconified and then Minimize then
         Float_Child (Child, False);
         Dock_Child (Child, False);
         Child.Uniconified_X := Child.X;
         Child.Uniconified_Y := Child.Y;
         Set_USize (Child, Icons_Width, Icon_Height);
         Child.State := Iconified;

         declare
            List : Widget_List.Glist := Children (MDI);
            Tmp : Widget_List.Glist := First (List);
            C2 : MDI_Child;
         begin
            Child.X := 0;
            Child.Y := 0;
            while Tmp /= Null_List loop
               C2 := MDI_Child (Get_Data (Tmp));
               if C2 /= MDI_Child (Child) and then C2.State = Iconified then
                  if C2.Y mod Icon_Height = 0
                    and then C2.Y >= Child.Y
                  then
                     if C2.X + Icons_Width >=
                       Gint (Get_Allocation_Width (MDI))
                     then
                        Child.X := 0;
                        Child.Y := C2.Y + Icon_Height;
                     elsif C2.X + Icons_Width > Child.Y then
                        Child.X := C2.X + Icons_Width;
                        Child.Y := C2.Y;
                     end if;
                  end if;
               end if;
               Tmp := Next (Tmp);
            end loop;
            Free (List);
         end;
         Move (MDI, Child, Child.X, Child.Y);
         Activate_Child (MDI, Child);

      elsif Child.State = Iconified and then not Minimize then
         Set_USize (Child, Child.Uniconified_Width, Child.Uniconified_Height);
         Child.X := Child.Uniconified_X;
         Child.Y := Child.Uniconified_Y;
         Child.State := Normal;
         Move (MDI, Child, Child.X, Child.Y);
         Activate_Child (MDI, Child);
      end if;
   end Minimize_Child;

   ----------------
   -- Get_Widget --
   ----------------

   function Get_Widget (Child : access MDI_Child_Record) return Gtk_Widget is
   begin
      return Gtk_Widget (Child.Initial_Child);
   end Get_Widget;

   ----------------
   -- Get_Window --
   ----------------

   function Get_Window (Child : access MDI_Child_Record) return Gtk_Window is
   begin
      if Child.Initial.all in Gtk_Window_Record'Class then
         return Gtk_Window (Child.Initial);
      else
         return null;
      end if;
   end Get_Window;

   ---------------------
   -- Get_Focus_Child --
   ---------------------

   function Get_Focus_Child
     (MDI : access MDI_Window_Record) return MDI_Child is
   begin
      return MDI.Focus_Child;
   end Get_Focus_Child;
end Gtkada.MDI;
