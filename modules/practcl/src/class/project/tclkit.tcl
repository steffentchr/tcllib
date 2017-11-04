

::oo::class create ::practcl::tclkit {
  superclass ::practcl::library

  method build-tclkit_main {PROJECT PKG_OBJS} {
    ###
    # Build static package list
    ###
    set statpkglist {}
    foreach cobj [list {*}${PKG_OBJS} $PROJECT] {
      foreach {pkg info} [$cobj project-static-packages] {
        dict set statpkglist $pkg $info
      }
    }
    foreach {ofile info} [${PROJECT} project-compile-products] {
      if {![dict exists $info object]} continue
      set cobj [dict get $info object]
      foreach {pkg info} [$cobj project-static-packages] {
        dict set statpkglist $pkg $info
      }
    }

    set result {}
    $PROJECT include {<tcl.h>}
    $PROJECT include {"tclInt.h"}
    $PROJECT include {"tclFileSystem.h"}
    $PROJECT include {<assert.h>}
    $PROJECT include {<stdio.h>}
    $PROJECT include {<stdlib.h>}
    $PROJECT include {<string.h>}
    $PROJECT include {<math.h>}

    $PROJECT code header {
#ifndef MODULE_SCOPE
#   define MODULE_SCOPE extern
#endif

/*
** Provide a dummy Tcl_InitStubs if we are using this as a static
** library.
*/
#ifndef USE_TCL_STUBS
# undef  Tcl_InitStubs
# define Tcl_InitStubs(a,b,c) TCL_VERSION
#endif
#define STATIC_BUILD 1
#undef USE_TCL_STUBS

/* Make sure the stubbed variants of those are never used. */
#undef Tcl_ObjSetVar2
#undef Tcl_NewStringObj
#undef Tk_Init
#undef Tk_MainEx
#undef Tk_SafeInit
}

    # Build an area of the file for #define directives and
    # function declarations
    set define {}
    set mainhook   [$PROJECT define get TCL_LOCAL_MAIN_HOOK Tclkit_MainHook]
    set mainfunc   [$PROJECT define get TCL_LOCAL_APPINIT Tclkit_AppInit]
    set mainscript [$PROJECT define get main.tcl main.tcl]
    set vfsroot    [$PROJECT define get vfsroot "[$PROJECT define get ZIPFS_VOLUME]app"]
    set vfs_main "${vfsroot}/${mainscript}"
    set vfs_tcl_library "${vfsroot}/boot/tcl"
    set vfs_tk_library "${vfsroot}/boot/tk"

    set map {}
    foreach var {
      vfsroot mainhook mainfunc vfs_main vfs_tcl_library vfs_tk_library
    } {
      dict set map %${var}% [set $var]
    }
    set preinitscript {
set ::odie(boot_vfs) {%vfsroot%}
set ::SRCDIR {%vfsroot%}
if {[file exists {%vfs_tcl_library%}]} {
  set ::tcl_library {%vfs_tcl_library%}
  set ::auto_path {}
}
if {[file exists {%vfs_tk_library%}]} {
  set ::tk_library {%vfs_tk_library%}
}
} ; # Preinitscript

    set zvfsboot {
/*
 * %mainhook% --
 * Performs the argument munging for the shell
 */
  }
    ::practcl::cputs zvfsboot {
  CONST char *archive;
  Tcl_FindExecutable(*argv[0]);
  archive=Tcl_GetNameOfExecutable();
}
    # We have to initialize the virtual filesystem before calling
    # Tcl_Init().  Otherwise, Tcl_Init() will not be able to find
    # its startup script files.
    if {[$PROJECT define get tip_430 0]} {
      ::practcl::cputs zvfsboot "  if(!TclZipfs_Mount(NULL, archive, \"%vfsroot%\", NULL)) \x7B "
    } else {
      ::practcl::cputs zvfsboot {  Odie_Zipfs_C_Init(NULL);}
      ::practcl::cputs zvfsboot "  if(!Odie_Zipfs_Mount(NULL, archive, \"%vfsroot%\", NULL)) \x7B "
    }
    ::practcl::cputs zvfsboot {
      Tcl_Obj *vfsinitscript;
      vfsinitscript=Tcl_NewStringObj("%vfs_main%",-1);
      Tcl_IncrRefCount(vfsinitscript);
      if(Tcl_FSAccess(vfsinitscript,F_OK)==0) {
        /* Startup script should be set before calling Tcl_AppInit */
        Tcl_SetStartupScript(vfsinitscript,NULL);
      }
    }
    ::practcl::cputs zvfsboot "    TclSetPreInitScript([::practcl::tcl_to_c $preinitscript])\;"
    ::practcl::cputs zvfsboot "  \x7D else \x7B"
    ::practcl::cputs zvfsboot "    TclSetPreInitScript([::practcl::tcl_to_c {
foreach path {../tcl} {
  set p  [file join $path library init.tcl]
  if {[file exists [file join $path library init.tcl]]} {
    set ::tcl_library [file normalize [file join $path library]]
    break
  }
}
foreach path {
  ../tk
} {
  if {[file exists [file join $path library tk.tcl]]} {
    set ::tk_library [file normalize [file join $path library]]
    break
  }
}
}])\;"
    ::practcl::cputs zvfsboot "  \x7D"
    ::practcl::cputs zvfsboot "  return TCL_OK;"

    if {[$PROJECT define get TEACUP_OS] eq "windows"} {
      set header {int %mainhook%(int *argc, TCHAR ***argv)}
    } else {
      set header {int %mainhook%(int *argc, char ***argv)}
    }
    $PROJECT c_function  [string map $map $header] [string map $map $zvfsboot]

    practcl::cputs appinit "int %mainfunc%(Tcl_Interp *interp) \x7B"

  # Build AppInit()
  set appinit {}
  practcl::cputs appinit {
  if ((Tcl_Init)(interp) == TCL_ERROR) {
      return TCL_ERROR;
  }
}
    set main_init_script {}

    foreach {statpkg info} $statpkglist {
      set initfunc {}
      if {[dict exists $info initfunc]} {
        set initfunc [dict get $info initfunc]
      }
      if {$initfunc eq {}} {
        set initfunc [string totitle ${statpkg}]_Init
      }
      if {![dict exists $info version]} {
        error "$statpkg HAS NO VERSION"
      }
      # We employ a NULL to prevent the package system from thinking the
      # package is actually loaded into the interpreter
      $PROJECT code header "extern Tcl_PackageInitProc $initfunc\;\n"
      set script [list package ifneeded $statpkg [dict get $info version] [list ::load {} $statpkg]]
      append main_init_script \n [list set ::kitpkg(${statpkg}) $script]
      if {[dict get $info autoload]} {
        ::practcl::cputs appinit "  if(${initfunc}(interp)) return TCL_ERROR\;"
        ::practcl::cputs appinit "  Tcl_StaticPackage(interp,\"$statpkg\",$initfunc,NULL)\;"
      } else {
        ::practcl::cputs appinit "\n  Tcl_StaticPackage(NULL,\"$statpkg\",$initfunc,NULL)\;"
        append main_init_script \n $script
      }
    }
    append main_init_script \n {
if {[file exists [file join $::SRCDIR packages.tcl]]} {
  #In a wrapped exe, we don't go out to the environment
  set dir $::SRCDIR
  source [file join $::SRCDIR packages.tcl]
}
# Specify a user-specific startup file to invoke if the application
# is run interactively.  Typically the startup file is "~/.apprc"
# where "app" is the name of the application.  If this line is deleted
# then no user-specific startup file will be run under any conditions.
}
    append main_init_script \n [list set tcl_rcFileName [$PROJECT define get tcl_rcFileName ~/.tclshrc]]
    practcl::cputs appinit "  Tcl_Eval(interp,[::practcl::tcl_to_c  $main_init_script]);"
    practcl::cputs appinit {  return TCL_OK;}
    $PROJECT c_function [string map $map "int %mainfunc%(Tcl_Interp *interp)"] [string map $map $appinit]
  }

  method Collate_Source CWD {
    next $CWD
    set name [my define get name]
    # Assume a static shell
    if {[my define exists SHARED_BUILD]} {
      my define set SHARED_BUILD 0
    }
    if {![my define exists TCL_LOCAL_APPINIT]} {
      my define set TCL_LOCAL_APPINIT Tclkit_AppInit
    }
    if {![my define exists TCL_LOCAL_MAIN_HOOK]} {
      my define set TCL_LOCAL_MAIN_HOOK Tclkit_MainHook
    }
    set PROJECT [self]
    set os [$PROJECT define get TEACUP_OS]
    if {[my define get SHARED_BUILD]} {
      puts [list BUILDING TCLSH FOR OS $os]
    } else {
      puts [list BUILDING KIT FOR OS $os]
    }
    set TCLOBJ [$PROJECT tclcore]
    ::practcl::toolset select $TCLOBJ

    set TCLSRCDIR [$TCLOBJ define get srcdir]
    set PKG_OBJS {}
    foreach item [$PROJECT link list core.library] {
      if {[string is true [$item define get static]]} {
        lappend PKG_OBJS $item
      }
    }
    foreach item [$PROJECT link list package] {
      if {[string is true [$item define get static]]} {
        lappend PKG_OBJS $item
      }
    }
    # Arrange to build an main.c that utilizes TCL_LOCAL_APPINIT and TCL_LOCAL_MAIN_HOOK
    if {$os eq "windows"} {
      set PLATFORM_SRC_DIR win
      if {[my define get SHARED_BUILD]} {
        my add class csource filename [file join $TCLSRCDIR win tclWinReg.c] initfunc Registry_Init pkg_name registry pkg_vers 1.3.1 autoload 1
        my add class csource filename [file join $TCLSRCDIR win tclWinDde.c] initfunc Dde_Init pkg_name dde pkg_vers 1.4.0 autoload 1
      }
      my add class csource ofile [my define get name]_appinit.o filename [file join $TCLSRCDIR win tclAppInit.c] extra [list -DTCL_LOCAL_MAIN_HOOK=[my define get TCL_LOCAL_MAIN_HOOK Tclkit_MainHook] -DTCL_LOCAL_APPINIT=[my define get TCL_LOCAL_APPINIT Tclkit_AppInit]]
    } else {
      set PLATFORM_SRC_DIR unix
      my add class csource ofile [my define get name]_appinit.o filename [file join $TCLSRCDIR unix tclAppInit.c] extra [list -DTCL_LOCAL_MAIN_HOOK=[my define get TCL_LOCAL_MAIN_HOOK Tclkit_MainHook] -DTCL_LOCAL_APPINIT=[my define get TCL_LOCAL_APPINIT Tclkit_AppInit]]
    }

    if {[my define get SHARED_BUILD]} {
      ###
      # Add local static Zlib implementation
      ###
      set cdir [file join $TCLSRCDIR compat zlib]
      foreach file {
        adler32.c compress.c crc32.c
        deflate.c infback.c inffast.c
        inflate.c inftrees.c trees.c
        uncompr.c zutil.c
      } {
        my add [file join $cdir $file]
      }
    }
    ###
    # Pre 8.7, Tcl doesn't include a Zipfs implementation
    # in the core. Grab the one from odielib
    ###
    set zipfs [file join $TCLSRCDIR generic tclZipfs.c]
    if {![$PROJECT define exists ZIPFS_VOLUME]} {
      $PROJECT define set ZIPFS_VOLUME "zipfs:/"
    }
    $PROJECT code header "#define ZIPFS_VOLUME \"[$PROJECT define get ZIPFS_VOLUME]\""
    if {[file exists $zipfs]} {
      $TCLOBJ define set tip_430 1
      my define set tip_430 1
    } else {
      # The Tclconfig project maintains a mirror of the version
      # released with the Tcl core
      my define set tip_430 0
      ::practcl::LOCAL tool odie unpack
      set COMPATSRCROOT [::practcl::LOCAL tool odie define get srcdir]
      my add [file join $COMPATSRCROOT compat zipfs zipfs.tcl]
    }

    my define add include_dir [file join $TCLSRCDIR generic]
    my define add include_dir [file join $TCLSRCDIR $PLATFORM_SRC_DIR]
    # This file will implement TCL_LOCAL_APPINIT and TCL_LOCAL_MAIN_HOOK
    my build-tclkit_main $PROJECT $PKG_OBJS
  }

  ## Wrap an executable
  #
  method wrap {PWD exename vfspath args} {
    cd $PWD
    if {![file exists $vfspath]} {
      file mkdir $vfspath
    }
    foreach item [my link list core.library] {
      set name  [$item define get name]
      set libsrcdir [$item define get srcdir]
      if {[file exists [file join $libsrcdir library]]} {
        ::practcl::copyDir [file join $libsrcdir library] [file join $vfspath boot $name]
      }
    }
    # Assume the user will populate the VFS path
    #if {[my define get installdir] ne {}} {
    #  ::practcl::copyDir [file join [my define get installdir] [string trimleft [my define get prefix] /] lib] [file join $vfspath lib]
    #}
    foreach arg $args {
       ::practcl::copyDir $arg $vfspath
    }

    set fout [open [file join $vfspath packages.tcl] w]
    puts $fout {
set ::PKGIDXFILE [info script]
set dir [file dirname $::PKGIDXFILE]
if {$::tcl_platform(platform) eq "windows"} {
  set ::g(HOME) [file join [file normalize $::env(LOCALAPPDATA)] tcl]
} else {
  set ::g(HOME) [file normalize ~/tcl]
}
lappend ::auto_path [file join $::g(HOME) teapot]
}
    puts $fout [list proc installDir [info args ::practcl::installDir] [info body ::practcl::installDir]]
    set EXEEXT [my define get EXEEXT]
    set tclkit_bare [my define get tclkit_bare]
    set buffer [::practcl::pkgindex_path $vfspath]
    puts $fout $buffer
    puts $fout {
# Advertise statically linked packages
foreach {pkg script} [array get ::kitpkg] {
  eval $script
}
}
    close $fout
    ::practcl::mkzip ${exename}${EXEEXT} $tclkit_bare $vfspath
    if { [my define get TEACUP_OS] ne "windows" } {
      file attributes ${exename}${EXEEXT} -permissions a+x
    }
  }
}
