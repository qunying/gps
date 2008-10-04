"""This file provides default data to the GPS Build Manager"""

import GPS, sys, os.path
from GPS import *

# This contains a list of project-specific targets
project_targets = []

# This is an XML model for all GNAT builders (gnatmake, gprbuild, gprmake)
Builder_Model_Template = """
<target-model name="builder" category="">
   <description>Generic GNAT builder</description>
   <command-line>
      <arg>%builder</arg>
      <arg>-d</arg>
      <arg>%eL</arg>
      <arg>-P%PP</arg>
      <arg>%X</arg>
   </command-line>
   <icon>gtk-media-play</icon>
   <switches command="%(tool_name)s" columns="2" lines="2">
     <title column="1" line="1" >Dependencies</title>
     <title column="2" line="1" >Compilation</title>
     <check label="Recompile if switches changed" switch="-s"
            tip="Recompile if compiler switches have changed since last compilation" />
     <spin label="Multiprocessing" switch="-j" min="1" max="100" default="1"
           column="2"
           tip="Use N processes to carry out the compilations. On a multiprocessor machine compilations will occur in parallel" />
     <check label="Progress bar" switch="-d" column="2"
            tip="Display a progress bar with information about how many files are left to be compiled" />
     <check label="Keep going" switch="-k" column="2"
            tip="Continue as much as possible after a compilation error" />
   </switches>
</target-model>
"""

# This is an XML model for gnatmake
Gnatmake_Model_Template = """
<target-model name="gnatmake" category="">
   <description>Build with gnatmake</description>
   <command-line>
      <arg>%gnatmake</arg>
      <arg>-d</arg>
      <arg>%eL</arg>
      <arg>-P%PP</arg>
      <arg>%X</arg>
   </command-line>
   <icon>gtk-media-play</icon>
   <switches command="%(tool_name)s" columns="2" lines="2">
     <title column="1" line="1" >Dependencies</title>
     <title column="1" line="2" >Checks</title>
     <title column="2" line="1" >Compilation</title>
     <check label="Recompile if switches changed" switch="-s"
            tip="Recompile if compiler switches have changed since last compilation" />
     <check label="Minimal recompilation" switch="-m"
            tip="Specifies that the minimum necessary amount of recompilation be performed. In this mode, gnatmake ignores time stamp differences when the only modification to a source file consist in adding or removing comments, empty lines, spaces or tabs" />
     <spin label="Multiprocessing" switch="-j" min="1" max="100" default="1"
           column="2"
           tip="Use N processes to carry out the compilations. On a multiprocessor machine compilations will occur in parallel" />
     <check label="Progress bar" switch="-d" column="2"
            tip="Display a progress bar with information about how many files are left to be compiled" />
     <check label="Keep going" switch="-k" column="2"
            tip="Continue as much as possible after a compilation error" />
     <check label="Debug information" switch="-g" column="2"
            tip="Add debugging information. This forces the corresponding switch for the compiler, binder and linker" />
     <check label="Syntax check" switch="-gnats" line="2"
            tip="Perform syntax check, no compilation occurs" />
     <check label="Semantic check" switch="-gnatc" line="2"
            tip="Perform syntax and semantic check only, no compilation occurs" />
   </switches>
</target-model>
"""

# This is an XML model for gnatclean/gprclean
Gprclean_Model_Template = """
<target-model name="gprclean" category="">
   <description>Clean compilation artefacts with gnatclean/gprclean</description>
   <command-line>
      <arg>%gprclean</arg>
      <arg>%eL</arg>
      <arg>-P%PP</arg>
      <arg>%X</arg>
   </command-line>
   <icon>gtk-media-play</icon>
   <switches command="%(tool_name)s" columns="1">
     <check label="Only delete compiler generated files" switch="-c"
            tip="Remove only the files generated by the compiler, ot other files" />
     <check label="Force deletion" switch="-f"
            tip="Force deletions of unwritable files" />
     <check label="Clean recursively" switch="-r"
            tip="Clean all projects recursively" />
   </switches>
</target-model>
"""

# This is a minimal XML model, used for launching custom commands
Custom_Model_Template = """
<target-model name="custom" category="">
   <description>Launch a custom build command</description>
   <icon>gtk-execute</icon>
   <switches command="">
   </switches>
</target-model>
"""

# This is an empty target using the Custom model

Custom_Target = """
<target model="custom" category="Project" name="Custom...">
    <in-toolbar>FALSE</in-toolbar>
    <icon>gtk-execute</icon>
    <launch-mode>MANUALLY</launch-mode>
    <read-only>TRUE</read-only>
    <command-line />
    <key>F9</key>
</target>
"""

# Targets to compile all project files using the builder model
Compile_All_Targets = """
<target model="builder" category="Project" name="_Build All">
    <in-toolbar>TRUE</in-toolbar>
    <icon>gtk-media-play</icon>
    <launch-mode>MANUALLY</launch-mode>
    <read-only>TRUE</read-only>
    <default-command-line>
       <arg>%builder</arg>
       <arg>-d</arg>
       <arg>%eL</arg>
       <arg>-P%PP</arg>
       <arg>%X</arg>
    </default-command-line>
</target>
<target model="builder" category="Project" name="_Compile All">
    <in-toolbar>TRUE</in-toolbar>
    <icon>gtk-media-play</icon>
    <launch-mode>MANUALLY</launch-mode>
    <read-only>TRUE</read-only>
    <default-command-line>
       <arg>%builder</arg>
       <arg>-c</arg>
       <arg>-U</arg>
       <arg>-d</arg>
       <arg>%eL</arg>
       <arg>-P%PP</arg>
       <arg>%X</arg>
    </default-command-line>
</target>
<target model="builder" category="Project" name="Compile _Root">
    <in-toolbar>TRUE</in-toolbar>
    <icon>gtk-media-play</icon>
    <launch-mode>MANUALLY</launch-mode>
    <read-only>TRUE</read-only>
    <default-command-line>
       <arg>%builder</arg>
       <arg>-c</arg>
       <arg>-u</arg>
       <arg>-d</arg>
       <arg>%eL</arg>
       <arg>-P%PP</arg>
       <arg>%X</arg>
    </default-command-line>
</target>
"""

# This is a target to compile the current file using the builder model
Compile_File_Target = """
<target model="builder" category="_File_" name="_Compile File">
    <in-toolbar>TRUE</in-toolbar>
    <icon>gtk-media-play</icon>
    <launch-mode>MANUALLY</launch-mode>
    <read-only>TRUE</read-only>
    <default-command-line>
       <arg>%builder</arg>
       <arg>-ws</arg>
       <arg>-c</arg>
       <arg>-u</arg>
       <arg>%eL</arg>
       <arg>-P%PP</arg>
       <arg>%X</arg>
       <arg>%F</arg>
    </default-command-line>
    <key>shift-F4</key>
</target>
"""

Syntax_Check_Target = """
<target model="gnatmake" category="_File_" name="Check _Syntax">
    <in-toolbar>TRUE</in-toolbar>
    <icon>gtk-media-play</icon>
    <launch-mode>MANUALLY</launch-mode>
    <read-only>TRUE</read-only>
    <default-command-line>
       <arg>%gnatmake</arg>
       <arg>-q</arg>
       <arg>-gnats</arg>
       <arg>-u</arg>
       <arg>%eL</arg>
       <arg>-P%PP</arg>
       <arg>%X</arg>
       <arg>%F</arg>
    </default-command-line>
</target>
"""

Semantic_Check_Target = """
<target model="gnatmake" category="_File_" name="Check S_emantic">
    <in-toolbar>TRUE</in-toolbar>
    <icon>gtk-media-play</icon>
    <launch-mode>MANUALLY</launch-mode>
    <read-only>TRUE</read-only>
    <default-command-line>
       <arg>%gnatmake</arg>
       <arg>-q</arg>
       <arg>-gnatc</arg>
       <arg>-u</arg>
       <arg>%eL</arg>
       <arg>-P%PP</arg>
       <arg>%X</arg>
       <arg>%F</arg>
    </default-command-line>
</target>
"""

# Targets to clear the current project using the gprclean model
Clean_Targets = """
<target model="gprclean" category="Project" name="Clean Root">
    <in-toolbar>FALSE</in-toolbar>
    <icon>gtk-clear</icon>
    <launch-mode>MANUALLY</launch-mode>
    <read-only>TRUE</read-only>
    <default-command-line>
       <arg>%gprclean</arg>
       <arg></arg>
       <arg>%eL</arg>
       <arg>-P%PP</arg>
       <arg>%X</arg>
    </default-command-line>
</target>
<target model="gprclean" category="Project" name="Clean All">
    <in-toolbar>FALSE</in-toolbar>
    <icon>gtk-clear</icon>
    <launch-mode>MANUALLY</launch-mode>
    <read-only>TRUE</read-only>
    <default-command-line>
       <arg>%gprclean</arg>
       <arg>-r</arg>
       <arg>%eL</arg>
       <arg>-P%PP</arg>
       <arg>%X</arg>
    </default-command-line>
</target>
"""

def create_project_targets():
    """ Register targets for building the main files of the project
    """
    # ??? to be implemented

def remove_project_targets():
    """ Unregister project-specific targets
    """
    # ??? to be implemented (need an API to remove targets)

def create_global_targets():
    """ Register global targets, ie targets which are the same in all projects
    """
    parse_xml (Syntax_Check_Target)
    parse_xml (Semantic_Check_Target)
    parse_xml (Compile_File_Target)
    parse_xml (Compile_All_Targets)
    parse_xml (Clean_Targets)
    parse_xml (Custom_Target)

def register_models():
    """ Register the models for building using standard tools
    """
    parse_xml (Builder_Model_Template)
    parse_xml (Gnatmake_Model_Template)
    parse_xml (Gprclean_Model_Template)
    parse_xml (Custom_Model_Template)

def on_project_recomputed (hook_name):
    """ Add the project-specific targets to the Build Manager """
    remove_project_targets()
    create_project_targets()

def on_gps_started (hook_name):
    """ Add the project-specific targets to the Build Manager """

    # Register the models
    register_models()

    # Create the global targets
    create_global_targets()

    GPS.Hook ("project_view_changed").add (on_project_recomputed)


GPS.Hook ("gps_started").add (on_gps_started)
