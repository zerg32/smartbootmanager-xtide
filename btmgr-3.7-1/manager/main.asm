; asmsyntax=nasm
;
; main.asm
;
; Main programs for Smart Boot Manager
;
; Copyright (C) 2000, Suzhe. See file COPYING for details.
;

%define MAIN
%define HAVE_MAIN_PROG
;%define EMULATE_PROG

%include "macros.h"
%include "ui.h"
%include "hd_io.h"
%include "knl.h"
%include "sbm.h"
%include "main.h"

%define NUM_OF_HOTKEYS      (func_list.entries - func_list.hotkeys)/2
%define NUM_OF_MNUCMDS      (menu_func_list.entries - menu_func_list.hotkeys)/2
%define MAIN_MENU_NITEMS    (func_list.record_mnu_hkeys - func_list.main_mnu_hkeys)/2
%define RECORD_MENU_NITEMS  (func_list.sys_mnu_hkeys - func_list.record_mnu_hkeys)/2
%define SYS_MENU_NITEMS     (func_list.end_of_mnu_hkeys - func_list.sys_mnu_hkeys)/2

	bits 16

%ifdef EMULATE_PROG
	org 0x100
%else
	org 0
%endif

	section .text
        
start_of_kernel:

	jmp start
	nop

start_of_sbmk_data:
;!!! PLEASE DON NOT CHANGE THE SIZE AND ORDER OF FOLLOWING DATA !!!

;=============================================================================
;the header of Smart Boot Manager kernel
;=============================================================================
sbmk_magic          dd  SBMK_MAGIC	; magic number = 'SBMK', 4 bytes.
sbmk_version        dw  SBMK_VERSION	; version, high byte is major version,
					; low byte is minor version.
total_size          dw  (end_of_kernel-start_of_kernel)
					; set to total(compressed) 
					; size by installer
compress_addr       dw  real_start	; The address of compressed part

checksum            db  0		; checksum of the kernel program.

kernel_sectors      db  0		; kernel size in sectors
kernel_drvid        db  0

kernel_sects1       db  0
kernel_addr1        dd  0		; the abs sector addr that kernel saved.

kernel_sects2       db  0
kernel_addr2        dd  0

kernel_sects3       db  0
kernel_addr3        dd  0

kernel_sects4       db  0
kernel_addr4        dd  0

kernel_sects5       db  0
kernel_addr5        dd  0

		    dw  BR_GOOD_FLAG
;=============================================================================
; MAIN data area
;=============================================================================
kernel_flags        db KNLFLAG_FIRSTSCAN 
delay_time          db 30                       ; delay time ( seconds )
direct_boot_record  db 0xff                     ; >= MAX_RECORD_NUM means no
                                                ; direct boot.
default_record      db 0xff                     ; the record number will
                                                ; be booted after the
                                                ; delay time is up or ESC
                                                ; key is pressed.
root_password       dd 0

bootmenu_style      db 0
                    db 0
cdrom_ioports       dw 0, 0

y2k_last_year       dw 0
y2k_last_month      db 0
		    db 0,0x55,0xAA

end_of_sbmk_header:

; buffer to store boot records
boot_records        times MAX_RECORD_NUM * SIZE_OF_BOOTRECORD db 0

sbml_codes          times SIZE_OF_MBR db 0
previous_mbr        times SECTOR_SIZE db 0

; private data 
main_window_col     db -1
main_window_row     db -1

end_of_sbmk_data:
;=============================================================================
; Program entry
;=============================================================================

start:

%ifndef EMULATE_PROG                            ; real program goes here.
	cli
	mov ax, STACK_SEG
	mov ss, ax                              ; ss:sp = 0x3000:0x1000
	mov sp, STACK_SIZE                      ;

	push cs
	pop ds
	sti

;Save current driver id for future use.
	mov [kernel_drvid], dl

;Backup Smart BootManager and decompress it, if it's compressed.
	push word KNLBACKUP_SEG
	pop es

	xor si, si
	xor di, di

	mov cx, [total_size]
	cld
	rep movsb

%ifdef COMPRESS_SBM
;test if it's compressed
	test byte [kernel_flags], KNLFLAG_COMPRESSED
	jmpz real_start

;decompress SBM
	lea si, [real_start]
	push si
	pop di

	push ds
	push es
	pop ds
	pop es

	mov bx, 0x800F
	xor cx, cx
	xor bp, bp
	inc bp
	push ds
	pop dx

	jmp short decompr_start_n2b		; decompress SBM

;=============================================================================
%include "n2b_d8e.ash"
;=============================================================================

%endif
%endif

;=============================================================================
%ifdef XTIDE_PRELOAD
	jmp real_start

xtide_preload_failed:
	mov si, xtide_preload_failed_text
.print_error:
	lodsb
	or al, al
	jz .halt
	mov ah, 0Eh
	mov bx, 0007h
	int 10h
	jmp short .print_error
.halt:
	mov al, [xtide_failure_code]
	mov ah, 0Eh
	mov bx, 0007h
	int 10h
	cli
	hlt
	jmp short .halt

xtide_preload_failed_text db "XTIDE preload failed: ", 0
%include "xtide_preload.asm"
%endif

;=============================================================================
; Compressed area starts here.
;=============================================================================
real_start:
	push cs					; reinitialize cs, ds
	push cs
	pop ds
	pop es

	lea di, [start_of_tmp_data]
	mov cx, end_of_tmp_data - start_of_tmp_data
	xor al, al                              ; clear the temp data area.
	rep stosb                               ;

; Install XT-IDE before SBM probes disks. The image is kept in a raw,
; low-LBA reservation so an old BIOS can read it before XT-IDE is active.
%ifdef XTIDE_PRELOAD
	call preload_xtide
	jc xtide_preload_failed
%endif

	mov bl, 1
	call install_myint13h

%ifndef DISABLE_CDBOOT				;Initializing the CD-ROMs..
	test byte [kernel_flags], KNLFLAG_NOCDROM
	jnz .not_set_cdrom_ports
	mov bx, [cdrom_ioports]
	mov cx, [cdrom_ioports+2]
	call set_io_ports
.not_set_cdrom_ports:
%endif

%ifndef EMULATE_PROG
	xor al, al

	test byte [kernel_flags], KNLFLAG_NOINT13EXT
	jnz .no_int13_ext

        inc al

.no_int13_ext:
	mov [use_int13_ext], al

	call init_theme			; initialize the theme
	call init_cmd_menus		; initialize the command menus
	call init_video			; initialize the video mode.

; save main window position.
	cmp byte [main_window_col], 0
	jg .main_win_col_ok
	mov al, [position.main_win_col]
	mov [main_window_col], al
.main_win_col_ok:
	cmp byte [main_window_row], 0
	jg .main_win_row_ok
	mov al, [position.main_win_row]
	mov [main_window_row], al
.main_win_row_ok:

; check if need scan boot records.
	test byte [kernel_flags], KNLFLAG_FIRSTSCAN
	jz .no_first_scan

	call init_boot_records		; if it's the first time
					; to run this program,
					; call the init_boot_records.
	call init_good_record_list
	and byte [kernel_flags], ~ KNLFLAG_FIRSTSCAN
	jmp short .show_menu

.no_first_scan:

%ifdef Y2K_BUGFIX
;Y2K fix for some BIOS which don't boot with years after 1999, we need to set
;the year based on the last time we booted the machine
	mov ah, 4
	int 0x1a				;(bcd) cx=year dh=month ...
	jc .y2k_donothing
	mov ax,[y2k_last_year]
	or ax,ax
	jz .y2k_donothing
	cmp [y2k_last_month],dh
	je .y2k_unbug
	jb .y2k_chmonth
	inc ax	;we enter here only if above wich means we don't have CF
	daa	;this is a must as daa uses CF and inc doesn't set it
	xchg ah,al
	adc al,0
	daa
	xchg ah,al
	mov [y2k_last_year],ax
.y2k_chmonth:
	mov [y2k_last_month],dh
        inc byte [change_occured]
.y2k_unbug:
	mov cx,ax
	mov ah,5				; FIXME this can go one day
	int 0x1a				; back if the day ends
.y2k_donothing:
%endif

; go ahead!
	call init_good_record_list

	mov ah, 0x02			; test the keyboard status,
	call bioskey			; if ctrl pressed then show
	test al, kbCtrlMask		; menu directly,
	jnz .show_menu			;

	mov al, [direct_boot_record]	; check if need boot directly.
	cmp al, MAX_RECORD_NUM		;
	jb .go_direct_boot

	call do_schedule		; implement the schedule table.

	cmp byte [delay_time], 0
	jnz .show_menu			; delay_time = 0, boot the
					; default record directly.
	mov al, [default_record]	;
	cmp al, MAX_RECORD_NUM
	jb .go_def_boot
	jmp short .show_menu
        
.go_direct_boot:
	mov byte [direct_boot_record], 0xff	; clear the direct boot sig.
	call save_boot_manager
	jc .disk_error

	mov [default_record], al

.go_def_boot:
	call boot_default
	jmp short .show_menu

.disk_error:
	call show_disk_error

%else
	call init_cmd_menus			; initialize the command menus
	call init_video				; here is the code for
	call init_boot_records			; emulate program.
	call do_schedule
%endif

.show_menu:
	call init_bootmenu_width

.not_hideflags:
	mov al, [delay_time]
	cmp al, 255
	jae .not_count_time			; if delay_time = 255
	mov [time_count], al			; then do not count time.
	xor al, al

.not_count_time:
	mov [key_pressed], al

	mov bl, [default_record]
	lea si, [good_record_list]
	mov cl, [good_record_number]
	xor ch, ch
	xor bh, bh
        
.loop_search_def:
	lodsb
	cmp al, bl
	je .found_def
	inc bh
	loop .loop_search_def
	jmp short .go_ahead

.found_def:
	mov [focus_record], bh
	cmp bh, [size.bootmenu_height]
	jb .go_ahead
	inc bh
	sub bh, [size.bootmenu_height]
	mov [first_visible_rec], bh

.go_ahead:
	call draw_screen

;=============================================================================
;msg_dispatcher ---- the main loop to handle user command
;=============================================================================
msg_dispatcher:
.loop_dispatch:
	call draw_bootmenu

	call get_key                            ; get a key

	lea si, [func_list.hotkeys]             ; search in hotkey list
	mov dx, ax
	mov cx, NUM_OF_HOTKEYS
	xor bx, bx
.loop_search:
	lodsw
	cmp dx, ax
	je .found_it                            ; found, go get func entry
	inc  bx
	loop .loop_search
	jmp short .loop_dispatch                ; not found, wait more

.found_it:
	shl bx, byte 1
	call word [bx + func_list.entries]      ; call the function
	jmp short .loop_dispatch

;=============================================================================
; do_nothing ---- just return!
;=============================================================================
do_nothing:
	ret

;=============================================================================
;include area
;=============================================================================

%include "main-cmds.asm"
%include "main-utils.asm"
%include "ui.asm"
%include "utils.asm"
%include "knl.asm"
%include "hd_io.asm"
%ifdef XTIDE_PRELOAD
%include "myint13h_stub.asm"
%else
%include "myint13h.asm"
%endif

;=============================================================================
; data area
;=============================================================================


func_list:
.hotkeys:
        dw  kbUp
        dw  kbEnhUp
        dw  kbCtrlUp
        dw  kbEnhCtrlUp
        dw  kbDown
        dw  kbEnhDown
        dw  kbCtrlDown
        dw  kbEnhCtrlDown

        dw  kbEnhEnter
        dw  kbEsc
        dw  kbTab

.main_mnu_hkeys:
        dw  kbF1
        dw  kbCtrlF1
        dw  kbF2
        dw  kbEnter
        dw  0
        dw  0
        dw  kbAltR
        dw  kbAltS
        dw  0
        dw  kbCtrlQ
        dw  kbCtrlF12

.record_mnu_hkeys:
        dw  kbSlash
        dw  kbF3
        dw  kbF9
        dw  kbCtrlS
        dw  kbCtrlK
        dw  0
        dw  kbF4
        dw  kbF5
        dw  kbF6
        dw  kbF7
        dw  kbCtrlX
        dw  0
        dw  kbCtrlD
        dw  kbCtrlP
        dw  kbCtrlU
        dw  kbCtrlN

.sys_mnu_hkeys:
        dw  kbF10
        dw  kbCtrlF10
        dw  kbAltF10
        dw  0
        dw  kbF8
        dw  kbShiftF8
        dw  kbCtrlT
        dw  kbCtrlF
        dw  kbCtrlL
        dw  0
        dw  0
        dw  kbCtrlI
        dw  kbCtrlH
        dw  0
        dw  0
        dw  0
        dw  0
        dw  0

.end_of_mnu_hkeys:
        dw  kbGrayPlus
        dw  kbDel
        dw  kbEnhDel
        dw  kbHome
        dw  kbEnhHome
        dw  kbPgDn
        dw  kbEnhPgDn
        dw  kbEnd
        dw  kbEnhEnd
        dw  kbQuestion

;=======================================================
.entries:
        dw  up_cursor                       ; kbUp
        dw  up_cursor                       ; kbUp
        dw  up_cursor                       ; kbUp
        dw  up_cursor                       ; kbUp
        dw  down_cursor                     ; dbDown
        dw  down_cursor                     ; dbDown
        dw  down_cursor                     ; dbDown
        dw  down_cursor                     ; dbDown
        dw  boot_it                         ; kbEnter
        dw  boot_default                    ; kbEsc
        dw  show_main_menu                  ; kbTab

.main_mnu_cmds:
        dw  show_help                       ; kbF1
        dw  show_about                      ; kbCtrlF1
        dw  save_changes                    ; kbF2
        dw  boot_it                         ; kbEnter
        dw  boot_prev_in_menu               ; nokey
        dw  do_nothing                      ; nokey
        dw  show_record_menu                ; nokey
        dw  show_sys_menu                   ; nokey
        dw  do_nothing                      ; nokey
        dw  return_to_bios                  ; kbCtrlQ
        dw  do_power_off                    ; kbCtrlF12

.record_mnu_cmds:
        dw  show_record_info                ; kbSlash
        dw  change_name                     ; kbF3
        dw  change_record_passwd            ; kbF9
        dw  toggle_schedule                 ; kbCtrlS
        dw  toggle_keystrokes               ; kbCtrlK
        dw  do_nothing                      ; nokey
        dw  mark_active                     ; kbF4
        dw  toggle_hidden                   ; kbF5
        dw  toggle_auto_active              ; kbF6
        dw  toggle_auto_hide                ; kbF7
        dw  toggle_swapid                   ; kbCtrlX
        dw  do_nothing                      ; nokey
        dw  delete_record                   ; kbCtrlD
        dw  dup_bootrecord                  ; kbCtrlP
        dw  move_record_up                  ; kbCtrlU
        dw  move_record_down                ; kbCtrlN

.sys_mnu_cmds:
        dw  change_root_passwd              ; kbF10
        dw  login_as_root                   ; kbCtrlF10
        dw  change_security_mode            ; kbAltF10
        dw  do_nothing                      ; nokey
        dw  set_default_record              ; kbF8
        dw  unset_default_record            ; kbShiftF8
        dw  set_delay_time                  ; kbCtrlT
        dw  change_bootmenu_style           ; kbCtrlF
        dw  toggle_rem_last                 ; kbCtrlL
        dw  toggle_int13ext                 ; nokey
        dw  do_nothing                      ; nokey
        dw  rescan_all_records              ; kbCtrlI
        dw  rescan_all_partitions           ; kbCtrlH
	dw  set_cdrom_ioports               ; nokey
        dw  set_y2k_year                    ; nokey
        dw  do_nothing                      ; nokey
        dw  install_sbm                     ; nokey
        dw  uninstall_sbm                   ; nokey

.end_of_mnu_cmds:
        dw  change_video_mode               ; kbGrayPlus
        dw  move_main_win_left              ; kbDel
        dw  move_main_win_left              ; kbDel
        dw  move_main_win_up                ; kbHome
        dw  move_main_win_up                ; kbHome
        dw  move_main_win_right             ; kbPgDn
        dw  move_main_win_right             ; kbPgDn
        dw  move_main_win_down              ; kbEnd
        dw  move_main_win_down              ; kbEnd
        dw  show_record_info                ; kbQuestion

;==========================================================
menu_func_list:
.hotkeys:
        dw  kbDel
        dw  kbEnhDel
        dw  kbHome
        dw  kbEnhHome
        dw  kbPgDn
        dw  kbEnhPgDn
        dw  kbEnd
        dw  kbEnhEnd

        dw  kbCtrlUp
        dw  kbEnhCtrlUp
        dw  kbCtrlDown
        dw  kbEnhCtrlDown

        dw  kbCtrlHome
        dw  kbEnhCtrlHome
        dw  kbCtrlEnd
        dw  kbEnhCtrlEnd
        dw  kbCtrlDel
        dw  kbEnhCtrlDel
        dw  kbCtrlPgDn
        dw  kbEnhCtrlPgDn

.entries:
        dw  move_menu_left
        dw  move_menu_left
        dw  move_menu_up
        dw  move_menu_up
        dw  move_menu_right
        dw  move_menu_right
        dw  move_menu_down
        dw  move_menu_down
        dw  up_cur_in_menu
        dw  up_cur_in_menu
        dw  down_cur_in_menu
        dw  down_cur_in_menu

        dw  move_main_win_up
        dw  move_main_win_up
        dw  move_main_win_down
        dw  move_main_win_down
        dw  move_main_win_left
        dw  move_main_win_left
        dw  move_main_win_right
        dw  move_main_win_right

;========================================================
;command menus
;========================================================
main_menu  istruc struc_menu
        at struc_menu.title,       dw 0
        at struc_menu.n_items,     dw MAIN_MENU_NITEMS
        at struc_menu.cur_item,    dw 0
        at struc_menu.win_pos,     dw 0
        at struc_menu.menu_size,   dw 0
        at struc_menu.win_size,    dw 0
        at struc_menu.win_attr,    dw 0
        at struc_menu.norm_attr,   dw 0
        at struc_menu.focus_attr,  dw 0
        at struc_menu.str_tbl,     dw str_idx.main_menu_strings
        at struc_menu.cmd_tbl,     dw func_list.main_mnu_cmds
        at struc_menu.hkey_tbl,    dw func_list.main_mnu_hkeys
        at struc_menu.mnu_cmd_num, dw NUM_OF_MNUCMDS
        at struc_menu.mnu_cmd_tbl, dw menu_func_list.entries
        at struc_menu.mnu_hkey_tbl,dw menu_func_list.hotkeys
        at struc_menu.post_req_cmd,dw 0
        iend

record_menu  istruc struc_menu
        at struc_menu.title,       dw 0
        at struc_menu.n_items,     dw RECORD_MENU_NITEMS
        at struc_menu.cur_item,    dw 0
        at struc_menu.win_pos,     dw 0
        at struc_menu.menu_size,   dw 0
        at struc_menu.win_size,    dw 0
        at struc_menu.win_attr,    dw 0
        at struc_menu.norm_attr,   dw 0
        at struc_menu.focus_attr,  dw 0
        at struc_menu.str_tbl,     dw str_idx.record_menu_strings
        at struc_menu.cmd_tbl,     dw func_list.record_mnu_cmds
        at struc_menu.hkey_tbl,    dw func_list.record_mnu_hkeys
        at struc_menu.mnu_cmd_num, dw NUM_OF_MNUCMDS
        at struc_menu.mnu_cmd_tbl, dw menu_func_list.entries
        at struc_menu.mnu_hkey_tbl,dw menu_func_list.hotkeys
        at struc_menu.post_req_cmd,dw draw_screen
        iend

sys_menu  istruc struc_menu
        at struc_menu.title,       dw 0
        at struc_menu.n_items,     dw SYS_MENU_NITEMS
        at struc_menu.cur_item,    dw 0
        at struc_menu.win_pos,     dw 0
        at struc_menu.menu_size,   dw 0
        at struc_menu.win_size,    dw 0
        at struc_menu.win_attr,    dw 0
        at struc_menu.norm_attr,   dw 0
        at struc_menu.focus_attr,  dw 0
        at struc_menu.str_tbl,     dw str_idx.sys_menu_strings
        at struc_menu.cmd_tbl,     dw func_list.sys_mnu_cmds
        at struc_menu.hkey_tbl,    dw func_list.sys_mnu_hkeys
        at struc_menu.mnu_cmd_num, dw NUM_OF_MNUCMDS
        at struc_menu.mnu_cmd_tbl, dw menu_func_list.entries
        at struc_menu.mnu_hkey_tbl,dw menu_func_list.hotkeys
        at struc_menu.post_req_cmd,dw 0
        iend

;END OF KERNEL
        dw BR_GOOD_FLAG
end_of_kernel:

;=============================================================================
;theme data
;=============================================================================
theme_start:

%ifdef THEME_ZH
%include "themes/theme-zh.asm"
%elifdef THEME_DE
%include "themes/theme-de.asm"
%elifdef THEME_HU
%include "themes/theme-hu.asm"
%elifdef THEME_RU
%include "themes/theme-ru.asm"
%elifdef THEME_CZ
%include "themes/theme-cz.asm"
%elifdef THEME_ES
%include "themes/theme-es.asm"
%elifdef THEME_FR
%include "themes/theme-fr.asm"
%elifdef THEME_PT
%include "themes/theme-pt.asm"
%else
%include "themes/theme-us.asm"
%endif

;=============================================================================
; temp data area
;=============================================================================
SIZE_OF_SBMK equ ($-$$)
	section .bss

%ifndef EMULATE_PROG
        resb MAX_SBM_SIZE - SIZE_OF_SBMK   ; skip enough space for theme.
%endif
 
start_of_tmp_data:
%include "tempdata.asm"
end_of_tmp_data:

; vi:ts=8:et:nowrap
