(*
Module: Grub
  Parses grub configuration

Author: David Lutterkort <lutter@redhat.com>

About: License
   This file is licenced under the LGPLv2+, like the rest of Augeas.

About: Lens Usage
   To be documented
*)

module Grub =
  autoload xfm

    (* This only covers the most basic grub directives. Needs to be *)
    (* expanded to cover more (and more esoteric) directives        *)
    (* It is good enough to handle the grub.conf on my Fedora 8 box *)


(************************************************************************
 * Group:                 USEFUL PRIMITIVES
 *************************************************************************)

    (* View: value_to_eol *)
    let value_to_eol = store /[^= \t\n][^\n]*[^= \t\n]|[^= \t\n]/

    (* View: eol *)
    let eol = Util.eol

    (* View: del_to_eol *)
    let del_to_eol = del /[^ \t\n]*/ ""

    (* View: spc *)
    let spc = Util.del_ws_spc

    (* View: opt_ws *)
    let opt_ws = Util.del_opt_ws ""

    (* View: dels *)
    let dels (s:string) = Util.del_str s

    (* View: eq *)
    let eq = dels "="

    (* View: switch *)
    let switch (n:regexp) = dels "--" . key n

    (* View: switch_arg *)
    let switch_arg (n:regexp) = switch n . eq . store Rx.no_spaces

    (* View: value_sep *)
    let value_sep (dflt:string) = del /[ \t]*[ \t=][ \t]*/ dflt

    (* View: comment_re *)
    let comment_re = /([^ \t\n].*[^ \t\n]|[^ \t\n])/
                       - /# ## (Start|End) Default Options ##/

    (* View: comment *)
    let comment    =
        [ Util.indent . label "#comment" . del /#[ \t]*/ "# "
            . store comment_re . eol ]

    (* View: empty *)
    let empty   = Util.empty

(************************************************************************
 * Group:                 USEFUL FUNCTIONS
 *************************************************************************)

    (* View: command *)
    let command (kw:regexp) (indent:string) =
      Util.del_opt_ws indent . key kw

    (* View: kw_arg *)
    let kw_arg (kw:regexp) (indent:string) (dflt_sep:string) =
      [ command kw indent . value_sep dflt_sep . value_to_eol . eol ]

    (* View: kw_boot_arg *)
    let kw_boot_arg (kw:string) = kw_arg kw "\t" " "

    (* View: kw_menu_arg *)
    let kw_menu_arg (kw:string) = kw_arg kw "" " "

    (* View: password_arg *)
    let password_arg = [ key "password" .
      (spc . [ switch "md5" ])? .
      spc . store (/[^ \t\n]+/ - "--md5") .
      (spc . [ label "file" . store /[^ \t\n]+/ ])? .
      eol ]

    (* View: kw_pres *)
    let kw_pres (kw:string) = [ opt_ws . key kw . del_to_eol . eol ]

(************************************************************************
 * Group:                 BOOT ENTRIES
 *************************************************************************)

    (* View: device
     *  This is a shell-only directive in upstream grub; the grub versions
     *  in at least Fedora/RHEL use this to find devices for UEFI boot *)
    let device =
	  [ command "device" "" . Sep.space . store /\([A-Za-z0-9_.-]+\)/ . spc .
		  [ label "file" . value_to_eol ] . Util.eol ]

    (* View: color *)
    let color =
      (* Should we nail it down to exactly the color names that *)
      (* grub supports ? *)
      let color_name = store /[A-Za-z-]+/ in
      let color_spec =
        [ label "foreground" . color_name] .
        dels "/" .
        [ label "background" . color_name ] in
      [ opt_ws . key "color" .
        spc . [ label "normal" . color_spec ] .
        (spc . [ label "highlight" . color_spec ])? .
        eol ]

    (* View: serial *)
    let serial =
      [ command "serial" "" .
        [ spc . switch_arg /unit|port|speed|word|parity|stop|device/ ]* .
        eol ]

    (* View: terminal *)
    let terminal =
      [ command "terminal" "" .
          ([ spc . switch /dumb|no-echo|no-edit|silent/ ]
          |[ spc . switch_arg /timeout|lines/ ])* .
          [ spc . key /console|serial|hercules/ ]* . eol ]

    (* View: menu_setting *)
    let menu_setting = kw_menu_arg "default"
                     | kw_menu_arg "fallback"
                     | kw_pres "hiddenmenu"
                     | kw_menu_arg "timeout"
                     | kw_menu_arg "splashimage"
                     | kw_menu_arg "gfxmenu"
                     | kw_menu_arg "background"
                     | serial
                     | terminal
                     | password_arg
                     | color
		     | device

    (* View: title *)
    let title = del /title[ \t=]+/ "title " . value_to_eol . eol

    (* View: multiboot_arg
     *  Permits a second form for Solaris multiboot kernels that
     *  take a path (with a slash) as their first arg, e.g.
     *  /boot/multiboot kernel/unix another=arg *)
    let multiboot_arg = [ label "@path" .
                          store (Rx.word . "/" . Rx.no_spaces) ]

    (* View: kernel_args
        Parse the file name and args on a kernel or module line. *)
    let kernel_args =
      let arg = /[A-Za-z0-9_.$-]+/ - /type|no-mem-option/  in
      store /(\([a-z0-9,]+\))?\/[^ \t\n]*/ .
            (spc . multiboot_arg)? .
            (spc . [ key arg . (eq. store /([^ \t\n])*/)?])* . eol

    (* View: module_line
        Solaris extension adds module$ and kernel$ for variable interpolation *)
    let module_line =
      [ command /module\$?/ "\t" . spc . kernel_args ]

    (* View: map_line *)
    let map_line =
      [ command "map" "\t" . spc .
           [ label "from" . store /[()A-za-z0-9]+/ ] . spc .
           [ label "to" . store /[()A-za-z0-9]+/ ] . eol ]

    (* View: kernel *)
    let kernel =
        [ command /kernel\$?/ "\t" .
          (spc .
             ([switch "type" . eq . store /[a-z]+/]
             |[switch "no-mem-option"]))* .
          spc . kernel_args ]

    (* View: chainloader *)
    let chainloader =
      [ command "chainloader" "\t" .
          [ spc . switch "force" ]? . spc . store Rx.no_spaces . eol ]

    (* View: savedefault *)
    let savedefault =
      [ command "savedefault" "\t" . (spc . store Rx.integer)? . eol ]

    (* View: configfile *)
    let configfile =
      [ command "configfile" "\t" . spc . store Rx.no_spaces . eol ]

    (* View: boot_setting
        <boot> entries *)
    let boot_setting = kw_boot_arg "root"
                     | kernel
                     | kw_boot_arg "initrd"
                     | kw_boot_arg "rootnoverify"
                     | chainloader
                     | kw_boot_arg "uuid"
                     | kw_boot_arg "findroot"  (* Solaris extension *)
                     | kw_boot_arg "bootfs"    (* Solaris extension *)
                     | kw_pres "quiet"  (* Seems to be a Ubuntu extension *)
                     | savedefault
                     | configfile
                     | module_line
                     | map_line

    (* View: boot *)
    let boot =
      let line = ((boot_setting|comment)* . boot_setting)? in
      [ label "title" . title . line ]

(************************************************************************
 * Group:                 DEBIAN-SPECIFIC SECTIONS
 *************************************************************************)

    (* View: debian_header
        Header for a <debian>-specific section *)
    let debian_header  = "## ## Start Default Options ##\n"

    (* View: debian_footer
        Footer for a <debian>-specific section *)
    let debian_footer  = "## ## End Default Options ##\n"

    (* View: debian_comment_re *)
    let debian_comment_re = /([^ \t\n].*[^ \t\n]|[^ \t\n])/
                            - "## End Default Options ##"

    (* View: debian_comment
        A comment entry inside a <debian>-specific section *)
    let debian_comment =
        [ Util.indent . label "#comment" . del /##[ \t]*/ "## "
            . store debian_comment_re . eol ]

    (* View: debian_setting_re *)
    let debian_setting_re = "kopt"
                          | "groot"
                          | "alternative"
                          | "lockalternative"
                          | "defoptions"
                          | "lockold"
                          | "xenhopt"
                          | "xenkopt"
                          | "altoptions"
                          | "howmany"
                          | "memtest86"
                          | "updatedefaultentry"
                          | "savedefault"
                          | "indomU"

    (* View: debian_entry *)
    let debian_entry   = [ Util.del_str "#" . Util.indent
                         . key debian_setting_re . del /[ \t]*=/ "="
                         . value_to_eol? . eol ]

    (* View: debian
        A debian-specific section, made of <debian_entry> lines *)
    let debian         = [ label "debian"
                    . del debian_header debian_header
                    . (debian_comment|empty|debian_entry)*
                    . del debian_footer debian_footer ]

(************************************************************************
 * Group:                 LENS AND FILTER
 *************************************************************************)

    (* View: lns *)
    let lns = (comment | empty | menu_setting | boot | debian)*

    (* View: filter *)
    let filter = incl "/boot/grub/menu.lst"
               . incl "/etc/grub.conf"

    let xfm = transform lns filter
