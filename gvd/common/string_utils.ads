-----------------------------------------------------------------------
--                   GVD - The GNU Visual Debugger                   --
--                                                                   --
--                      Copyright (C) 2000-2001                      --
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

--  This package provides a set of subprograms for manipulating and parsing
--  strings.

with GNAT.Directory_Operations;

package String_Utils is

   procedure Skip_Blanks
     (Type_Str : String;
      Index    : in out Natural;
      Step     : Integer := 1);
   --  Skip all the blank characters starting from Index.
   --  Index is modified to point to the first non-blank character.
   --  Step should be either 1 or -1, depending on whether you want to search
   --  forward or backward.

   procedure Skip_To_Blank
     (Type_Str : String;
      Index    : in out Natural);
   --  Skip to the next blank character

   procedure Skip_Hexa_Digit
     (Type_Str : String;
      Index    : in out Natural);
   --  Move Index to the first character that can not be part of an hexadecimal
   --  digit. Note that an hexadecimal digit can optionally start with '0x',
   --  which is the only case where x is recognized as part of the digit.

   procedure Skip_To_Char
     (Type_Str : String;
      Index    : in out Natural;
      Char     : Character;
      Step     : Integer := 1);
   --  Skip every character up to the first occurence of Char in the string.

   procedure Skip_To_String
     (Type_Str  : String;
      Index     : in out Natural;
      Substring : String);
   --  Skip every character until an occurence of Substring is found.
   --  Index is set to the first character of the occurence.

   procedure Skip_Word
     (Type_Str : String;
      Index    : in out Natural;
      Step     : Integer := 1);
   --  Skip the word starting at Index (at least one character, even if there
   --  is no word).
   --  Currently, a word is defined as any string made of alphanumeric
   --  character or underscore.

   procedure Parse_Num
     (Type_Str : String;
      Index    : in out Natural;
      Result   : out Long_Integer);
   --  Parse the integer found at position Index in Type_Str.
   --  Index is set to the position of the first character that does not
   --  belong to the integer.

   function Looking_At
     (Type_Str  : String;
      Index     : Natural;
      Substring : String) return Boolean;
   --  Return True if the characters starting at Index in Type_Str are
   --  equivalent to Substring.

   procedure Parse_Cst_String
     (Type_Str : String;
      Index    : in out Natural;
      Str      : out String;
      Backslash_Special : Boolean := True);
   --  Parse the string pointed to by Index, and copy the result in Str.
   --  Index must point to the opening " character, and will be set to
   --  point after the closing " character.
   --  Special characters, as output by gdb (["0a"]) are also interpreted
   --  and converted to the equivalent Character value.
   --  Str must be long enough to contain the string, not check is done. As a
   --  special case, if Str'Length = 0 then no attempt is done to fill up
   --  the string, and only Length is computed.
   --
   --  Index is set to the number of characters parsed in the string.

   procedure Skip_Simple_Value
     (Type_Str             : in String;
      Index                : in out Natural;
      Array_Item_Separator : in Character := ',';
      End_Of_Array         : in Character := ')';
      Repeat_Item_Start    : in Character := '<');
   --  Skip the value of a simple value ("65 'A'" for instance).
   --  This stops at the first special character.
   --
   --  Array_Item_Separator is the separator in an array value (ie "5, 2, 3").
   --  End_Of_Array is the array that indicates the end of an array value, as
   --  in "((1, 2), (3, 4))".
   --  Repeat_Item_Start if the character that starts a repeat statements, as
   --  in "<repeats .. times>"

   function Reduce (S : String) return String;
   --  Replace in string S all ASCII.LF and ASCII.HT characters with a space,
   --  and replace multiple spaces with a single one.
   --  Return the resulting string.

   function Strip_CR (Text : String) return String;
   --  Return a version of Text after stripping all the CR from the string.
   --  This function is used on Windows or when the Strip_CR preference is
   --  enabled (for systems that share dos files).

   function Do_Tab_Expansion
     (Text : String; Tab_Size : Integer) return String;
   --  Return a version of Text after all tabs have been correctly expanded
   --  depending on the value of Tab_Size.
   --  This function works correctly with multiple-line strings.

   procedure Mixed_Case (S : in out String);
   --  Return S with a casing matching Ada style: upper case after an
   --  underscore or a dot.

   procedure Lower_Case (S : in out String);
   --  Return S with all characters lowered.

   function Strip_Quotes (S : in String) return String;
   --  Remove the quotes and the spaces at the beginning and end of S.

   function Image (N : Integer) return String;
   --  Create a string image of the given Integer.

   function Image (N : Integer; Length : Positive) return String;
   --  Create a string image of the given Integer.
   --  The returned string is padded with leading spaces to create a string of
   --  at least length characters.

   function Number_Of_Digits (N : Integer) return Natural;
   --  Return the number of digits for the given Integer number;

   ----------------------------
   -- File name manipulation --
   ----------------------------

   function Base_File_Name (File_Name : String) return String;
   --  Return the base name of File_Name (ie without any directory indication)
   --  This function is now obsolete, and you should use
   --  GNAT.Directories.Base_Name instead. it is kept for compatibility
   --  with 3.14p only.

   function File_Extension (File_Name : String) return String;
   --  Return the extension of the file (ie the part after the last '.'),
   --  or "" if there is none.
   --  This function is now obsolete, and you should use
   --  GNAT.Directories.File_Extension instead. it is kept for compatibility
   --  with 3.14p only.

   function Name_As_Directory
     (Name  : String;
      Style : GNAT.Directory_Operations.Path_Style :=
        GNAT.Directory_Operations.System_Default) return String;
   --  Add a directory separator at the end of Name if there is none.
   --  This also normalizes the pathname (see
   --  GNAT.Directory_Operations.Normalize_Pathname).
   --  ??? Should go into GNAT.Directory_Operations

   function Suffix_Matches
     (File_Name : String; Suffix : String) return Boolean;
   --  Return true if File_Name has the given Suffix. This is more general
   --  than extensions, since it doesn't need to start after a '.'.
   --  Note that this function also return False when Filename = Extension
   --  as this does not make sense for a source filename.

   function To_Unix_Pathname (Path : String) return String;
   --  Convert all occurences of Directory_Separator to '/'.
   --  If Directory_Separator is different than '/', the following
   --  additional substitutions are operated:
   --  /cydrive/x/ -> x:\
   --  //x/        -> x:\
   --  where x is an arbitrary character

   function To_Host_Pathname (Path : String) return String;
   --  Convert all occurences of '/' to Directory_Separator.
   --  This function is now obsolete, and you should use
   --  GNAT.Directories.Normalize_Pathname instead. it is kept for
   --  compatibility with 3.14 only.

   function To_File_Name (Name : in String) return String;
   --  Returns a file name from an ada subprogram/package name (ie converts '.'
   --  and '-' to the appropriate characters).
   --  ??? Note: this should be modified to use the naming schemes, if needed.

private
   pragma Inline (Looking_At);
   pragma Inline (Skip_Blanks);
   pragma Inline (Skip_To_Char);
end String_Utils;
