::oo::class create ::practcl::metaclass {
  superclass ::oo::object

  method define {submethod args} {
    my variable define
    switch $submethod {
      dump {
        return [array get define]
      }
      add {
        set field [lindex $args 0]
        if {![info exists define($field)]} {
          set define($field) {}
        }
        foreach arg [lrange $args 1 end] {
          if {$arg ni $define($field)} {
            lappend define($field) $arg
          }
        }
        return $define($field)
      }
      remove {
        set field [lindex $args 0]
        if {![info exists define($field)]} {
          return
        }
        set rlist [lrange $args 1 end]
        set olist $define($field)
        set nlist {}
        foreach arg $olist {
          if {$arg in $rlist} continue
          lappend nlist $arg
        }
        set define($field) $nlist
        return $nlist
      }
      exists {
        set field [lindex $args 0]
        return [info exists define($field)]
      }
      getnull -
      get -
      cget {
        set field [lindex $args 0]
        if {[info exists define($field)]} {
          return $define($field)
        }
        return [lindex $args 1]
      }
      set {
        if {[llength $args]==1} {
          set arglist [lindex $args 0]
        } else {
          set arglist $args
        }
        array set define $arglist
        if {[dict exists $arglist class]} {
          my select
        }
      }
      default {
        array $submethod define {*}$args
      }
    }
  }

  method graft args {
    my variable organs
    if {[llength $args] == 1} {
      error "Need two arguments"
    }
    set object {}
    foreach {stub object} $args {
      dict set organs $stub $object
      oo::objdefine [self] forward <${stub}> $object
      oo::objdefine [self] export <${stub}>
    }
    return $object
  }

  method initialize {} {}


  method link {command args} {
    my variable links
    switch $command {
      object {
        foreach obj $args {
          foreach linktype [$obj linktype] {
            my link add $linktype $obj
          }
        }
      }
      add {
        ###
        # Add a link to an object that was externally created
        ###
        if {[llength $args] ne 2} { error "Usage: link add LINKTYPE OBJECT"}
        lassign $args linktype object
        if {[info exists links($linktype)] && $object in $links($linktype)} {
          return
        }
        lappend links($linktype) $object
      }
      remove {
        set object [lindex $args 0]
        if {[llength $args]==1} {
          set ltype *
        } else {
          set ltype [lindex $args 1]
        }
        foreach {linktype elements} [array get links $ltype] {
          if {$object in $elements} {
            set nlist {}
            foreach e $elements {
              if { $object ne $e } { lappend nlist $e }
            }
            set links($linktype) $nlist
          }
        }
      }
      list {
        if {[llength $args]==0} {
          return [array get links]
        }
        if {[llength $args] != 1} { error "Usage: link list LINKTYPE"}
        set linktype [lindex $args 0]
        if {![info exists links($linktype)]} {
          return {}
        }
        return $links($linktype)
      }
      dump {
        return [array get links]
      }
    }
  }

  method morph classname {
    my variable define
    if {$classname ne {}} {
      set map [list @name@ $classname]
      foreach pattern [split [string map $map {
        @name@
        ::practcl::@name@
        ::practcl::project.@name@
        ::practcl::subproject.@name@
        ::practcl::tool.@name@
        ::practcl::*@name@
        ::practcl::*@name@*
      }] \n] {
        set pattern [string trim $pattern]
        set matches [info commands $pattern]
        if {![llength $matches]} continue
        set class [lindex $matches 0]
        break
      }
      set mixinslot {}
      foreach {slot pattern} {
        distribution ::practcl::distribution*
        product      ::practcl::product*
        toolset      ::practcl::toolset*
      } {
        if {[string match $pattern $class]} {
           set mixinslot $slot
           break
        }
      }
      if {$mixinslot ne {}} {
        my mixin $mixinslot $class
      } elseif {[info command $class] ne {}} {
        if {[info object class [self]] ne $class} {
          ::oo::objdefine [self] class $class
          ::practcl::debug [self] morph $class
           my define set class $class
        }
      } else {
        error "[self] Could not detect class for $classname"
      }
    }
    if {[::info exists define(oodefine)]} {
      ::oo::objdefine [self] $define(oodefine)
      unset define(oodefine)
    }
  }

  method mixin {slot classname} {
    my variable mixinslot
    set class {}
    set map [list @slot@ $slot @name@ $classname]
    foreach pattern [split [string map $map {
      @name@
      @slot@.@name@
      ::practcl::@name@
      ::practcl::@slot@.@name@
      ::practcl::@slot@*@name@
      ::practcl::*@name@*
    }] \n] {
      set pattern [string trim $pattern]
      set matches [info commands $pattern]
      if {![llength $matches]} continue
      set class [lindex $matches 0]
      break
    }
    ::practcl::debug [self] mixin $slot $class
    dict set mixinslot $slot $class
    set mixins {}
    foreach {s c} $mixinslot {
      if {$c eq {}} continue
      lappend mixins $c
    }
    oo::objdefine [self] mixin {*}$mixins
  }

  method organ {{stub all}} {
    my variable organs
    if {![info exists organs]} {
      return {}
    }
    if { $stub eq "all" } {
      return $organs
    }
    if {[dict exists $organs $stub]} {
      return [dict get $organs $stub]
    }
  }

  method script script {
    eval $script
  }

  method select {} {
    my variable define
    if {[info exists define(class)]} {
      my morph $define(class)
    } else {
      if {[::info exists define(oodefine)]} {
        ::oo::objdefine [self] $define(oodefine)
        unset define(oodefine)
      }
    }
  }

  method source filename {
    source $filename
  }
}
