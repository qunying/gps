with Glib;
with Gdk.GC;
with Gdk.Types;
with Gtk.Event_Box;
with Gtk.Layout;
with Gtk.Widget;
with Gtk.Window;
with GNAT.OS_Lib;

--  TODO:
--  - handles docking (widgets that can't move)
--  - handles multiple views of the MDI (through several top-level windows)
--  - have an icon-bar somewhere (or notebook) to list all the children
--  - Provide automatic initial placement of widgets
--  - Saving and restoring sessions (window location,...)
--  - When in a scrolled window, shouldn't constrain the possible coordinates
--  - When a toplevel window is destroyed, we must remove the child from
--    the MDI
--  - Icons should be put at the bottom, and automatically moved when the
--    MDI window is resized.
--  - When items are maximized, they should be put in a notebook.
--
--  From GNOME MDI documentation:
--  - GnomeMDI also provides means to create global menus and toolbar that
--    apply for each document and for merging document-specific menus with the
--    global ones

package Gtkada.MDI is

   type MDI_Window_Record is new Gtk.Widget.Gtk_Widget_Record with private;
   type MDI_Window is access all MDI_Window_Record'Class;
   --  Although this widget is implemented as a gtk_layout, you shouldn't
   --  use the standard Gtk_Layout functions like Put and Move yourself.

   type MDI_Child_Record is new Gtk.Event_Box.Gtk_Event_Box_Record
     with private;
   type MDI_Child is access all MDI_Child_Record'Class;
   --  A child of the MDI,  that encapsulate the widgets you have put in the
   --  MDI window.
   --  You can easily convert from this to the initial widget using the
   --  functions Find_MDI_Child and Get_Widget.

   type Dock_Side is (None, Left, Top, Right, Bottom);
   --  Side on which a child will be docked. If None, the child cannot be
   --  docked.

   procedure Gtk_New (MDI : out MDI_Window);
   --  Create a new MDI window.
   --  Note that it is recommended that you modify the style (Set_Background
   --  in State_Normal) to have a different color.

   procedure Initialize (MDI : access MDI_Window_Record'Class);
   --  Internal initialization function.
   --  See the section "Creating your own widgets" in the documentation.

   procedure Put (MDI : access MDI_Window_Record;
                  Child : access Gtk.Widget.Gtk_Widget_Record'Class;
                  Name : String);
   --  Add a new child to the MDI window.
   --  Note that there is a small difference between adding a toplevel
   --  Gtk_Window and a standard widget.
   --  In the former case, only the child of the window is inserted into MDI.
   --  However, every time the child is set as floating (ie in its own
   --  toplevel window), we reuse the window you give in parameter to Put.
   --  Likewise, before the child is destroyed, a "delete_event" is emitted
   --  on the window you give in parameter to Put).
   --
   --  In that case, you shouldn't access Child directly afterwards, but should
   --  manipulate its child instead. However, as a special exception, you can
   --  still pass Child as a parameter to the subprograms in this package to
   --  manipulate it (for instance in Raise_Child,...)
   --
   --  On the other hand, if you insert any other widget, toplevel windows
   --  are created on the fly when needed, and destroyed automatically.

   procedure Raise_Child (Child : access MDI_Child_Record'Class);
   --  Put Child in the foreground.

   procedure Minimize_Child
     (Child : access MDI_Child_Record'Class; Minimize : Boolean);
   --  Change the minimized state of a child.
   --  If the child was floating, it is first put back in the MDI

   function Get_Focus_Child
     (MDI : access MDI_Window_Record) return MDI_Child;
   --  Return the child that currently has the focus.
   --  null is returned if no child has the focus.

   -----------------------------------------
   -- MDI_Child and encapsulated children --
   -----------------------------------------

   function Get_Widget (Child : access MDI_Child_Record)
      return Gtk.Widget.Gtk_Widget;
   --  Return the widget that Child encapsulates. This is the widget you
   --  initially Put() in MDI.
   --  Note that if you put a toplevel Gtk_Window initially, this returns the
   --  child of the window.

   function Get_Window (Child : access MDI_Child_Record)
      return Gtk.Window.Gtk_Window;
   --  If you initially Put() a Gtk_Window in the MDI, this returns that
   --  window, although with no child (see Get_Widget instead).
   --  If you have put something else than a toplevel window, this function
   --  returns null.

   function Find_MDI_Child
     (MDI : access MDI_Window_Record;
      Widget : access Gtk.Widget.Gtk_Widget_Record'Class)
      return MDI_Child;
   --  Return the MDI_Child that encapsulates Widget.
   --  Widget must be the exact same one you gave in argument to Put.

   -----------------------------------
   -- Floating and docking children --
   -----------------------------------

   procedure Float_Child
     (Child : access MDI_Child_Record'Class; Float : Boolean);
   --  Change the floating state of a child

   function Is_Floating
     (Child : access MDI_Child_Record'Class) return Boolean;
   --  Return True if Child is currently in a separate window

   procedure Dock_Child
     (Child : access MDI_Child_Record'Class; Dock : Boolean := True);
   --  Change the docking start of a child.
   --  If the child was floating, it is first put back in the MDI

   procedure Set_Dock_Side
     (Child : access MDI_Child_Record'Class; Side  : Dock_Side);
   --  Specify where a child should be docked. Note that this doesn't
   --  actually dock the child.

   ---------------------------
   -- Reorganizing children --
   ---------------------------

   procedure Cascade_Children (MDI : access MDI_Window_Record);
   --  All the children are stacked so that the focus widget is on top.
   --  They overlap each other, but all the title bars are left visible

   procedure Tile_Horizontally (MDI : access MDI_Window_Record);
   procedure Tile_Vertically (MDI : access MDI_Window_Record);
   --  The available space in the MDI is shared equally between all children.
   --  They do not overlap each other.
   --  Tile_Horizontally with put children next to each other, Tile_Vertically
   --  will put children one below another. This is the same behavior as for
   --  Gtk_Vbox and Gtk_Hbox

   -------------
   -- Signals --
   -------------

   --  <signals>
   --  The following new signals are defined for this widget:
   --
   --  - "delete_event"
   --    function Handler (Child : access Gtk_Widget_Record'Class)
   --                     return Boolean;
   --
   --    This signal is emitted for each item in the MDI window before it is
   --    actually delete. The child is destroyed only if the handler returns
   --    False.
   --    Note that the Child passed in argument is exactly the one you passed
   --    to Put to insert it in the MDI window.
   --    Note that this is also the signal to use to prevent top level
   --    Gtk_Window from being destroyed.
   --  </signals>

private
   type State_Type is (Normal, Iconified, Floating, Docked);

   type MDI_Child_Record is new Gtk.Event_Box.Gtk_Event_Box_Record with record
      Initial : Gtk.Widget.Gtk_Widget;
      Initial_Child : Gtk.Widget.Gtk_Widget;
      --  The widget we used to build this child. This is used in case it
      --  was a window, since we need to be able to reparent it in the future,
      --  just in case.

      X, Y : Glib.Gint;
      State : State_Type := Normal;
      Name : GNAT.OS_Lib.String_Access;

      Dock : Dock_Side := None;

      Uniconified_Width, Uniconified_Height : Glib.Gint;
      --  The size of the window, when not iconified. When in normal state,
      --  this represents the size of the window, since we can not rely on
      --  Get_Allocation_Width and Get_Allocation_Height (in case for instance
      --  we just resized the widget but didn't go back to the main gtk loop)

      Uniconified_X, Uniconified_Y : Glib.Gint;
   end record;

   procedure Gtk_New (Child : out MDI_Child;
                      Widget : access Gtk.Widget.Gtk_Widget_Record'Class);
   --  Create a new MDI child that contains widget.

   procedure Initialize (Child : access MDI_Child_Record;
                         Widget : access Gtk.Widget.Gtk_Widget_Record'Class);
   --  Internal initialization function.
   --  See the section "Creating your own widgets" in the documentation.

   type MDI_Window_Record is new Gtk.Layout.Gtk_Layout_Record with record
      X_Root, Y_Root : Glib.Gint;
      --  Root coordinates of the button_press event that generated a move

      Selected_Child : MDI_Child;
      --  The child being moved

      Current_Cursor : Gdk.Types.Gdk_Cursor_Type := Gdk.Types.Left_Ptr;

      Initial_Width, Initial_Height : Glib.Gint;

      Focus_Child : MDI_Child := null;
      --  The widget that currently has the focus.

      Current_W, Current_H, Current_X, Current_Y : Glib.Gint;
      --  Current size and location of the widget that is currently
      --  resized. This is used for non-opaque resizing.

      GC   : Gdk.GC.Gdk_GC;
      Resize_GC : Gdk.GC.Gdk_GC;
      Focus_GC : Gdk.GC.Gdk_GC;
      Title_GC : Gdk.GC.Gdk_GC;
      --  The graphic contexts to draw the children.
   end record;

   pragma Inline (Get_Window);
   pragma Inline (Get_Widget);
   pragma Inline (Get_Focus_Child);
end Gtkada.MDI;
