if {![package vsatisfies [package provide Tcl] 8.2]} {return}
package ifneeded autoproxy 1.5.4 [list source [file join $dir autoproxy.tcl]]
