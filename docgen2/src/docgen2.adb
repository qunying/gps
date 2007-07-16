-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                   Copyright (C) 2007, AdaCore                     --
--                                                                   --
-- GPS is free  software;  you can redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this program; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with Ada.Characters.Handling;               use Ada.Characters.Handling;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;                 use Ada.Strings.Unbounded;
with Ada.Text_IO;                           use Ada.Text_IO;

with GNAT.HTable;
with GNAT.Regpat;               use GNAT.Regpat;
with GNAT.Strings;              use GNAT.Strings;

with Basic_Types;
with Commands;                  use Commands;
with Doc_Utils;                 use Doc_Utils;
with Entities;                  use Entities;
with Entities.Queries;          use Entities.Queries;
with File_Utils;
with Find_Utils;
with GPS.Kernel;                use GPS.Kernel;
with GPS.Kernel.Contexts;       use GPS.Kernel.Contexts;
with GPS.Kernel.Project;        use GPS.Kernel.Project;
with GPS.Kernel.Standard_Hooks; use GPS.Kernel.Standard_Hooks;
with GPS.Kernel.Task_Manager;   use GPS.Kernel.Task_Manager;
with Language;                  use Language;
with Language.C;
with Language.Cpp;
with Language.Documentation;    use Language.Documentation;
with Language.Tree;             use Language.Tree;
with Language_Handlers;         use Language_Handlers;
with Projects;                  use Projects;
with Projects.Registry;         use Projects.Registry;
with String_Utils;              use String_Utils;
with Traces;                    use Traces;
with Templates_Parser;          use Templates_Parser;
with VFS; use VFS;

with Docgen2_Backend;           use Docgen2_Backend;

package body Docgen2 is

   Me : constant Debug_Handle := Create ("Docgen");

   type Entity_Info_Category is
     (Cat_File,
      Cat_Package,
      Cat_Class,
      Cat_Task,
      Cat_Protected,
      Cat_Type,
      Cat_Variable,
      Cat_Parameter,
      Cat_Subprogram,
      Cat_Entry,
      Cat_Unknown);

   function Image (Cat : Entity_Info_Category) return String;
   function Image (Cat : Language_Category) return String;
   --  Returns a printable image of the category

   type Entity_Info_Record (Category : Entity_Info_Category := Cat_Unknown);
   type Entity_Info is access all Entity_Info_Record;

   type Location_Type is record
      File_Loc : File_Location;
      Pkg_Nb   : Natural;
   end record;

   Null_Location : constant Location_Type :=
                     (File_Loc => No_File_Location,
                      Pkg_Nb   => 0);

   type Cross_Ref_Record;
   type Cross_Ref is access all Cross_Ref_Record;

   type Cross_Ref_Record is record
      Location      : File_Location;
      Name          : GNAT.Strings.String_Access;
      Xref          : Entity_Info := null;
      Inherited     : Boolean := False; -- Primitive operation cross-ref
      Overriding_Op : Cross_Ref;        -- Primitive operation cross-ref
   end record;

   package Cross_Ref_List is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Cross_Ref);

   package Entity_Info_List is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Entity_Info);

   package Locations_List is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => File_Location);

   package Files_List is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => VFS.Virtual_File);

   function Less_Than (Left, Right : Cross_Ref) return Boolean;
   function Less_Than (Left, Right : Entity_Info) return Boolean;
   function Less_Than (Left, Right : VFS.Virtual_File) return Boolean;
   --  Used to sort the children lists

   package Vector_Sort is new Cross_Ref_List.Generic_Sorting
     ("<" => Less_Than);

   package EInfo_Vector_Sort is new Entity_Info_List.Generic_Sorting
     ("<" => Less_Than);

   package Files_Vector_Sort is new Files_List.Generic_Sorting
     ("<" => Less_Than);

   type Entity_Info_Record (Category : Entity_Info_Category := Cat_Unknown)
      is record
         Lang_Category        : Language_Category;
         Name                 : GNAT.Strings.String_Access;
         Short_Name           : GNAT.Strings.String_Access;
         Description          : GNAT.Strings.String_Access;
         Printout             : GNAT.Strings.String_Access;
         Entity_Loc           : Source_Location;
         Printout_Loc         : Source_Location;
         Location             : Location_Type;
         Is_Abstract          : Boolean := False;
         Is_Private           : Boolean := False;
         Is_Generic           : Boolean := False;
         Generic_Params       : Entity_Info_List.Vector;
         Is_Renaming          : Boolean := False;
         Renamed_Entity       : Cross_Ref := null;
         Is_Instantiation     : Boolean := False;
         Instantiated_Entity  : Cross_Ref := null;
         Is_Partial           : Boolean := False;
         Full_Declaration     : Cross_Ref := null;
         Displayed            : Boolean := False;
         Children             : Entity_Info_List.Vector;
         References           : Locations_List.Vector;

         case Category is
            when Cat_Package | Cat_File =>
               Language       : Language_Access;
               File           : Source_File;
               Pkg_Nb         : Natural;
            when Cat_Task | Cat_Protected =>
               Is_Type        : Boolean;
            when Cat_Class =>
               Parents        : Cross_Ref_List.Vector;
               Class_Children : Cross_Ref_List.Vector;
               Primitive_Ops  : Cross_Ref_List.Vector;
            when Cat_Variable =>
               Variable_Type  : Cross_Ref := null;
            when Cat_Parameter =>
               Parameter_Type : Cross_Ref := null;
            when Cat_Subprogram | Cat_Entry =>
               Return_Type    : Cross_Ref := null;
            when others =>
               null;
         end case;
      end record;

   function Hash (Key : File_Location) return Ada.Containers.Hash_Type;
   function Equivalent_Keys (Left, Right : File_Location)
                             return Boolean;
   package Entity_Info_Map is new Ada.Containers.Indefinite_Hashed_Maps
     (File_Location, Entity_Info, Hash, Equivalent_Keys);
   --  A hashed set of nodes, identified by their 'loc' attribute

   function To_Category (Category : Language_Category)
                         return Entity_Info_Category;
   --  Translate language category into entity_info_category

   function Is_Spec_File
     (Kernel : access GPS.Kernel.Kernel_Handle_Record'Class;
      File   : VFS.Virtual_File) return Boolean;
   --  Whether File is a spec file

   function Get_Entity
     (Construct : String;
      Loc       : Source_Location;
      File      : Source_File;
      Db        : Entities_Database;
      Lang      : Language_Access) return Entity_Information;
   --  Retrieve the entity corresponding to construct, or create a new one.

   function Get_Declaration_Entity
     (Construct : String;
      Loc       : Source_Location;
      File      : Source_File;
      Db        : Entities_Database;
      Lang      : Language_Access) return Entity_Information;
   --  Retrieve the entity declaration corresponding to construct.

   function Filter_Documentation
     (Doc     : String;
      Options : Docgen_Options) return String;
   --  Filters the doc according to the Options.

   procedure Set_Printout
     (Construct   : Simple_Construct_Information;
      File_Buffer : GNAT.Strings.String_Access;
      E_Info      : in out Entity_Info);
   --  Retrieve the Source extract representing the construct, and
   --  set the printout field of E_Info

   procedure Set_Pkg_Printout
     (Construct   : Simple_Construct_Information;
      Entity      : Entity_Information;
      File_Buffer : GNAT.Strings.String_Access;
      E_Info      : in out Entity_Info);
   --  Retrieve the Source extract representing the header of the package, or
   --  the full construct if the package is an instantiation or a renaming.

   type Context_Stack_Element is record
      Parent_Entity : Entity_Info;
      Pkg_Entity    : Entity_Info;
      Parent_Iter   : Construct_Tree_Iterator;
   end record;

   package Context_Stack is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Context_Stack_Element);

   type Analysis_Context is record
      Stack       : Context_Stack.Vector;
      Iter        : Construct_Tree_Iterator;
      Tree        : Construct_Tree;
      File_Buffer : GNAT.Strings.String_Access;
      File        : Source_File;
      Language    : Language_Handler;
      Pkg_Nb      : Natural;
   end record;

   procedure Push
     (Context : in out Analysis_Context;
      Elem    : Context_Stack_Element);
   procedure Pop (Context : in out Analysis_Context);
   function Current (Context : Analysis_Context) return Context_Stack_Element;
   --  Context stack manipulation

   --  Command --
   type Docgen_Command is new Commands.Root_Command with record
      Kernel         : Kernel_Handle;
      Backend        : Docgen2_Backend.Backend_Handle;
      Project        : Projects.Project_Type;
      Source_Files   : File_Array_Access;
      Xref_List      : Cross_Ref_List.Vector;
      EInfo_Map      : Entity_Info_Map.Map;
      Class_List     : Cross_Ref_List.Vector;
      Documentation  : Entity_Info_List.Vector;
      File_Index     : Natural;
      Src_File_Index : Natural;
      Src_File_Iter  : Parse_Entities_Iterator;
      Buffer         : GNAT.Strings.String_Access;
      Src_Files      : Files_List.Vector;
      Files          : Cross_Ref_List.Vector;
      Analysis_Ctxt  : Analysis_Context;
      Options        : Docgen_Options;
      Cursor         : Entity_Info_List.Cursor;
      Doc_Gen        : Boolean := False;
   end record;
   --  Command used for generating the documentation

   type Docgen_Command_Access is access all Docgen_Command'Class;

   function Name (Command : access Docgen_Command) return String;
   function Progress (Command : access Docgen_Command) return Progress_Record;
   function Execute (Command : access Docgen_Command)
                     return Command_Return_Type;
   --  See inherited for documentation

   procedure Analyse_Construct
     (Context     : in out Analysis_Context;
      Options     : Docgen_Options;
      Db          : Entities_Database;
      EInfo_Map   : in out Entity_Info_Map.Map;
      Xref_List   : in out Cross_Ref_List.Vector;
      Class_List  : in out Cross_Ref_List.Vector);

   procedure Generate_Support_Files
     (Kernel : access Kernel_Handle_Record'Class;
      Backend : Backend_Handle);
   --  Generate support files in destination directory

   procedure Generate_Xrefs
     (XRef_List : in out Cross_Ref_List.Vector;
      EInfo_Map : Entity_Info_Map.Map);
   --  Generate all missing links in Xref_List

   procedure Generate_TOC
     (Kernel     : access Kernel_Handle_Record'Class;
      Backend    : Backend_Handle;
      Files      : in out Cross_Ref_List.Vector);
   --  Generate the Table Of Contents

   procedure Generate_Files_Index
     (Kernel     : access Kernel_Handle_Record'Class;
      Backend    : Backend_Handle;
      Src_Files  : Files_List.Vector);
   --  Generate the global src files index

   procedure Generate_Trees
     (Kernel     : access Kernel_Handle_Record'Class;
      Backend    : Backend_Handle;
      Class_List : in out Cross_Ref_List.Vector;
      EInfo_Map  : Entity_Info_Map.Map);
   --  Generate the global inheritance trees

   procedure Generate_Global_Index
     (Kernel     : access Kernel_Handle_Record'Class;
      Backend    : Backend_Handle;
      EInfo_Map  : Entity_Info_Map.Map);
   --  Generate the global index

   procedure Generate_Annotated_Source
     (Kernel  : access Kernel_Handle_Record'Class;
      Backend : Backend_Handle;
      File    : Source_File;
      Buffer  : GNAT.Strings.String_Access;
      Iter    : in out Parse_Entities_Iterator;
      Lang    : Language_Access;
      Db      : Entities_Database;
      Xrefs   : Entity_Info_Map.Map);
   --  Generate hrefs and pretty print on a source file.

   procedure Generate_Doc
     (Kernel    : access Kernel_Handle_Record'Class;
      Backend   : Backend_Handle;
      Xrefs     : Entity_Info_Map.Map;
      Lang      : Language_Access;
      Db        : Entities_Database;
      File      : Source_File;
      Files     : in out Cross_Ref_List.Vector;
      E_Info    : Entity_Info);
   --  Generate the final documentation for the specified Entity_Info.
   --  E_Info's category must be Cat_File

   --  UTILITIES FOR TAG HANDLING (TEMPLATE PARSER)

   generic
      type The_Type is private;
      with function "&" (Left : Tag; Right : The_Type) return Tag is <>;
   procedure Gen_Append
     (Translation : in out Translate_Set;
      Tag_Name    : String;
      Value       : The_Type);

   procedure Gen_Append
     (Translation : in out Translate_Set;
      Tag_Name    : String;
      Value       : The_Type)
   is
      E_Tag      : Tag;
      Prev_Assoc : Association;
   begin
      Prev_Assoc := Get (Translation, Tag_Name);

      if Prev_Assoc /= Null_Association then
         E_Tag := Get (Prev_Assoc);
      end if;

      E_Tag := E_Tag & Value;
      Insert (Translation, Assoc (Tag_Name, E_Tag));
   end Gen_Append;

   procedure Append
     (Translation : in out Translate_Set;
      Tag_Name    : String;
      Value       : String);
   procedure Append
     (Translation : in out Translate_Set;
      Tag_Name    : String;
      Value       : Tag);
   procedure Append is new Gen_Append (Boolean);
   procedure Append is new Gen_Append (Character);
   --  Append a new value to Tag_Name association.

   function Gen_Href
     (Backend : Backend_Handle;
      EInfo   : Entity_Info;
      Name    : String := "") return String;
   --  Generates a '<a href' tag, using Name to display or the entity's
   --  name if name is empty

   function Gen_Href
     (Backend : Backend_Handle;
      Xref    : Cross_Ref;
      Name    : String := "") return String;
   --  Same as above for Cross-Refs. If the cross-ref could not be found
   --  then only the name is displayed with no hyper-link

   function Location_Image (Loc : File_Location) return String;
   --  Return the location formated the gnat way: "file:line:col"

   function Get_Doc_Directory
     (Kernel : not null access Kernel_Handle_Record'Class) return String;
   --  Return the directory in which the documentation will be generated

   ---------------
   -- Less_Than --
   ---------------

   function Less_Than (Left, Right : Cross_Ref) return Boolean is
   begin
      if Left.Xref /= null and then Right.Xref /= null then
         return To_Lower (Left.Xref.Name.all) < To_Lower (Right.Xref.Name.all);
      else
         return To_Lower (Left.Name.all) < To_Lower (Right.Name.all);
      end if;
   end Less_Than;

   ---------------
   -- Less_Than --
   ---------------

   function Less_Than (Left, Right : Entity_Info) return Boolean is
   begin
      return To_Lower (Left.Short_Name.all) < To_Lower (Right.Short_Name.all);
   end Less_Than;

   ---------------
   -- Less_Than --
   ---------------

   function Less_Than (Left, Right : VFS.Virtual_File) return Boolean is
   begin
      return To_Lower (Base_Name (Left)) < To_Lower (Base_Name (Right));
   end Less_Than;

   -----------
   -- Image --
   -----------

   function Image (Cat : Entity_Info_Category) return String is
   begin
      case Cat is
         when Cat_File =>
            return "file";
         when Cat_Package =>
            return "package";
         when Cat_Class =>
            return "class";
         when Cat_Task =>
            return "task";
         when Cat_Protected =>
            return "protected";
         when Cat_Type =>
            return "type";
         when Cat_Variable =>
            return "constant or variable";
         when Cat_Parameter =>
            return "parameter";
         when Cat_Subprogram =>
            return "subprogram";
         when Cat_Entry =>
            return "entry";
         when Cat_Unknown =>
            return "";
      end case;
   end Image;

   -----------
   -- Image --
   -----------

   function Image (Cat : Language_Category) return String is
   begin
      case Cat is
         when Cat_Function =>
            return "function";
         when Cat_Procedure =>
            return "procedure";
         when others =>
            return Category_Name (Cat);
      end case;
   end Image;

   -----------------
   -- To_Category --
   -----------------

   function To_Category (Category : Language_Category)
                         return Entity_Info_Category is
   begin
      case Category is
         when Cat_Package =>
            return Cat_Package;
         when Cat_Class =>
            return Cat_Class;
         when Cat_Task =>
            return Cat_Task;
         when Cat_Protected =>
            return Cat_Protected;
         when Cat_Entry =>
            return Cat_Entry;
         when Cat_Structure | Cat_Union | Cat_Type | Cat_Subtype =>
            return Cat_Type;
         when Cat_Variable =>
            return Cat_Variable;
         when Cat_Parameter =>
            return Cat_Parameter;
         when Cat_Procedure | Cat_Function | Cat_Method =>
            return Cat_Subprogram;
         when others =>
            return Cat_Unknown;
      end case;
   end To_Category;

   ------------
   -- Append --
   ------------

   procedure Append
     (Translation : in out Translate_Set;
      Tag_Name    : String;
      Value       : String)
   is
      E_Tag      : Tag;
      Prev_Assoc : Association;
   begin
      Prev_Assoc := Get (Translation, Tag_Name);

      if Prev_Assoc /= Null_Association then
         E_Tag := Get (Prev_Assoc);
      end if;

      E_Tag := E_Tag & Value;
      Insert (Translation, Assoc (Tag_Name, E_Tag));
   end Append;

   ------------
   -- Append --
   ------------

   procedure Append
     (Translation : in out Translate_Set;
      Tag_Name    : String;
      Value       : Tag)
   is
      procedure Internal is new Gen_Append (Tag);
   begin
      if Size (Value) = 0 then
         Append (Translation, Tag_Name, "none");
      else
         Internal (Translation, Tag_Name, Value);
      end if;
   end Append;

   --------------
   -- Gen_Href --
   --------------

   function Gen_Href
     (Backend : Backend_Handle;
      EInfo   : Entity_Info;
      Name    : String := "") return String
   is
      Ref : constant String :=
              Backend.To_Href
                (Location_Image (EInfo.Location.File_Loc),
                 VFS.Base_Name
                   (Get_Filename (EInfo.Location.File_Loc.File)),
                 EInfo.Location.Pkg_Nb);
   begin
      if Name = "" then
         return Backend.Gen_Href
           (EInfo.Name.all, Ref,
            "defined at " & Location_Image (EInfo.Location.File_Loc));
      else
         return Backend.Gen_Href
           (Name, Ref,
            "defined at " & Location_Image (EInfo.Location.File_Loc));
      end if;
   end Gen_Href;

   --------------
   -- Gen_Href --
   --------------

   function Gen_Href
     (Backend : Backend_Handle;
      Xref    : Cross_Ref;
      Name    : String := "") return String
   is
   begin
      if Xref = null then
         return "";
      end if;

      if Xref.Xref /= null then
         if Name = "" then
            return Gen_Href (Backend, Xref.Xref, Xref.Name.all);
         else
            return Gen_Href (Backend, Xref.Xref, Name);
         end if;
      else
         if Name = "" then
            return Xref.Name.all;
         else
            return Name;
         end if;
      end if;
   end Gen_Href;

   --------------------
   -- Location_Image --
   --------------------

   function Location_Image (Loc : File_Location) return String is
      function Int_Img (I : Integer) return String;
      function Int_Img (I : Integer) return String is
         Str : constant String := Integer'Image (I);
      begin
         if Str (Str'First) = ' ' then
            return Str (Str'First + 1 .. Str'Last);
         else
            return Str;
         end if;
      end Int_Img;

   begin
      if Loc = No_File_Location then
         return "";
      end if;

      declare
         F_Name : constant String := Base_Name (Get_Filename (Get_File (Loc)));
      begin
         if F_Name = "<case_insensitive_predefined>"
           or else F_Name = "<case_sensitive_predefined>"
         then
            return "standard";
         end if;

         return F_Name & ":" &
           Int_Img (Get_Line (Loc)) & ":" &
           Int_Img (Integer (Get_Column (Loc)));
      end;
   end Location_Image;

   ------------------
   -- Is_Spec_File --
   ------------------

   function Is_Spec_File
     (Kernel : access GPS.Kernel.Kernel_Handle_Record'Class;
      File   : VFS.Virtual_File) return Boolean is
   begin
      return Get_Unit_Part_From_Filename
        (Get_Project_From_File (Get_Registry (Kernel).all, File), File) =
        Unit_Spec;
   end Is_Spec_File;

   ----------------
   -- Get_Entity --
   ----------------

   function Get_Entity
     (Construct : String;
      Loc       : Source_Location;
      File      : Source_File;
      Db        : Entities_Database;
      Lang      : Language_Access) return Entity_Information
   is
      Entity        : Entity_Information;
      --        Entity_Status : Find_Decl_Or_Body_Query_Status;
      Current_Loc   : File_Location;
      pragma Unreferenced (Db);

   begin
      Current_Loc :=
        (File   => File,
         Line   => Loc.Line,
         Column => Basic_Types.Visible_Column_Type (Loc.Column));

      Entity := Get_Or_Create
        (Construct,
         File,
         Current_Loc.Line,
         Current_Loc.Column,
         Allow_Create => False);

      if Entity = null and then Get_Name (Lang) = "Ada" then
         for J in Construct'Range loop
            --  ??? Ada Specific ... should use language service
            --  Need to define it !
            if Construct (J) = '.' then
               Current_Loc.Column :=
                 Basic_Types.Visible_Column_Type
                   (Loc.Column + J + 1 - Construct'First);

               Entity := Get_Or_Create
                 (Construct (J + 1 .. Construct'Last),
                  File,
                  Current_Loc.Line,
                  Current_Loc.Column,
                  Allow_Create => False);

               exit when Entity /= null;
            end if;
         end loop;
      end if;

      --  Last chance, force creation of entity
      if Entity = null then
         Current_Loc :=
           (File   => File,
            Line   => Loc.Line,
            Column => Basic_Types.Visible_Column_Type (Loc.Column));

         Entity := Get_Or_Create
           (Construct,
            File,
            Current_Loc.Line,
            Current_Loc.Column);
      end if;

      return Entity;
   end Get_Entity;

   ----------------------------
   -- Get_Declaration_Entity --
   ----------------------------

   function Get_Declaration_Entity
     (Construct : String;
      Loc       : Source_Location;
      File      : Source_File;
      Db        : Entities_Database;
      Lang      : Language_Access) return Entity_Information
   is
      Entity        : Entity_Information;
      Entity_Status : Find_Decl_Or_Body_Query_Status;
      Current_Loc   : File_Location;
   begin
      Current_Loc :=
        (File   => File,
         Line   => Loc.Line,
         Column => Basic_Types.Visible_Column_Type (Loc.Column));

      Find_Declaration
        (Db              => Db,
         File_Name       => Get_Filename (File),
         Entity_Name     => Construct,
         Line            => Current_Loc.Line,
         Column          => Current_Loc.Column,
         Entity          => Entity,
         Status          => Entity_Status,
         Check_Decl_Only => False);

      if Entity = null and then Get_Name (Lang) = "Ada" then
         for J in Construct'Range loop
            --  ??? Ada Specific ... should use language service
            --  Need to define it !
            if Construct (J) = '.' then
               Current_Loc.Column :=
                 Basic_Types.Visible_Column_Type
                   (Loc.Column + J + 1 - Construct'First);

               Find_Declaration
                 (Db,
                  File_Name       => Get_Filename (File),
                  Entity_Name     => Construct (J + 1 .. Construct'Last),
                  Line            => Current_Loc.Line,
                  Column          => Current_Loc.Column,
                  Entity          => Entity,
                  Status          => Entity_Status,
                  Check_Decl_Only => False);

               exit when Entity /= null;
            end if;
         end loop;
      end if;

      return Entity;
   end Get_Declaration_Entity;

   --------------------------
   -- Filter_Documentation --
   --------------------------

   function Filter_Documentation
     (Doc     : String;
      Options : Docgen_Options) return String
   is
      Matches : Match_Array (0 .. 0);
      use type GNAT.Expect.Pattern_Matcher_Access;
   begin
      if Options.Comments_Filter = null then
         return Doc;
      end if;

      Match (Options.Comments_Filter.all, Doc, Matches);

      if Matches (0) = No_Match then
         return Doc;
      end if;

      return Filter_Documentation
        (Doc (Doc'First .. Matches (0).First - 1) &
           Doc (Matches (0).Last + 1 .. Doc'Last),
         Options);
   end Filter_Documentation;

   ------------------
   -- Set_Printout --
   ------------------

   procedure Set_Printout
     (Construct   : Simple_Construct_Information;
      File_Buffer : GNAT.Strings.String_Access;
      E_Info      : in out Entity_Info)
   is
      Col, Line          : Natural;
      Idx_Start, Idx_End : Natural;
   begin
      E_Info.Printout_Loc := Construct.Sloc_Start;

      if Construct.Sloc_Start.Index < File_Buffer'First then
         --  Case where index is not initialized in the construct
         --  This happens with the C++ parser, for example.
         if Construct.Sloc_Start.Column /= 0
           and then Construct.Sloc_End.Column /= 0
         then
            Col := 1;
            Line := 1;
            Idx_Start := 0;
            Idx_End := 0;

            for J in File_Buffer'Range loop

               if File_Buffer (J) = ASCII.LF then
                  Line := Line + 1;
                  Col := 0;
               else
                  --  ??? what about utf-8 characters ?
                  Col := Col + 1;
               end if;

               if Line = Construct.Sloc_Start.Line
                 and then Col = Construct.Sloc_Start.Column
               then
                  Idx_Start := J;
               end if;

               if Line = Construct.Sloc_End.Line
                 and then Col = Construct.Sloc_End.Column
               then
                  Idx_End := J;
               end if;

               exit when Idx_Start /= 0 and then Idx_End /= 0;
            end loop;

            if Idx_Start /= 0 and then Idx_End /= 0 then
               E_Info.Printout_Loc.Index := Idx_Start;
               E_Info.Printout := new String'
                 (File_Buffer (Idx_Start .. Idx_End));
               return;
            end if;
         end if;
      end if;

      E_Info.Printout := new String'
        (File_Buffer
           (Construct.Sloc_Start.Index .. Construct.Sloc_End.Index));
   end Set_Printout;

   ----------------------
   -- Set_Pkg_Printout --
   ----------------------

   procedure Set_Pkg_Printout
     (Construct   : Simple_Construct_Information;
      Entity      : Entity_Information;
      File_Buffer : GNAT.Strings.String_Access;
      E_Info      : in out Entity_Info)
   is
      Start_Index : Natural;
      End_Index   : Natural;
      Pkg_Found   : Boolean;
      Entity_Kind : constant E_Kind := Get_Kind (Entity);

      function Is_Token (Token : String; Start_Index : Natural)
                         return Boolean;
      --  Test if Token is found at index Start_Index;

      function Is_Token (Token : String; Start_Index : Natural)
                         return Boolean is
      begin
         return Start_Index >= File_Buffer'First
           and then Start_Index + Token'Length <= File_Buffer'Last
           and then Is_Blank (File_Buffer (Start_Index + Token'Length))
           and then (Start_Index = File_Buffer'First
                     or else Is_Blank (File_Buffer (Start_Index - 1)))
           and then Equal
             (File_Buffer (Start_Index .. Start_Index + Token'Length - 1),
              Token,
              Case_Sensitive => False);
      end Is_Token;

   begin
      --  We assume Index is initialized, as the Ada parser does so.
      Start_Index := Construct.Sloc_Start.Index;
      End_Index := Construct.Sloc_Start.Index - 1;

      if Entity_Kind.Is_Generic then
         --  Look for 'generic' beforee Sloc_Start.Index
         for J in reverse File_Buffer'First ..
           Construct.Sloc_Start.Index - 6
         loop
            if Is_Token ("generic", J) then
               Start_Index := J;
               exit;
            end if;
         end loop;
      end if;

      --  If we have an instantiation or a renaming, then output the full
      --  printout
      if Is_Instantiation_Of (Entity) /= null
        or else Renaming_Of (Entity) /= null
      then
         End_Index := Construct.Sloc_End.Index;

      else
         --  We will stop after 'package XXX is'
         Pkg_Found := False;

         for J in Construct.Sloc_Start.Index .. Construct.Sloc_End.Index loop
            if not Pkg_Found and then Is_Token ("package", J) then
               Pkg_Found := True;
            end if;

            if Pkg_Found then
               --  After package keywork, expect a ' is '
               --  or a '; '
               if File_Buffer (J) = ';' then
                  End_Index := J;
                  exit;

               elsif Is_Token ("is", J) then
                  End_Index := J + 1;
                  exit;

               end if;
            end if;
         end loop;
      end if;

      E_Info.Printout := new String'(File_Buffer (Start_Index .. End_Index));

      if Start_Index /= Construct.Sloc_Start.Index then
         declare
            Line    : Natural := 1;
            Col     : Basic_Types.Character_Offset_Type := 1;
            V_Col   : Basic_Types.Visible_Column_Type := 1;
            L_Start : Natural := 1;
         begin
            Find_Utils.To_Line_Column
              (Buffer         => File_Buffer.all,
               Pos            => Start_Index,
               Line           => Line,
               Column         => Col,
               Visible_Column => V_Col,
               Line_Start     => L_Start);
            E_Info.Printout_Loc :=
              (Line   => Line,
               Column => Natural (Col),
               Index  => Start_Index);
         end;
      else
         E_Info.Printout_Loc := Construct.Sloc_Start;
      end if;
   end Set_Pkg_Printout;

   ----------
   -- Push --
   ----------

   procedure Push
     (Context : in out Analysis_Context;
      Elem    : Context_Stack_Element) is
   begin
      Context.Stack.Append (Elem);
   end Push;

   ---------
   -- Pop --
   ---------

   procedure Pop (Context : in out Analysis_Context) is
      Elem : Context_Stack_Element;
   begin
      if not Context.Stack.Is_Empty then
         Elem := Current (Context);
         Context.Iter := Next
           (Context.Tree, Elem.Parent_Iter, Jump_Over);
         Context.Stack.Delete_Last (Count => 1);
      end if;
   end Pop;

   -------------
   -- Current --
   -------------

   function Current (Context : Analysis_Context) return Context_Stack_Element
   is
   begin
      return Context.Stack.Last_Element;
   end Current;

   -----------------------
   -- Analyse_Construct --
   -----------------------

   procedure Analyse_Construct
     (Context     : in out Analysis_Context;
      Options     : Docgen_Options;
      Db          : Entities_Database;
      EInfo_Map   : in out Entity_Info_Map.Map;
      Xref_List   : in out Cross_Ref_List.Vector;
      Class_List  : in out Cross_Ref_List.Vector)
   is
      Construct   : Simple_Construct_Information;
      Entity      : Entity_Information := null;
      E_Info      : Entity_Info;
      Entity_Kind : E_Kind;
      Lang        : constant Language_Access :=
                      Get_Language_From_File
                        (Context.Language, Get_Filename (Context.File));
      Body_Location : File_Location;
      Context_Elem  : constant Context_Stack_Element := Current (Context);

      function Create_Xref (E    : Entity_Information) return Cross_Ref;
      function Create_Xref (Name : String; Loc : File_Location)
                            return Cross_Ref;
      --  Create a new Cross-Ref and update the Cross-Refs list

      function Create_EInfo (Cat : Language_Category;
                             Loc : File_Location) return Entity_Info;
      --  Create a new Entity Info and update the Entity info list

      -----------------
      -- Create_Xref --
      -----------------

      function Create_Xref (Name : String; Loc : File_Location)
                            return Cross_Ref is
         Xref : Cross_Ref;
      begin
         if Loc = No_File_Location then
            return null;
         end if;

         Xref := new Cross_Ref_Record'
           (Name         => new String'(Name),
            Location     => Loc,
            Xref         => null,
            Inherited    => False,
            Overriding_Op => null);

         Xref_List.Append (Xref);

         return Xref;
      end Create_Xref;

      -----------------
      -- Create_Xref --
      -----------------

      function Create_Xref (E : Entity_Information) return Cross_Ref is
      begin
         if E = null then
            return null;
         end if;

         --  If the cross ref is in the same file, use a simple name
         --  If in another file, then use the fully qualified name
         if Get_Declaration_Of (E).File = Get_Declaration_Of (Entity).File then
            return Create_Xref (Get_Name (E).all, Get_Declaration_Of (E));
         else
            return Create_Xref (Get_Full_Name (E), Get_Declaration_Of (E));
         end if;
      end Create_Xref;

      ------------------
      -- Create_EInfo --
      ------------------

      function Create_EInfo (Cat : Language_Category;
                             Loc : File_Location) return Entity_Info
      is
         E_Info : Entity_Info;

      begin
         E_Info := new Entity_Info_Record (Category => To_Category (Cat));
         E_Info.Lang_Category := Cat;

         if Loc /= No_File_Location then
            if Context_Elem.Pkg_Entity /= null then
               E_Info.Location := (File_Loc => Loc,
                                   Pkg_Nb   => Context_Elem.Pkg_Entity.Pkg_Nb);
            else
               E_Info.Location := (File_Loc => Loc, Pkg_Nb => 1);
            end if;

            EInfo_Map.Include (Loc, E_Info);
         else
            E_Info.Location := Null_Location;
         end if;

         if E_Info.Category = Cat_Class then
            Class_List.Append
              (Create_Xref
                 (Get_Name (Entity).all, Get_Declaration_Of (Entity)));
         end if;

         return E_Info;
      end Create_EInfo;

   begin
      --  Exit when no more construct is available
      if Context.Iter = Null_Construct_Tree_Iterator then
         return;
      end if;

      --  If scope has changed, pop the context and return
      if Context_Elem.Parent_Iter /= Null_Construct_Tree_Iterator
        and then Get_Parent_Scope (Context.Tree, Context.Iter) /=
          Context_Elem.Parent_Iter
      then
         Pop (Context);
         return;
      end if;

      Construct := Get_Construct (Context.Iter);

      --  Ignore the private part
      if Construct.Visibility = Visibility_Private
        and then not Options.Show_Private
      then
         Pop (Context);
         return;
      end if;

      --  Ignoring with, use clauses
      --  Ignoring parameters, directly handled in subprogram nodes
      --  Ignoring represenation clauses.
      --  Ignoring constructs whose category is Unknown
      --  Ignoring unnamed entities.
      if Construct.Category not in Dependency_Category
        and then Construct.Category /= Cat_Representation_Clause
        and then Construct.Category /= Cat_Namespace
        and then Category_Name (Construct.Category) /= ""
        and then Construct.Name /= null
      then
         Entity := Get_Entity
           (Construct.Name.all, Construct.Sloc_Entity, Context.File, Db, Lang);
      end if;

      if Entity /= null then
         Entity_Kind := Get_Kind (Entity);

         E_Info := Create_EInfo (Construct.Category,
                                 Get_Declaration_Of (Entity));
         Context_Elem.Parent_Entity.Children.Append (E_Info);
         E_Info.Entity_Loc := Construct.Sloc_Entity;

         --  First set values common to all categories

         --  Set Name
         if Construct.Category = Cat_Package then
            --  Packages receive fully qualified names
            E_Info.Name := new String'(Get_Full_Name (Entity));
         else
            E_Info.Name := new String'(Get_Name (Entity).all);
         end if;

         E_Info.Short_Name := new String'(Get_Name (Entity).all);

         --  Retrieve documentation comments
         declare
            Doc : constant String :=
                    Filter_Documentation
                      (Get_Documentation
                         (Context.Language,
                          Entity,
                          Context.File_Buffer.all),
                       Options);
         begin
            if Doc /= "" then
               E_Info.Description := new String'(Doc);
            end if;
         end;

         --  Retrieve printout

         if Construct.Category not in Namespace_Category then
            Set_Printout (Construct, Context.File_Buffer, E_Info);
         elsif Construct.Category = Cat_Package then
            Set_Pkg_Printout (Construct, Entity, Context.File_Buffer, E_Info);
         end if;

         --  Retrieve references

         declare
            Iter : Entity_Reference_Iterator;
            Ref  : Entity_Reference;
         begin
            if Options.References
              and then Construct.Category /= Cat_Package
            then
               Find_All_References (Iter, Entity);

               while not At_End (Iter) loop
                  Ref := Get (Iter);

                  if Ref /= No_Entity_Reference then
                     E_Info.References.Append (Get_Location (Ref));
                  end if;

                  Next (Iter);
               end loop;
            end if;
         end;

         E_Info.Is_Abstract := Entity_Kind.Is_Abstract;
         E_Info.Is_Private := Construct.Visibility = Visibility_Private;
         E_Info.Is_Generic := Entity_Kind.Is_Generic;
         E_Info.Is_Renaming := Renaming_Of (Entity) /= null;
         E_Info.Is_Instantiation := Is_Instantiation_Of (Entity) /= null;

         --  Init common children

         --  generic parameters:
         if E_Info.Is_Generic then
            declare
               Iter         : Generic_Iterator;
               Param_Entity : Entity_Information;
               Param_EInfo  : Entity_Info;
            begin
               Iter := Get_Generic_Parameters (Entity);

               loop
                  Get (Iter, Param_Entity);

                  exit when Param_Entity = null;

                  Param_EInfo := Create_EInfo
                    (Cat_Parameter,
                     Get_Declaration_Of (Param_Entity));
                  Param_EInfo.Name := new String'(Get_Name (Param_Entity).all);

                  declare
                     Doc : constant String :=
                             Filter_Documentation
                               (Get_Documentation
                                  (Context.Language,
                                   Param_Entity,
                                   Context.File_Buffer.all),
                                Options);
                  begin
                     if Doc /= "" then
                        Param_EInfo.Description := new String'(Doc);
                     end if;
                  end;

                  --  ??? need a better handling of formal parameters types
                  Param_EInfo.Parameter_Type := new Cross_Ref_Record'
                    (Name         => new String'
                                    (Kind_To_String (Get_Kind (Param_Entity))),
                     Location     => No_File_Location,
                     Xref         => null,
                     Inherited    => False,
                     Overriding_Op => null);

                  E_Info.Generic_Params.Append (Param_EInfo);

                  Next (Iter);
               end loop;
            end;
         end if;

         --  Renamed entity
         if E_Info.Is_Renaming then
            declare
               Renamed_Entity : constant Entity_Information :=
                                  Renaming_Of (Entity);
            begin
               E_Info.Renamed_Entity := Create_Xref (Renamed_Entity);
            end;
         end if;

         --  Entity is an instantiation
         if E_Info.Is_Instantiation then
            declare
               Instantiated_Entity : constant Entity_Information :=
                                       Is_Instantiation_Of (Entity);
            begin
               E_Info.Instantiated_Entity := Create_Xref (Instantiated_Entity);
            end;
         end if;

         --  Is the entity a partial declaration ?
         Body_Location := No_File_Location;

         if not Is_Container (Get_Kind (Entity).Kind) then
            Find_Next_Body
              (Entity   => Entity,
               Location => Body_Location);
         end if;

         if Body_Location /= No_File_Location
           and then Body_Location /= E_Info.Location.File_Loc
           and then Body_Location.File = Context.File
         then
            E_Info.Is_Partial := True;
            E_Info.Full_Declaration :=
              Create_Xref (E_Info.Name.all, Body_Location);
         end if;

         --  Initialize now category specific parameters
         case E_Info.Category is
            when Cat_Package =>
               if not E_Info.Is_Instantiation
                 and then not E_Info.Is_Renaming
               then
                  --  Bump pkg nb
                  Context.Pkg_Nb := Context.Pkg_Nb + 1;
                  E_Info.Pkg_Nb := Context.Pkg_Nb;
                  E_Info.Location.Pkg_Nb := Context.Pkg_Nb;

                  if E_Info.Is_Generic then
                     declare
                        Cursor : Entity_Info_List.Cursor;
                     begin
                        Cursor := Entity_Info_List.First
                          (E_Info.Generic_Params);

                        while Entity_Info_List.Has_Element (Cursor) loop
                           Entity_Info_List.Element (Cursor).Location.Pkg_Nb :=
                             E_Info.Pkg_Nb;
                           Entity_Info_List.Next (Cursor);
                        end loop;
                     end;
                  end if;

                  --  Get children
                  declare
                     New_Context : constant Context_Stack_Element :=
                                     (Parent_Entity => E_Info,
                                      Pkg_Entity    => E_Info,
                                      Parent_Iter   => Context.Iter);
                  begin
                     Push (Context, New_Context);
                     Context.Iter := Next
                       (Context.Tree, Context.Iter, Jump_Into);
                     return;
                  end;
               end if;

            when Cat_Task | Cat_Protected =>
               --  Get children (task entries)

               declare
                  New_Context : constant Context_Stack_Element :=
                                  (Parent_Entity => E_Info,
                                   Pkg_Entity    => Context_Elem.Pkg_Entity,
                                   Parent_Iter   => Context.Iter);
               begin
                  Push (Context, New_Context);
                  Context.Iter := Next
                    (Context.Tree, Context.Iter, Jump_Into);
                  return;
               end;

            when Cat_Class =>
               --  Get parents
               Trace (Me, "Get class parents");
               declare
                  Parents : constant Entity_Information_Array :=
                              Get_Parent_Types (Entity, Recursive => True);
               begin
                  for J in Parents'Range loop
                     E_Info.Parents.Append (Create_Xref (Parents (J)));
                  end loop;
               end;

               --  Get known children
               Trace (Me, "Get known children");
               declare
                  Children : constant Entity_Information_Array :=
                               Get_Child_Types (Entity, Recursive => False);
               begin
                  for J in Children'Range loop
                     E_Info.Class_Children.Append
                       (Create_Xref
                          (Get_Name (Children (J)).all,
                           Get_Declaration_Of (Children (J))));
                  end loop;
               end;

               --  Get primitive operations
               Trace (Me, "Get primitive operations");

               declare
                  Iter, Iter_First : Primitive_Operations_Iterator;
                  E_Overriden      : Entity_Information;
                  Op_Xref          : Cross_Ref;
                  Nb_Primop        : Natural;

               begin
                  Find_All_Primitive_Operations (Iter, Entity, True);
                  Trace (Me, "All primitive operations found: start filter");

                  Iter_First := Iter;

                  Nb_Primop := 0;

                  while not At_End (Iter) loop
                     Nb_Primop := Nb_Primop + 1;
                     Next (Iter);
                  end loop;

                  declare
                     type Primop_Info is record
                        Entity    : Entity_Information;
                        Overriden : Boolean;
                     end record;

                     List : array (1 .. Nb_Primop) of Primop_Info;

                  begin
                     Iter := Iter_First;

                     --  Init the list of primitive operations
                     for J in List'Range loop
                        List (J) := (Get (Iter), False);
                        Next (Iter);
                     end loop;

                     --  Search for overriden operations
                     for J in List'Range loop
                        E_Overriden := Overriden_Entity (List (J).Entity);

                        for K in J + 1 .. List'Last loop
                           if E_Overriden = List (K).Entity then
                              List (K).Overriden := True;
                           end if;
                        end loop;
                     end loop;

                     --  Insert non overriden operations in the xref list.
                     for J in List'Range loop
                        if not List (J).Overriden then
                           Op_Xref := Create_Xref  (List (J).Entity);

                           Op_Xref.Inherited :=
                             Is_Primitive_Operation_Of (List (J).Entity) /=
                             Entity;

                           E_Overriden := Overriden_Entity (List (J).Entity);

                           if E_Overriden /= null then
                              Op_Xref.Overriding_Op :=
                                Create_Xref (E_Overriden);
                           end if;

                           E_Info.Primitive_Ops.Append (Op_Xref);
                        end if;
                     end loop;
                  end;
               end;

               Trace (Me, "End class analysis");

            when Cat_Variable =>
               --  Get its type
               declare
                  Type_Entity : Entity_Information;
               begin
                  Type_Entity := Get_Type_Of (Entity);

                  if Type_Entity = null then
                     Type_Entity := Pointed_Type (Entity);
                  end if;

                  if Type_Entity = null then
                     Type_Entity := Get_Variable_Type (Entity);
                  end if;

                  if Type_Entity = null then
                     Type_Entity := Get_Returned_Type (Entity);
                  end if;

                  if Type_Entity /= null then
                     E_Info.Variable_Type := Create_Xref (Type_Entity);
                  end if;
               end;

            when Cat_Parameter =>
               declare
                  Type_Entity : Entity_Information;
               begin
                  Type_Entity := Get_Type_Of (Entity);

                  if Type_Entity = null then
                     Type_Entity := Pointed_Type (Entity);
                  end if;

                  if Type_Entity /= null then
                     E_Info.Parameter_Type := Create_Xref (Type_Entity);
                  else
                     --  don't know the type, let's use the printout as name
                     E_Info.Parameter_Type :=
                       new Cross_Ref_Record'
                         (Name          => new String'
                              (Context.File_Buffer
                                   (Construct.Sloc_Start.Index +
                                        Construct.Name.all'Length ..
                                          Construct.Sloc_End.Index)),
                          Location      => No_File_Location,
                          Xref          => null,
                          Inherited     => False,
                          Overriding_Op => null);
                  end if;
               end;

            when Cat_Subprogram | Cat_Entry =>
               --  Get the parameters and return type

               --  Parameters
               declare
                  New_Context : constant Context_Stack_Element :=
                                  (Parent_Entity => E_Info,
                                   Pkg_Entity    => Context_Elem.Pkg_Entity,
                                   Parent_Iter   => Context.Iter);
                  Type_Entity : Entity_Information;
               begin
                  --  Return type
                  Type_Entity := Get_Returned_Type (Entity);

                  if Type_Entity /= null then
                     E_Info.Return_Type := Create_Xref (Type_Entity);
                  end if;

                  Push (Context, New_Context);
                  Context.Iter := Next
                    (Context.Tree, Context.Iter, Jump_Into);
                  return;
               end;

            when others =>
               --  ??? Todo:
               --  Cat_Constructor (idem)
               --  Cat_Destructor (idem)
               --  Cat_Local_Variable (should not require anything, since we
               --   are evaluating specs)
               --  Cat_Field (do we want to detail a record's field ?)
               --  Cat_Literal (do we want to output anything for a literal ?)
               null;
         end case;
      end if;

      Context.Iter := Next
        (Context.Tree, Context.Iter, Jump_Over);
   end Analyse_Construct;

   ----------
   -- Hash --
   ----------

   function Hash (Key : File_Location) return Ada.Containers.Hash_Type is
      type Internal_Hash_Type is range 0 .. 2 ** 31 - 1;
      function Internal is new GNAT.HTable.Hash
        (Header_Num => Internal_Hash_Type);
   begin
      return Ada.Containers.Hash_Type
        (Internal
           (VFS.Full_Name (Get_Filename (Key.File)).all &
            Natural'Image (Key.Line) &
            Basic_Types.Visible_Column_Type'Image (Key.Column)));
   end Hash;

   -------------------------
   -- Equivalent_Elements --
   -------------------------

   function Equivalent_Keys (Left, Right : File_Location)
                             return Boolean is
      use Basic_Types;
   begin
      return Left.File = Right.File
        and then Left.Line = Right.Line
        and then Left.Column = Right.Column;
   end Equivalent_Keys;

   ----------
   -- Name --
   ----------

   function Name (Command : access Docgen_Command) return String is
      pragma Unreferenced (Command);
   begin
      return "Documentation generator";
   end Name;

   --------------
   -- Progress --
   --------------

   function Progress (Command : access Docgen_Command) return Progress_Record
   is
   begin
      if Command.File_Index < Command.Source_Files'Last then
         return (Activity => Running,
                 Current  => Command.File_Index,
                 Total    => Command.Source_Files'Length * 2);
      elsif Command.Src_File_Index < Command.Source_Files'Last then
         return (Activity => Running,
                 Current  => Command.Source_Files'Length +
                               Command.Src_File_Index,
                 Total    => Command.Source_Files'Length * 2);
      else
         return (Activity => Stalled,
                 Current  => Command.Source_Files'Length * 2,
                 Total    => Command.Source_Files'Length * 2);
      end if;
   end Progress;

   -------------
   -- Execute --
   -------------

   function Execute (Command : access Docgen_Command)
                     return Command_Return_Type
   is
      File_EInfo    : Entity_Info;
      File_Buffer   : GNAT.Strings.String_Access;
      Comment_Start : Natural;
      Comment_End   : Integer;
      Database      : constant Entities_Database :=
                        Get_Database (Command.Kernel);
      use type Ada.Containers.Count_Type;
   begin
      if Command.Analysis_Ctxt.Iter /= Null_Construct_Tree_Iterator then
         --  Analysis of a new construct of the current file.
         Analyse_Construct
           (Command.Analysis_Ctxt, Command.Options,
            Db          => Get_Database (Command.Kernel),
            EInfo_Map   => Command.EInfo_Map,
            Xref_List   => Command.Xref_List,
            Class_List  => Command.Class_List);

      elsif Command.File_Index < Command.Source_Files'Last then
         --  Current file has been analysed, Let's start the next one

         Command.File_Index := Command.File_Index + 1;

         --  Clean-up previous context if needed
         Free (Command.Analysis_Ctxt.Tree);
         Free (Command.Analysis_Ctxt.File_Buffer);

         --  Only analyze specs
         if Is_Spec_File (Command.Kernel,
                          Command.Source_Files (Command.File_Index))
         then
            --  Create the new entity info structure
            File_EInfo := new Entity_Info_Record
              (Category => Cat_File);
            File_EInfo.Name := new String'
              (Base_Name (Command.Source_Files (Command.File_Index)));
            File_EInfo.Short_Name := File_EInfo.Name;

            Trace (Me, "Analysis of file " & File_EInfo.Name.all);

            --  And add it to the global documentation list
            Command.Documentation.Append (File_EInfo);

            declare
               Lang_Handler  : constant Language_Handler :=
                                 Get_Language_Handler (Command.Kernel);
               Language      : constant Language_Access :=
                                 Get_Language_From_File
                                   (Lang_Handler,
                                    Command.Source_Files (Command.File_Index));
               Construct_T   : Construct_Tree;
               Constructs    : aliased Construct_List;
               Ctxt_Elem     : Context_Stack_Element;
               use type Ada.Containers.Count_Type;

            begin
               File_EInfo.Language := Language;
               File_EInfo.File := Get_Or_Create
                 (Database,
                  Command.Source_Files (Command.File_Index));
               File_Buffer := Read_File
                 (Command.Source_Files (Command.File_Index));

               --  In case of C/C++, the LI_Handler's Parse_File_Construct
               --  work much better than Language's Parse_Construct.
               if Language.all in Cpp.Cpp_Language'Class
                 or else Language.all in C.C_Language'Class
               then
                  declare
                     Handler : LI_Handler;
                  begin
                     Handler := Get_LI_Handler_From_File
                       (Lang_Handler,
                        Command.Source_Files (Command.File_Index));

                     if Handler /= null then
                        Parse_File_Constructs
                          (Handler,
                           Lang_Handler,
                           Command.Source_Files (Command.File_Index),
                           Constructs);
                     else
                        Parse_Constructs
                          (Language, File_Buffer.all, Constructs);
                     end if;
                  end;
               else
                  Parse_Constructs
                    (Language, File_Buffer.all, Constructs);
               end if;
               Construct_T := To_Construct_Tree (Constructs'Access, True);

               --  Retrieve the file's main unit comments, if any

               --  If the main unit is documented, then there are
               --  great chances that the comment is at the beginning
               --  of the file. Let's look for it

               --  Try to retrieve the documentation before the first
               --  construct.

               Comment_End :=
                 Get_Construct (First (Construct_T)).Sloc_Start.Index - 1;

               --  Now skip all blanks before this first construct
               while Comment_End > File_Buffer'First loop
                  Skip_Blanks (File_Buffer.all,
                               Comment_End,
                               -1);
                  exit when File_Buffer (Comment_End) /= ASCII.LF;
                  Comment_End := Comment_End - 1;
               end loop;

               --  Now try to get a documentation before where we are
               Get_Documentation_Before
                 (Get_Language_Context (Language).all,
                  File_Buffer.all,
                  Comment_End + 1,
                  Comment_Start,
                  Comment_End);

               --  Now that we have a comment block, we need to
               --  extract it without the comment markups
               if Comment_Start /= 0 then
                  declare
                     Block : constant String :=
                               Filter_Documentation
                                 (Comment_Block
                                    (Language,
                                     File_Buffer
                                       (Comment_Start .. Comment_End),
                                     Comment => False,
                                     Clean   => True),
                                  Command.Options);
                  begin
                     if Block /= "" then
                        --  Add this description to the unit node
                        File_EInfo.Description := new String'(Block);
                     end if;
                  end;
               end if;

               --  We now create the command's analysis_ctxt structure
               Command.Analysis_Ctxt.Iter        := First (Construct_T);
               Command.Analysis_Ctxt.Tree        := Construct_T;
               Command.Analysis_Ctxt.File_Buffer := File_Buffer;
               Command.Analysis_Ctxt.Language    := Lang_Handler;
               Command.Analysis_Ctxt.File        := File_EInfo.File;
               Command.Analysis_Ctxt.Pkg_Nb      := 0;

               Ctxt_Elem := (Parent_Entity => File_EInfo,
                             Pkg_Entity    => null,
                             Parent_Iter   => Null_Construct_Tree_Iterator);
               Push (Command.Analysis_Ctxt, Ctxt_Elem);
               --  Push it twice, so that one remains when the file analysis
               --  is finished
               Push (Command.Analysis_Ctxt, Ctxt_Elem);
            end;
         end if;

      elsif not Command.Doc_Gen then
         --  All files analysed. Let's generate the documentation

         --  Clean-up previous context if needed
         Free (Command.Analysis_Ctxt.Tree);
         Free (Command.Analysis_Ctxt.File_Buffer);

         Generate_Support_Files (Command.Kernel, Command.Backend);

         --  Generate all cross-refs
         Trace (Me, "Generate all Cross-Refs");
         Generate_Xrefs (Command.Xref_List, Command.EInfo_Map);

         Command.Doc_Gen := True;
         Command.Cursor := Command.Documentation.First;

      elsif Entity_Info_List.Has_Element (Command.Cursor) then
         --  Documentation generation has already started.

         --  For every file, generate the documentation.
         declare
            EInfo   : constant Entity_Info :=
                        Entity_Info_List.Element (Command.Cursor);
         begin
            Trace (Me, "Generate doc for " & EInfo.Name.all);
            Generate_Doc
              (Kernel  => Command.Kernel,
               Backend => Command.Backend,
               Xrefs   => Command.EInfo_Map,
               Lang    => EInfo.Language,
               Db      => Database,
               File    => EInfo.File,
               Files   => Command.Files,
               E_Info  => EInfo);
            Entity_Info_List.Next (Command.Cursor);
         end;

      elsif Command.Src_File_Index < Command.Source_Files'Last then
         --  Generate annotated source files

         if At_End (Command.Src_File_Iter) then
            Command.Src_File_Index := Command.Src_File_Index + 1;

            if Is_Spec_File (Command.Kernel,
                             Command.Source_Files (Command.Src_File_Index))
              or else Command.Options.Process_Body_Files
            then
               Command.Src_Files.Append
                 (Command.Source_Files (Command.Src_File_Index));

               Trace
                 (Me, "Generate annotated source for " &
                  Base_Name
                    (Command.Source_Files (Command.Src_File_Index)));

               Free (Command.Buffer);
               Command.Buffer :=
                 VFS.Read_File (Command.Source_Files (Command.Src_File_Index));

               Command.Src_File_Iter := Get_Parse_Entities_Iterator
                 (Command.Buffer.all);

            end if;
         else
            declare
               Lang_Handler  : constant Language_Handler :=
                                 Get_Language_Handler (Command.Kernel);
               Language      : constant Language_Access :=
                                 Get_Language_From_File
                                   (Lang_Handler,
                                    Command.Source_Files
                                      (Command.Src_File_Index));
            begin
               Generate_Annotated_Source
                 (Kernel  => Command.Kernel,
                  Backend => Command.Backend,
                  File    => Get_Or_Create
                    (Database, Command.Source_Files (Command.Src_File_Index)),
                  Buffer  => Command.Buffer,
                  Iter    => Command.Src_File_Iter,
                  Lang    => Language,
                  Db      => Database,
                  Xrefs   => Command.EInfo_Map);
            end;
         end if;

      else
         --  No more file processing. Let's print indexes.

         Files_Vector_Sort.Sort (Command.Src_Files);
         Generate_Files_Index
           (Command.Kernel, Command.Backend, Command.Src_Files);

         Generate_Trees
           (Command.Kernel, Command.Backend,
            Command.Class_List, Command.EInfo_Map);

         Generate_Global_Index
           (Command.Kernel, Command.Backend, Command.EInfo_Map);

         Generate_TOC
           (Command.Kernel, Command.Backend, Command.Files);

         Templates_Parser.Release_Cache;
         Free (Command.Buffer);

         --  ??? todo: cleanup everything

         return Success;
      end if;

      return Execute_Again;

   exception
      when E : others =>
         Trace (Exception_Handle, E);
         return Failure;
   end Execute;

   --------------
   -- Generate --
   --------------

   procedure Generate
     (Kernel  : not null access GPS.Kernel.Kernel_Handle_Record'Class;
      Backend : Docgen2_Backend.Backend_Handle;
      File    : VFS.Virtual_File;
      Options : Docgen_Options)
   is
      P             : constant Project_Type :=
                        Get_Project_From_File
                          (Registry          => Get_Registry (Kernel).all,
                           Source_Filename   => File,
                           Root_If_Not_Found => True);
      Source_Files  : constant File_Array_Access :=
                        new File_Array'(1 => File);
      C             : Docgen_Command_Access;
   begin
      Parse_All_LI_Information (Kernel, P, False);

      C := new Docgen_Command;
      C.Kernel         := Kernel_Handle (Kernel);
      C.Backend        := Backend;
      C.Project        := P;
      C.Source_Files   := Source_Files;
      C.File_Index     := Source_Files'First - 1;
      C.Src_File_Index := Source_Files'First - 1;
      C.Src_File_Iter  := No_Parse_Entities_Iterator;
      C.Options        := Options;
      C.Analysis_Ctxt.Iter := Null_Construct_Tree_Iterator;

      Launch_Background_Command
        (Kernel,
         Command         => C,
         Active          => True,
         Show_Bar        => True,
         Destroy_On_Exit => True,
         Block_Exit      => True);
   end Generate;

   --------------
   -- Generate --
   --------------

   procedure Generate
     (Kernel    : not null access GPS.Kernel.Kernel_Handle_Record'Class;
      Backend   : Docgen2_Backend.Backend_Handle;
      Project   : Projects.Project_Type;
      Options   : Docgen_Options;
      Recursive : Boolean := False)
   is
      C             : Docgen_Command_Access;
      P             : Projects.Project_Type := Project;
      Context       : Selection_Context;
   begin
      if P = No_Project then
         Context := Get_Current_Context (Kernel);

         if Has_Project_Information (Context) then
            P := Project_Information (Context);
         else
            P := Get_Project (Kernel);
         end if;
      end if;

      Parse_All_LI_Information (Kernel, P, Recursive);

      declare
         Source_Files  : constant File_Array_Access :=
                           Get_Source_Files (P, Recursive);
      begin
         C := new Docgen_Command;
         C.Kernel         := Kernel_Handle (Kernel);
         C.Backend        := Backend;
         C.Project        := P;
         C.Source_Files   := Source_Files;
         C.Src_File_Index := Source_Files'First - 1;
         C.Src_File_Iter  := No_Parse_Entities_Iterator;
         C.File_Index     := Source_Files'First - 1;
         C.Options        := Options;
         C.Analysis_Ctxt.Iter := Null_Construct_Tree_Iterator;
      end;

      Launch_Background_Command
        (Kernel,
         Command         => C,
         Active          => True,
         Show_Bar        => True,
         Destroy_On_Exit => True,
         Block_Exit      => True);
   end Generate;

   -------------------------------
   -- Generate_Annotated_Source --
   -------------------------------

   procedure Generate_Annotated_Source
     (Kernel  : access Kernel_Handle_Record'Class;
      Backend : Backend_Handle;
      File    : Source_File;
      Buffer  : GNAT.Strings.String_Access;
      Iter    : in out Parse_Entities_Iterator;
      Lang    : Language_Access;
      Db      : Entities_Database;
      Xrefs   : Entity_Info_Map.Map)
   is
      Last_Idx    : Natural := 0;
      Printout    : Unbounded_String;
      File_Handle : File_Type;
      Translation : Translate_Set;
      Tmpl        : constant String :=
                      Backend.Get_Template
                        (Get_System_Dir (Kernel), Tmpl_Src);

      function CB
        (Entity         : Language_Entity;
         Sloc_Start     : Source_Location;
         Sloc_End       : Source_Location;
         Partial_Entity : Boolean) return Boolean;

      --------
      -- CB --
      --------

      function CB
        (Entity         : Language_Entity;
         Sloc_Start     : Source_Location;
         Sloc_End       : Source_Location;
         Partial_Entity : Boolean) return Boolean
      is
         pragma Unreferenced (Partial_Entity);
         Decl_Entity        : Entity_Information;
         EInfo_Cursor       : Entity_Info_Map.Cursor;
         EInfo              : Entity_Info;
         Loc                : File_Location;
         use Basic_Types;
      begin
         --  Print all text between previous call and current one
         if Last_Idx /= 0 then
            Printout := Printout &
            Buffer (Last_Idx + 1 .. Sloc_Start.Index - 1);
         end if;

         Last_Idx := Sloc_End.Index;

         if Entity /= Identifier_Text
           and then Entity /= Partial_Identifier_Text
         then
            --  For all entities that are not identifiers, print them
            --  directly
            Printout := Printout &
            Backend.Gen_Tag
              (Entity, Buffer (Sloc_Start.Index .. Sloc_End.Index));

         else
            --  If entity is an identifier or a partial identifier, then try
            --  to find its corresponding Entity_Info

            --  Find the entity in E_Info and its children
            Decl_Entity := Get_Declaration_Entity
              (Buffer (Sloc_Start.Index .. Sloc_End.Index),
               Sloc_Start, File, Db, Lang);

            EInfo := null;

            if Decl_Entity /= null then
               Loc := Get_Declaration_Of (Decl_Entity);
               EInfo_Cursor := Xrefs.Find (Loc);

               if Entity_Info_Map.Has_Element (EInfo_Cursor) then
                  EInfo := Entity_Info_Map.Element (EInfo_Cursor);
               end if;
            end if;

            --  EInfo should now contain the Entity_Info corresponding to
            --  the entity declaration

            if EInfo /= null then
               --  The entity references an entity that we've analysed
               --  We generate a href to this entity declaration.
               Printout := Printout & Gen_Href
                 (Backend, EInfo,
                  Buffer (Sloc_Start.Index .. Sloc_End.Index));

            elsif EInfo = null
              and then Decl_Entity /= null
              and then Loc.File = File
              and then Loc.Line = Sloc_Start.Line
              and then Loc.Column =
                Basic_Types.Visible_Column_Type (Sloc_Start.Column)
            then
               --  the examined entity is a declaration entity
               Printout := Printout & Backend.Gen_Tag
                 (Identifier_Text,
                  Buffer (Sloc_Start.Index .. Sloc_End.Index));

            else
               --  No declaration associated with examined entity
               --  just generate simple text
               Printout := Printout & Backend.Gen_Tag
                 (Normal_Text,
                  Buffer (Sloc_Start.Index .. Sloc_End.Index));

            end if;
         end if;

         return False;
      exception
         when E : others =>
            Trace (Exception_Handle, E);
            return True;
      end CB;

   begin
      Parse_Entities (Lang, Iter, Buffer.all, CB'Unrestricted_Access);

      if At_End (Iter) then
         Append (Translation,
                 Tag_Name => "SOURCE_FILE",
                 Value    => Get_Filename (File).Base_Name);
         Append (Translation,
                 Tag_Name => "PRINTOUT",
                 Value    => To_String (Printout));
         Ada.Text_IO.Create
           (File_Handle,
            Name => Get_Doc_Directory (Kernel) & "src_" &
            Backend.To_Destination_Name
              (VFS.Base_Name (Get_Filename (File))));

         Trace (Me, "Generating file");
         Ada.Text_IO.Put
           (File_Handle, Parse (Tmpl, Translation, Cached => True));
         Ada.Text_IO.Close (File_Handle);
      end if;
   end Generate_Annotated_Source;

   ------------------
   -- Generate_Doc --
   ------------------

   procedure Generate_Doc
     (Kernel    : access Kernel_Handle_Record'Class;
      Backend   : Backend_Handle;
      Xrefs     : Entity_Info_Map.Map;
      Lang      : Language_Access;
      Db        : Entities_Database;
      File      : Source_File;
      Files     : in out Cross_Ref_List.Vector;
      E_Info    : Entity_Info)
   is
      Tmpl        : constant String :=
                      Backend.Get_Template
                        (Get_System_Dir (Kernel), Tmpl_Spec);
      Translation : Translate_Set;
      Pkg_Found   : Boolean;
      File_Handle : File_Type;

      function Get_Name (E : Entity_Info) return String;
      --  Get name from E, and formats it to reflect its attribute (abstract,
      --  generic)

      procedure Init_Common_Informations
        (E_Info   : Entity_Info;
         Tag_Name : String);

      procedure Format_Printout (E_Info : Entity_Info);
      --  Formats the printout to reflect language_entity types and
      --  cross-refs.

      --------------
      -- Get_Name --
      --------------

      function Get_Name (E : Entity_Info) return String is
         Str : Unbounded_String;
      begin
         Str := To_Unbounded_String (E.Name.all);
         if E.Is_Abstract then
            Str := Str & " (abstract)";
         end if;
         if E.Is_Private then
            Str := Str & " (private)";
         end if;
         if E.Is_Generic then
            Str := Str & " (generic)";
         end if;

         return To_String (Str);
      end Get_Name;

      ------------------------------
      -- Init_Common_Informations --
      ------------------------------

      procedure Init_Common_Informations
        (E_Info   : Entity_Info;
         Tag_Name : String)
      is
         Ref_Tag : Tag;
      begin
         Append (Translation, Tag_Name, Get_Name (E_Info));
         Format_Printout (E_Info);

         if E_Info.Printout /= null then
            Append (Translation, Tag_Name & "_PRINTOUT", E_Info.Printout.all);
         else
            Append (Translation, Tag_Name & "_PRINTOUT", "");
         end if;

         if E_Info.Description /= null then
            Append
              (Translation, Tag_Name & "_DESCRIPTION", E_Info.Description.all);
         else
            Append (Translation, Tag_Name & "_DESCRIPTION", "");
         end if;

         for J in E_Info.References.First_Index .. E_Info.References.Last_Index
         loop
            Ref_Tag := Ref_Tag &
              Location_Image (E_Info.References.Element (J));
         end loop;

         Append (Translation, Tag_Name & "_REFERENCES", Ref_Tag);

         Append (Translation, Tag_Name & "_LOC",
                 Location_Image (E_Info.Location.File_Loc));
         Append (Translation, Tag_Name & "_INSTANTIATION",
                 Gen_Href (Backend, E_Info.Instantiated_Entity));
         Append (Translation, Tag_Name & "_RENAMES",
                 Gen_Href (Backend, E_Info.Renamed_Entity));
         Append (Translation, Tag_Name & "_CAT", Image (E_Info.Lang_Category));
      end Init_Common_Informations;

      procedure Format_Printout (E_Info : Entity_Info) is
         Printout : Unbounded_String;
         Last_Idx : Natural := 0;

         function To_Global_Loc (Src : Source_Location) return Source_Location;
         function Extract (Idx_Start, Idx_End : Natural) return String;
         function CB
           (Entity         : Language_Entity;
            Sloc_Start     : Source_Location;
            Sloc_End       : Source_Location;
            Partial_Entity : Boolean) return Boolean;

         -------------------
         -- To_Global_Loc --
         -------------------

         function To_Global_Loc (Src : Source_Location) return Source_Location
         is
            Ret : Source_Location;
         begin
            Ret.Line := E_Info.Printout_Loc.Line + Src.Line - 1;

            if Src.Line = 1 then
               Ret.Column := E_Info.Printout_Loc.Column + Src.Column - 1;
            else
               Ret.Column := Src.Column;
            end if;

            Ret.Index := E_Info.Printout_Loc.Index + Src.Index -
              E_Info.Printout'First;

            return Ret;
         end To_Global_Loc;

         -------------
         -- Extract --
         -------------

         function Extract (Idx_Start, Idx_End : Natural) return String is
         begin
            return E_Info.Printout (Idx_Start .. Idx_End);
         end Extract;

         --------
         -- CB --
         --------

         function CB
           (Entity         : Language_Entity;
            Sloc_Start     : Source_Location;
            Sloc_End       : Source_Location;
            Partial_Entity : Boolean) return Boolean
         is
            pragma Unreferenced (Partial_Entity);
            Decl_Entity        : Entity_Information;
            EInfo_Cursor       : Entity_Info_Map.Cursor;
            EInfo              : Entity_Info;
            Start_Loc          : Source_Location;
            Loc                : File_Location;
            use Basic_Types;
         begin
            --  Print all text between previous call and current one
            if Last_Idx /= 0 then
               Printout := Printout &
                 Extract (Last_Idx + 1, Sloc_Start.Index - 1);
            end if;

            Last_Idx := Sloc_End.Index;

            if Entity /= Identifier_Text
              and then Entity /= Partial_Identifier_Text
            then
               --  For all entities that are not identifiers, print them
               --  directly
               Printout := Printout &
                 Backend.Gen_Tag
                   (Entity, Extract (Sloc_Start.Index, Sloc_End.Index));

            else
               --  If entity is an identifier or a partial identifier, then try
               --  to find its corresponding Entity_Info

               --  Find the entity in E_Info and its children
               Start_Loc := To_Global_Loc (Sloc_Start);

               if E_Info.Entity_Loc.Index = Start_Loc.Index
                 or else
                   (E_Info.Full_Declaration /= null
                    and then E_Info.Full_Declaration.Xref /= null
                    and then E_Info.Full_Declaration.Xref.Entity_Loc.Index =
                      Start_Loc.Index)
               then
                  --  Identifier of current entity.
                  Printout := Printout & Backend.Gen_Tag
                    (Entity, Extract (Sloc_Start.Index, Sloc_End.Index), True);

               else
                  Decl_Entity := Get_Declaration_Entity
                    (Extract (Sloc_Start.Index, Sloc_End.Index),
                     Start_Loc, File, Db, Lang);

                  EInfo := null;

                  if Decl_Entity /= null then
                     Loc := Get_Declaration_Of (Decl_Entity);
                     EInfo_Cursor := Xrefs.Find (Loc);

                     if Entity_Info_Map.Has_Element (EInfo_Cursor) then
                        EInfo := Entity_Info_Map.Element (EInfo_Cursor);
                     end if;
                  end if;

                  --  EInfo should now contain the Entity_Info corresponding to
                  --  the entity declaration

                  if EInfo /= null
                    and then EInfo.Location.File_Loc.File = File
                    and then EInfo.Location.File_Loc.Line = Start_Loc.Line
                    and then EInfo.Location.File_Loc.Column =
                      Basic_Types.Visible_Column_Type (Start_Loc.Column)
                  then
                     --  the examined entity is a declaration entity
                     Printout := Printout & Backend.Gen_Tag
                       (Identifier_Text,
                        Extract (Sloc_Start.Index, Sloc_End.Index));

                  elsif EInfo = null then
                     --  No declaration associated with examined entity
                     --  just generate simple text
                     Printout := Printout & Backend.Gen_Tag
                       (Normal_Text,
                        Extract (Sloc_Start.Index, Sloc_End.Index));

                  else
                     --  The entity references an entity that we've analysed
                     --  We generate a href to this entity declaration.
                     Printout := Printout & Gen_Href
                       (Backend, EInfo,
                        Extract (Sloc_Start.Index, Sloc_End.Index));
                  end if;
               end if;
            end if;

            return False;
         exception
            when E : others =>
               Trace (Exception_Handle, E);
               return True;
         end CB;

      begin
         if E_Info.Printout /= null then
            Parse_Entities (Lang, E_Info.Printout.all, CB'Unrestricted_Access);
            Free (E_Info.Printout);
            E_Info.Printout := new String'(To_String (Printout));
         end if;
      end Format_Printout;

      Cursor           : Entity_Info_List.Cursor;
      Child_EInfo      : Entity_Info;
      Displayed        : Boolean;

   begin
      Pkg_Found := False;

      Cursor := E_Info.Children.First;
      while Entity_Info_List.Has_Element (Cursor) loop
         Child_EInfo := Entity_Info_List.Element (Cursor);

         if Child_EInfo.Category = Cat_Package then
            --  Move file's description to main package's description
            if E_Info.Category = Cat_File
              and then E_Info.Description /= null
              and then Child_EInfo.Description = null
            then
               Child_EInfo.Description := E_Info.Description;
               E_Info.Description := null;
            end if;

            Init_Common_Informations (Child_EInfo, "PKG");
            Append (Translation, "PKG_FULL_LINK",
                    Gen_Href (Backend, Child_EInfo, "Full description"));

            if not Child_EInfo.Is_Renaming
              and then not Child_EInfo.Is_Instantiation
            then
               Pkg_Found := True;
               Generate_Doc
                 (Kernel, Backend, Xrefs, Lang, Db, File, Files, Child_EInfo);
            end if;
         end if;

         Entity_Info_List.Next (Cursor);
      end loop;

      if E_Info.Category = Cat_File then

         --  If one or more packages are defined there, then this means that
         --  the file's content has already been alalysed, just exit here.

         if Pkg_Found then
            --  If at least one package is found, this means that nothing
            --  more needs to be analysed on this file. Let's exit now then
            return;
         end if;

         --  Set main unit name
         Insert (Translation, Assoc ("SOURCE_FILE", Get_Name (E_Info)));

      elsif E_Info.Category = Cat_Package then

         Insert (Translation, Assoc ("PACKAGE_NAME", Get_Name (E_Info)));
      end if;

      --  UNIT HANDLING --

      --  Get current unit description
      if E_Info.Description /= null then
         Insert (Translation, Assoc ("DESCRIPTION", E_Info.Description.all));
      end if;

      --  Get current unit printout
      if E_Info.Printout /= null then
         Insert (Translation, Assoc ("PRINTOUT", E_Info.Printout.all));
      end if;

      --  Get the current unit generic parameters
      if E_Info.Is_Generic then
         declare
            Cursor            : Entity_Info_List.Cursor;
            Param             : Entity_Info;
            Param_Type        : Cross_Ref;
            Name_Str          : Ada.Strings.Unbounded.Unbounded_String;
         begin
            Cursor := Entity_Info_List.First (E_Info.Generic_Params);

            while Entity_Info_List.Has_Element (Cursor) loop
               Param := Entity_Info_List.Element (Cursor);
               Param_Type := Param.Parameter_Type;

               Name_Str := To_Unbounded_String
                 (Backend.Gen_Tag (Identifier_Text, Get_Name (Param)));

               if Param_Type /= null then
                  Name_Str := Name_Str & " (" &
                  Gen_Href (Backend, Param_Type) & ")";
               end if;

               Append
                 (Translation, "GENERIC_PARAMETERS", To_String (Name_Str));
               Append
                 (Translation, "GENERIC_PARAMETERS_LOC",
                  Location_Image (Param.Location.File_Loc));

               Entity_Info_List.Next (Cursor);
            end loop;
         end;
      end if;

      Cursor := E_Info.Children.First;

      while Entity_Info_List.Has_Element (Cursor) loop
         Child_EInfo := Entity_Info_List.Element (Cursor);

         Displayed := False;

         if Child_EInfo.Is_Partial
           and then Child_EInfo.Full_Declaration.Xref /= null
           and then not Child_EInfo.Full_Declaration.Xref.Displayed
         then
            Child_EInfo.Printout := Child_EInfo.Full_Declaration.Xref.Printout;
            Child_EInfo.Printout_Loc :=
              Child_EInfo.Full_Declaration.Xref.Printout_Loc;
            Child_EInfo.Full_Declaration.Xref.Displayed := True;

         elsif Child_EInfo.Displayed then
            Displayed := True;
         end if;

         if Displayed then
            null;

            --  CLASSES HANDLING --

         elsif Child_EInfo.Category = Cat_Class then

            declare
               Prim_Tag, Prim_Inh_Tag, Parent_Tag : Vector_Tag;
               Xref        : Cross_Ref;
               Prim_Op_Str : Ada.Strings.Unbounded.Unbounded_String;
            begin
               --  Init entities common information
               Init_Common_Informations (Child_EInfo, "CLASS");

               --  Init parents
               for J in Child_EInfo.Parents.First_Index ..
                 Child_EInfo.Parents.Last_Index
               loop
                  Xref := Child_EInfo.Parents.Element (J);
                  Parent_Tag := Parent_Tag & Gen_Href (Backend, Xref);
               end loop;

               Append (Translation, "CLASS_PARENTS", Parent_Tag);

               --  Init primitive operations
               Vector_Sort.Sort (Child_EInfo.Primitive_Ops);

               for J in Child_EInfo.Primitive_Ops.First_Index ..
                 Child_EInfo.Primitive_Ops.Last_Index
               loop
                  Xref := Child_EInfo.Primitive_Ops.Element (J);

                  Prim_Op_Str := To_Unbounded_String
                    (Gen_Href (Backend, Xref));

                  if Xref.Overriding_Op /= null
                    and then not Xref.Inherited
                  then
                     Prim_Op_Str := Prim_Op_Str & " (" &
                     Gen_Href (Backend, Xref.Overriding_Op, "overriding") &
                     ")";
                  end if;

                  if Xref.Inherited then
                     Prim_Inh_Tag := Prim_Inh_Tag & Prim_Op_Str;
                  else
                     Prim_Tag := Prim_Tag & Prim_Op_Str;
                  end if;
               end loop;

               Append (Translation, "CLASS_PRIMITIVES", Prim_Tag);
               Clear (Prim_Tag);
               Append
                 (Translation, "CLASS_PRIMITIVES_INHERITED", Prim_Inh_Tag);
               Clear (Prim_Inh_Tag);
            end;

            --  TASKS HANDLING --

         elsif Child_EInfo.Category = Cat_Task
           or else Child_EInfo.Category = Cat_Protected
         then

            --  Init entities common information
            declare
               Entry_Tag        : Vector_Tag;
               Entry_Cat_Tag    : Vector_Tag;
               Entry_Parent_Tag : Vector_Tag;
               Entry_P_Loc_Tag  : Vector_Tag;
               Entry_Loc_Tag    : Vector_Tag;
               Entry_Print_Tag  : Vector_Tag;
               Entry_Descr_Tag  : Vector_Tag;
               Entry_Cursor     : Entity_Info_List.Cursor;
               E_Entry          : Entity_Info;

            begin
               Init_Common_Informations (Child_EInfo, "TASK");
               Append (Translation, "TASK_TYPE", Image (Child_EInfo.Category));
               Append (Translation, "TASK_IS_TYPE", Child_EInfo.Is_Type);

               Entry_Cursor := Entity_Info_List.First (Child_EInfo.Children);

               while Entity_Info_List.Has_Element (Entry_Cursor) loop
                  E_Entry := Entity_Info_List.Element (Entry_Cursor);

                  Entry_Tag := Entry_Tag & E_Entry.Name.all;
                  Entry_Cat_Tag := Entry_Cat_Tag &
                  Image (E_Entry.Lang_Category);
                  Entry_Parent_Tag := Entry_Parent_Tag & Child_EInfo.Name.all;
                  Entry_P_Loc_Tag := Entry_P_Loc_Tag &
                  Location_Image (Child_EInfo.Location.File_Loc);
                  Entry_Loc_Tag := Entry_Loc_Tag &
                  Location_Image (E_Entry.Location.File_Loc);
                  Format_Printout (E_Entry);
                  Entry_Print_Tag := Entry_Print_Tag &
                  E_Entry.Printout.all;

                  if E_Entry.Description /= null then
                     Entry_Descr_Tag := Entry_Descr_Tag &
                     E_Entry.Description.all;
                  else
                     Entry_Descr_Tag := Entry_Descr_Tag & "";
                  end if;

                  Entity_Info_List.Next (Entry_Cursor);
               end loop;

               Append (Translation, "TASK_ENTRY", Entry_Tag);
               Append (Translation, "TASK_ENTRY_CAT", Entry_Cat_Tag);
               Append (Translation, "TASK_ENTRY_PARENT", Entry_Parent_Tag);
               Append (Translation, "TASK_ENTRY_PARENT_LOC", Entry_P_Loc_Tag);
               Append (Translation, "TASK_ENTRY_LOC", Entry_Loc_Tag);
               Append (Translation, "TASK_ENTRY_DESCRIPTION", Entry_Descr_Tag);
               Append (Translation, "TASK_ENTRY_PRINTOUT", Entry_Print_Tag);
            end;

            --  TYPES HANDLING --
         elsif Child_EInfo.Category = Cat_Type then

            --  Init entities common information
            Init_Common_Informations (Child_EInfo, "TYPE");

            --  CONSTANTS AND GLOBAL VARIABLES HANDLING --
         elsif Child_EInfo.Category = Cat_Variable then

            --  Init entities common information
            Init_Common_Informations (Child_EInfo, "CST");
            Append
              (Translation, "CST_TYPE",
               Gen_Href (Backend, Child_EInfo.Variable_Type));

            --  SUBPROGRAMS
         elsif Child_EInfo.Category = Cat_Subprogram then

            --  Init entities common information
            Init_Common_Informations (Child_EInfo, "SUBP");

            declare
               Param_Tag         : Tag;
               Param_Loc_Tag     : Tag;
               Param_Cursor      : Entity_Info_List.Cursor;
               Param             : Entity_Info;
               Param_Type        : Cross_Ref;
               Name_Str          : Ada.Strings.Unbounded.Unbounded_String;
            begin
               Param_Cursor := Entity_Info_List.First
                 (Child_EInfo.Generic_Params);

               while Entity_Info_List.Has_Element (Param_Cursor) loop
                  Param := Entity_Info_List.Element (Param_Cursor);
                  Param_Type := Param.Parameter_Type;

                  Name_Str := To_Unbounded_String
                    (Backend.Gen_Tag (Identifier_Text, Param.Name.all));

                  if Param_Type /= null then
                     Name_Str := Name_Str & " (" &
                     Gen_Href (Backend, Param_Type) & ")";
                  end if;

                  Param_Tag := Param_Tag & Name_Str;
                  Param_Loc_Tag := Param_Loc_Tag &
                  Location_Image (Param_Type.Location);

                  Entity_Info_List.Next (Param_Cursor);
               end loop;

               Append (Translation, "SUBP_GENERIC_PARAMETERS", Param_Tag);
               Append
                 (Translation, "SUBP_GENERIC_PARAMETERS_LOC", Param_Loc_Tag);
            end;
         end if;

         Entity_Info_List.Next (Cursor);
      end loop;

      if E_Info.Category = Cat_File then
         Append (Translation, "SOURCE",
                 "src_" & Backend.To_Destination_Name (E_Info.Name.all));
      else
         Append (Translation, "SOURCE",
                 "src_" & Backend.To_Destination_Name
                   (Get_Filename (E_Info.Location.File_Loc.File).Base_Name));
      end if;

      if E_Info.Category = Cat_File then
         Files.Append
           (new Cross_Ref_Record'
              (Location      => No_File_Location,
               Name          => new String'
                 (Backend.To_Destination_Name (E_Info.Name.all)),
               Xref          => E_Info,
               Inherited     => False,
               Overriding_Op => null));
         Ada.Text_IO.Create
           (File_Handle,
            Name => Get_Doc_Directory (Kernel) &
              Backend.To_Destination_Name (E_Info.Name.all));
      else
         --  Don't display inner packages in TOC.
         if E_Info.Location.Pkg_Nb = 1 then
            Files.Append
              (new Cross_Ref_Record'
                 (Location      => E_Info.Location.File_Loc,
                  Name          => new String'
                    (Backend.To_Destination_Name
                       (Get_Filename (E_Info.Location.File_Loc.File).Base_Name,
                        1)),
                  Xref          => E_Info,
                  Inherited     => False,
                  Overriding_Op => null));
         end if;

         Ada.Text_IO.Create
           (File_Handle,
            Name => Get_Doc_Directory (Kernel) &
              Backend.To_Destination_Name
                (VFS.Base_Name (Get_Filename (E_Info.Location.File_Loc.File)),
                 E_Info.Location.Pkg_Nb));
      end if;

      Ada.Text_IO.Put (File_Handle, Parse (Tmpl, Translation, Cached => True));
      Ada.Text_IO.Close (File_Handle);
   end Generate_Doc;

   --------------------
   -- Generate_Xrefs --
   --------------------

   procedure Generate_Xrefs
     (XRef_List : in out Cross_Ref_List.Vector;
      EInfo_Map : Entity_Info_Map.Map)
   is
      Xref_Cursor  : Cross_Ref_List.Cursor;
      Xref_Node    : Cross_Ref;
      EInfo_Cursor : Entity_Info_Map.Cursor;

   begin
      Xref_Cursor := XRef_List.First;

      while Cross_Ref_List.Has_Element (Xref_Cursor) loop
         Xref_Node := Cross_Ref_List.Element (Xref_Cursor);
         EInfo_Cursor := EInfo_Map.Find (Xref_Node.Location);

         if Entity_Info_Map.Has_Element (EInfo_Cursor) then
            --  We found the referenced node
            Xref_Node.Xref := Entity_Info_Map.Element (EInfo_Cursor);
         end if;

         Cross_Ref_List.Next (Xref_Cursor);
      end loop;
   end Generate_Xrefs;

   ------------------
   -- Generate_TOC --
   ------------------

   procedure Generate_TOC
     (Kernel     : access Kernel_Handle_Record'Class;
      Backend    : Backend_Handle;
      Files      : in out Cross_Ref_List.Vector)
   is
      Tmpl         : constant String :=
                      Backend.Get_Template
                        (Get_System_Dir (Kernel), Tmpl_TOC);
      Translation  : Translate_Set;
      File_Handle  : File_Type;
      Xref         : Cross_Ref;
      First_Letter : Character;
      Prev_Letter  : Character := ASCII.NUL;
   begin
      Vector_Sort.Sort (Files);

      for J in Files.First_Index .. Files.Last_Index loop
         Xref := Files.Element (J);
         First_Letter := To_Upper (Xref.Xref.Name (Xref.Xref.Name'First));

         if not Is_Letter (First_Letter) then
            First_Letter := '*';
         end if;

         Append (Translation, "LETTER", First_Letter);
         Append (Translation, "LETTER_CHANGED", First_Letter /= Prev_Letter);
         Prev_Letter := First_Letter;

         Append (Translation, "FILES",
                 Backend.Gen_Href
                   (Name  => Xref.Xref.Name.all,
                    Href  => Xref.Name.all,
                    Title => Location_Image (Xref.Location)));
      end loop;

      Ada.Text_IO.Create
        (File_Handle,
         Name =>  Get_Doc_Directory (Kernel) &
           Backend.To_Destination_Name ("index"));
      Ada.Text_IO.Put (File_Handle, Parse (Tmpl, Translation, Cached => True));
      Ada.Text_IO.Close (File_Handle);

      Open_Html
        (Kernel            => Kernel,
         URL_Or_File       => Get_Doc_Directory (Kernel) &
                                Backend.To_Destination_Name ("index"));
   end Generate_TOC;

   --------------------------
   -- Generate_Files_Index --
   --------------------------

   procedure Generate_Files_Index
     (Kernel     : access Kernel_Handle_Record'Class;
      Backend    : Backend_Handle;
      Src_Files  : Files_List.Vector)
   is
      Tmpl        : constant String :=
                      Backend.Get_Template
                        (Get_System_Dir (Kernel), Tmpl_Src_Index);
      File_Handle : File_Type;
      Translation : Translate_Set;
   begin
      for J in Src_Files.First_Index .. Src_Files.Last_Index loop
         Append
           (Translation, "SRC_FILE", Base_Name (Src_Files.Element (J)));
      end loop;

      Ada.Text_IO.Create
        (File_Handle,
         Name =>  Get_Doc_Directory (Kernel) &
           Backend.To_Destination_Name ("src_index"));
      Ada.Text_IO.Put (File_Handle, Parse (Tmpl, Translation, Cached => True));
      Ada.Text_IO.Close (File_Handle);
   end Generate_Files_Index;

   --------------------
   -- Generate_Trees --
   --------------------

   procedure Generate_Trees
     (Kernel     : access Kernel_Handle_Record'Class;
      Backend    : Backend_Handle;
      Class_List : in out Cross_Ref_List.Vector;
      EInfo_Map  : Entity_Info_Map.Map)
   is
      Tmpl        : constant String :=
                      Backend.Get_Template
                        (Get_System_Dir (Kernel), Tmpl_Class_Tree);
      Tmpl_Elem   : constant String :=
                      Backend.Get_Template
                        (Get_System_Dir (Kernel), Tmpl_Class_Tree_Elem);
      File_Handle : File_Type;
      Xref_Cursor : Cross_Ref_List.Cursor;
      EInfo       : Entity_Info;
      Map_Cursor  : Entity_Info_Map.Cursor;
      Xref        : Cross_Ref;
      Translation : Translate_Set;

      function Print_Tree
        (Name  : String;
         Class : Entity_Info;
         Depth : Natural) return String;
      --  Recursively print the class tree

      ----------------
      -- Print_Tree --
      ----------------

      function Print_Tree
        (Name  : String;
         Class : Entity_Info;
         Depth : Natural) return String
      is
         Cursor        : Cross_Ref_List.Cursor;
         Translation   : Translate_Set;
      begin
         if Class = null then
            return "";
         elsif Class.Category /= Cat_Class then
            return "";
         end if;

         Append (Translation, "TREE", Gen_Href (Backend, Class, Name));
         Append (Translation, "TREE_LOC",
                 Location_Image (Class.Location.File_Loc));
         Append (Translation, "ROOT_TREE", Depth = 0);

         Vector_Sort.Sort (Class.Class_Children);

         Cursor := Class.Class_Children.First;

         while Cross_Ref_List.Has_Element (Cursor) loop
            if Cross_Ref_List.Element (Cursor).Xref /= null
              and then not Cross_Ref_List.Element (Cursor).Xref.Displayed
            then
               declare
                  Child : constant String :=
                            Print_Tree
                              (Cross_Ref_List.Element (Cursor).Name.all,
                               Cross_Ref_List.Element (Cursor).Xref,
                               Depth + 1);
               begin
                  if Child /= "" then
                     Append (Translation, "TREE_CHILDREN", Child);
                  end if;
               end;
            end if;

            Cross_Ref_List.Next (Cursor);
         end loop;

         return Parse (Tmpl_Elem, Translation, Cached => True);
      end Print_Tree;

   begin
      Vector_Sort.Sort (Class_List);
      Xref_Cursor := Class_List.First;

      while Cross_Ref_List.Has_Element (Xref_Cursor) loop
         Xref := Cross_Ref_List.Element (Xref_Cursor);
         Map_Cursor := EInfo_Map.Find (Xref.Location);

         if Entity_Info_Map.Has_Element (Map_Cursor) then
            --  We found the referenced node
            EInfo := Entity_Info_Map.Element (Map_Cursor);

            --  Let's see if it has a parent
            if (EInfo.Parents.Is_Empty
                or else EInfo.Parents.First_Element.Xref = null)
              and then not EInfo.Displayed
            then
               Append (Translation, "TREE",
                       Print_Tree (Xref.Name.all, EInfo, 0));
            end if;
         end if;

         Cross_Ref_List.Next (Xref_Cursor);
      end loop;

      Ada.Text_IO.Create
        (File_Handle,
         Name => Get_Doc_Directory (Kernel) &
           Backend.To_Destination_Name ("tree"));
      Ada.Text_IO.Put (File_Handle, Parse (Tmpl, Translation, Cached => True));
      Ada.Text_IO.Close (File_Handle);
   end Generate_Trees;

   ---------------------------
   -- Generate_Global_Index --
   ---------------------------

   procedure Generate_Global_Index
     (Kernel     : access Kernel_Handle_Record'Class;
      Backend    : Backend_Handle;
      EInfo_Map  : Entity_Info_Map.Map)
   is
      Tmpl        : constant String :=
                      Backend.Get_Template
                        (Get_System_Dir (Kernel), Tmpl_Index);
      Letter       : Character;
      Map_Cursor   : Entity_Info_Map.Cursor;
      EInfo        : Entity_Info;
      List_Index   : Natural;
      Translation  : Translate_Set;
      Href_Tag     : Tag;
      Loc_Tag      : Tag;
      Kind_Tag     : Tag;

      File_Handle  : File_Type;
      Local_List   : array (1 .. 27) of Entity_Info_List.Vector;

   begin
      Map_Cursor := EInfo_Map.First;

      while Entity_Info_Map.Has_Element (Map_Cursor) loop
         EInfo := Entity_Info_Map.Element (Map_Cursor);

         if EInfo.Category /= Cat_Parameter then
            Letter := To_Upper (EInfo.Short_Name (EInfo.Short_Name'First));

            if not Is_Letter (Letter) then
               List_Index := 1;
            else
               List_Index := 2 +
                 Character'Pos (Letter) - Character'Pos ('A');
            end if;

            Local_List (List_Index).Append (EInfo);
         end if;

         Entity_Info_Map.Next (Map_Cursor);
      end loop;

      for J in Local_List'Range loop
         EInfo_Vector_Sort.Sort (Local_List (J));
         Clear (Href_Tag);
         Clear (Loc_Tag);
         Clear (Kind_Tag);

         for K in Local_List (J).First_Index .. Local_List (J).Last_Index loop
            EInfo := Local_List (J).Element (K);
            Href_Tag := Href_Tag &
              Gen_Href (Backend, EInfo, EInfo.Short_Name.all);
            Loc_Tag := Loc_Tag & Location_Image (EInfo.Location.File_Loc);
            Kind_Tag := Kind_Tag & Image (EInfo.Category);
         end loop;

         Insert (Translation, Assoc ("ENTITY_HREF", Href_Tag));
         Insert (Translation, Assoc ("ENTITY_LOC", Loc_Tag));
         Insert (Translation, Assoc ("ENTITY_KIND", Kind_Tag));

         if J = 1 then
            Letter := '*';
         else
            Letter := Character'Val (J - 2 + Character'Pos ('A'));
         end if;

         Insert (Translation, Assoc ("LETTER", +Letter));

         if Letter = '*' then
            Ada.Text_IO.Create
              (File_Handle,
               Name => Get_Doc_Directory (Kernel) &
                 Backend.To_Destination_Name ("entities"));
         else
            Ada.Text_IO.Create
              (File_Handle,
               Name => Get_Doc_Directory (Kernel) &
                 Backend.To_Destination_Name ("entities" & Letter));
         end if;

         Ada.Text_IO.Put
           (File_Handle, Parse (Tmpl, Translation, Cached => True));
         Ada.Text_IO.Close (File_Handle);
      end loop;
   end Generate_Global_Index;

   ----------------------------
   -- Generate_Support_Files --
   ----------------------------

   procedure Generate_Support_Files
     (Kernel : access Kernel_Handle_Record'Class;
      Backend : Backend_Handle)
   is
      Src_Dir : constant VFS.Virtual_File :=
                  Create (Backend.Get_Support_Dir (Get_System_Dir (Kernel)));
      Dst_Dir : constant String :=
                  Get_Doc_Directory (Kernel);
      Dead    : Boolean;
   begin
      Src_Dir.Copy (Dst_Dir & Base_Dir_Name (Src_Dir), Dead);
   end Generate_Support_Files;

   -----------------------
   -- Get_Doc_Directory --
   -----------------------

   function Get_Doc_Directory
     (Kernel : not null access Kernel_Handle_Record'Class) return String is
   begin
      return File_Utils.Name_As_Directory
        (Object_Path
           (Get_Root_Project (Get_Registry (Kernel).all),
            False)) & "doc/";
   end Get_Doc_Directory;

end Docgen2;
