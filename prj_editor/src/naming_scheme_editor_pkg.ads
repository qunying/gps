-----------------------------------------------------------------------
--                          G L I D E  I I                           --
--                                                                   --
--                        Copyright (C) 2001                         --
--                            ACT-Europe                             --
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

with Gtk.Window; use Gtk.Window;
with Gtk.Alignment; use Gtk.Alignment;
with Gtk.Box; use Gtk.Box;
with Gtk.Label; use Gtk.Label;
with Gtk.Combo; use Gtk.Combo;
with Gtk.GEntry; use Gtk.GEntry;
with Gtk.Frame; use Gtk.Frame;
with Gtk.GEntry; use Gtk.GEntry;
with Gtk.Scrolled_Window; use Gtk.Scrolled_Window;
with Gtk.Clist; use Gtk.Clist;
with Gtk.Button; use Gtk.Button;
package Naming_Scheme_Editor_Pkg is

   type Naming_Scheme_Editor_Record is new Gtk_Window_Record with record
      Alignment1 : Gtk_Alignment;
      Main_Box : Gtk_Vbox;
      Hbox4 : Gtk_Hbox;
      Label_Naming_Scheme : Gtk_Label;
      Standard_Scheme : Gtk_Combo;
      Combo_Entry3 : Gtk_Entry;
      Frame28 : Gtk_Frame;
      Vbox53 : Gtk_Vbox;
      Hbox5 : Gtk_Hbox;
      Label_Casing : Gtk_Label;
      Casing : Gtk_Combo;
      Combo_Entry2 : Gtk_Entry;
      Hbox7 : Gtk_Hbox;
      Label_Dot_Replacement : Gtk_Label;
      Dot_Replacement : Gtk_Entry;
      Hbox6 : Gtk_Hbox;
      Label_Spec_Extensions : Gtk_Label;
      Spec_Extension : Gtk_Combo;
      Combo_Entry4 : Gtk_Entry;
      Hbox8 : Gtk_Hbox;
      Label_Body_Extensions : Gtk_Label;
      Body_Extension : Gtk_Combo;
      Combo_Entry5 : Gtk_Entry;
      Hbox9 : Gtk_Hbox;
      Label_Separate_Extensions : Gtk_Label;
      Separate_Extension : Gtk_Combo;
      Combo_Entry6 : Gtk_Entry;
      Frame30 : Gtk_Frame;
      Vbox29 : Gtk_Vbox;
      Scrolledwindow1 : Gtk_Scrolled_Window;
      Exception_List : Gtk_Clist;
      Label28 : Gtk_Label;
      Label29 : Gtk_Label;
      Label30 : Gtk_Label;
      Hbox3 : Gtk_Hbox;
      Unit_Name_Entry : Gtk_Entry;
      Spec_Filename_Entry : Gtk_Entry;
      Body_Filename_Entry : Gtk_Entry;
      Update : Gtk_Button;
   end record;
   type Naming_Scheme_Editor_Access is access all Naming_Scheme_Editor_Record'Class;

   procedure Gtk_New (Naming_Scheme_Editor : out Naming_Scheme_Editor_Access);
   procedure Initialize (Naming_Scheme_Editor : access Naming_Scheme_Editor_Record'Class);

end Naming_Scheme_Editor_Pkg;
