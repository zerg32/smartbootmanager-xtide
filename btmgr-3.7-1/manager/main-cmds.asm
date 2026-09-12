; asmsyntax=nasm
;
; main-cmds.asm
;
; command handles for main program
;
; Copyright (C) 2000, Suzhe. See file COPYING for details.
;

%ifdef MAIN

%define MAIN_MENU_ON        0x01
%define RECORD_MENU_ON      0x02
%define SYS_MENU_ON         0x04

;=============================================================================
;show_help ---- show the help window
;=============================================================================
show_help:
        mov di, [str_idx.help]
        mov si, [str_idx.help_content]
        or si, si
        jz .end
        
        call count_lines
        mov dx, cx
        add dh, [size.box_height]
        add dl, [size.box_width]
        mov al, [color.help_msg]
        mov bx, [color.help_win_frame]
        xchg si, di
        call message_box
        call get_key
        call draw_screen
.end:
        ret

;=============================================================================
;show_about ---- show the about window
;=============================================================================
show_about:
        mov di, [str_idx.about]
        mov si, [str_idx.about_content]
        or si, si
        jz .end
        
        call count_lines
        mov dx, cx
        add dh, [size.box_height]
        add dl, [size.box_width]
        mov al, [color.about_msg]
        mov bx, [color.about_win_frame]
        xchg si, di
        call message_box
        call get_key
        call draw_screen
.end:
        ret

;=============================================================================
;ask_save_changes ---- save boot manager to disk
;=============================================================================
ask_save_changes:
        cmp byte [change_occured], 0
        je .no_changes
        
        mov si, [str_idx.ask_save_changes]
        call info_box
        cmp ax, kbEnter
        je save_changes
        cmp al, [yes_key_lower]
        je save_changes
        cmp al, [yes_key_upper]
        je save_changes
        
.no_changes:
        ret

;=============================================================================
;save_changes ---- save boot manager to disk
;=============================================================================
save_changes:
        test byte [kernel_flags], KNLFLAG_SECURITY
        jz .normal
        call confirm_root_passwd
        jc .end

.normal:

%ifndef EMULATE_PROG
        call save_boot_manager
        jc .disk_error
%endif

        mov byte [change_occured], 0               ; clear change signature.

        mov si, [str_idx.changes_saved]
        call info_box
        ret
        
.disk_error:
        call show_disk_error
.end:
        ret

;=============================================================================
;change_video_mode ---- change the video mode
;=============================================================================
change_video_mode:

        inc byte [change_occured]               ; some changes occured.

        mov al, [video_mode]
        not al
        mov [video_mode], al
        call init_video
        call draw_screen
        ret
        
;=============================================================================
;up_cur_in_menu ---- move the boot record cursor up in command menu
;=============================================================================
up_cur_in_menu:
        call up_cursor
        call draw_screen
        ret

;=============================================================================
;up_cursor ---- move the cursor up
;=============================================================================
up_cursor:
        mov al, [focus_record]
        or al, al                               ; already at top of the list
        jz .end                                 ; do nothing
        dec al
        mov [focus_record], al
        cmp [first_visible_rec], al
        jbe .end                                ; no need to scroll down.
        mov [first_visible_rec], al             ;
.end:
        ret
        
;=============================================================================
;down_cur_in_menu ---- move the boot record cursor down in command menu
;=============================================================================
down_cur_in_menu:
        call down_cursor
        call draw_screen
        ret

;=============================================================================
;down_cursor ---- move the cursor down
;=============================================================================
down_cursor:
        mov al, [focus_record]
        inc al
        cmp al, [good_record_number]            ;
        jae .end                                ; already at bottom of the list
        mov [focus_record], al
        sub al, [first_visible_rec]
        cmp al, [size.bootmenu_height]
        jb .end                                 ; no need to scroll up
        inc byte [first_visible_rec]
.end:
        ret

;=============================================================================
;change_name ---- change the record name
;=============================================================================
change_name:
        call auth_record_cmd
        jc .end

        call get_record_pointer

        add si, struc_bootrecord.name                   ;
        lea di, [tmp_buffer]                            ; get old name.
        mov cl, MAX_NAME_LENGTH                         ;
        xor ch, ch                                      ;
        push cx                                         ;
        push di                                         ;
        call strncpy                                    ;
        pop di                                          ;
        pop cx                                          ;
        
        push si
        
        movzx ax, byte [color.input_box_msg]
        mov bx, [color.input_box_frame]
        mov si, [str_idx.name]
        call input_box
        pop si
        jc .end_clean


        xchg di, si
        xor ch, ch
        call strncpy

        inc byte [change_occured]               ; some changes occured.
        
.end_clean:
        call draw_screen
.end:
        ret


;=============================================================================
;login_as_root ---- login as root
;=============================================================================
login_as_root:
        cmp dword [root_password], 0
        jz .end

        mov al, [root_login]
        or al, al
        jnz .logout

        call confirm_root_passwd
        jc .end

        mov byte [root_login], 1
        jmp short .end_clean

.logout:
        xor al, al
        mov [root_login], al

.end_clean:
        call draw_screen
.end:
        ret


;=============================================================================
;change_security_mode ---- change the secure mode
;=============================================================================
change_security_mode:
        cmp dword[root_password], 0
        jz .end

        test byte [kernel_flags], KNLFLAG_SECURITY
        jz .enter_security

        call confirm_root_passwd
        jc .end

        and byte [kernel_flags], ~ KNLFLAG_SECURITY
        jmp short .end_clean

.enter_security:
        or byte [kernel_flags], KNLFLAG_SECURITY

.end_clean:
        inc byte [change_occured]
        call draw_screen
.end:
        ret

;=============================================================================
;change_root_passwd ---- change the root password
;=============================================================================
change_root_passwd:
        call confirm_root_passwd
        jc .end
        
        mov si, [str_idx.new_root_passwd]
        call input_passwd
        jc .end
        mov bx, ax
        mov cx, dx

        push bx
        push cx
        mov si, [str_idx.retype_passwd]
        call input_passwd
        pop cx
        pop bx
        jc .end
        cmp bx, ax
        jne .wrong
        cmp cx, dx
        jne .wrong
        mov [root_password], bx
        mov [root_password+2], cx

        mov byte [root_login], 0
        and byte [kernel_flags], ~ KNLFLAG_SECURITY

        mov si, [str_idx.passwd_changed]
        call info_box

        inc byte [change_occured]               ; some changes occured.
        
        jmp short .end
.wrong:
        mov si, [str_idx.wrong_passwd]
        call error_box
.end:
        ret

;=============================================================================
;change_record_passwd ---- change the record password
;=============================================================================
change_record_passwd:
        call auth_record_cmd
        jc .end

        mov si, [str_idx.new_record_passwd]
        call input_passwd
        jc .end
        mov bx, ax
        mov cx, dx

        push bx
        push cx
        mov si, [str_idx.retype_passwd]
        call input_passwd
        pop cx
        pop bx
        jc .end
        cmp bx, ax
        jne .wrong
        cmp cx, dx
        jne .wrong

        call get_record_pointer
        mov [si+struc_bootrecord.password], bx
        mov [si+struc_bootrecord.password+2], cx
        
        mov si, [str_idx.passwd_changed]
        call info_box

        inc byte [change_occured]               ; some changes occured.
        
        ret
        
.wrong:
        mov si, [str_idx.wrong_passwd]
        call error_box
.end:
        ret

;=============================================================================
;set_default_record ---- set the default boot record
;=============================================================================
set_default_record:
        cmp byte [good_record_number], 0
        je .end

        call confirm_root_passwd
        jc .end

        movzx dx, [focus_record]                ; get real record index
        lea si, [good_record_list]              ;
        add si, dx                              ;
        lodsb                                   ;
        
        mov [default_record], al
        inc byte [change_occured]               ; some changes occured.
        call draw_bootmenu
.end:
        ret

;=============================================================================
;unset_default_record ---- unset the default boot record
;=============================================================================
unset_default_record:
        call confirm_root_passwd
        jc .end

        mov byte [default_record], 0xFF
        inc byte [change_occured]               ; some changes occured.
        call draw_bootmenu
.end:
        ret
        
;=============================================================================
;toggle_auto_active ---- toggle the auto active switch
;=============================================================================
toggle_auto_active:
.end:
        ret

;=============================================================================
;toggle_auto_hide ---- toggle the auto hide switch
;=============================================================================
toggle_auto_hide:
        cmp byte [good_record_number], 0
        je .end

        call get_record_pointer
        call check_allow_hide
        jc .end

        push si
        call confirm_security_passwd
        pop si
        jc .end
        
        xor word [si + struc_bootrecord.flags], INFOFLAG_AUTOHIDE
        inc byte [change_occured]               ; some changes occured.

.end:
        ret

;=============================================================================
;mark_active ---- mark the record active
;=============================================================================
mark_active:
        cmp byte [good_record_number], 0
        je .end

        call get_record_pointer
        call check_allow_act
        jc .end

        push si
        call confirm_security_passwd
        pop si
        jc .end

        mov dl, [si + struc_bootrecord.drive_id]

        push si
        lea si, [good_record_list]
        lea di, [boot_records]

        movzx cx, byte [good_record_number]
        mov dh, SIZE_OF_BOOTRECORD
        xor ebx, ebx
        cld
.loop_clear_act:                                ; clear all active marks of
        push di                                 ; the boot records in same
        lodsb                                   ; drive and father partition.
        mul dh
        add di, ax
        cmp dl, [di + struc_bootrecord.drive_id]
        jne .do_nothing
        cmp [di + struc_bootrecord.father_abs_addr], ebx
        jne .do_nothing
        and word [di + struc_bootrecord.flags], ~ INFOFLAG_ACTIVE
.do_nothing:
        pop di
        loop .loop_clear_act

        pop si
        
        call mark_record_active
        jc .error                                ; mark active ok
        call recheck_same_records                ; recheck same records
        jc .disk_error
        ret

.error:
        or ax, ax
        jz .cannot_act

.disk_error:
        call show_disk_error
        ret

.cannot_act:
        mov si, [str_idx.mark_act_failed]
        call error_box
.end:
        ret

;=============================================================================
;toggle_hidden ---- toggle a record's hidden attribute
;=============================================================================
toggle_hidden:
        cmp byte [good_record_number], 0
        je .end

        call get_record_pointer
        call check_allow_hide
        jc .end

        push si
        call confirm_security_passwd
        pop si
        jc .end

        call toggle_record_hidden
        jc .error                                 ; toggle hidden ok
        call recheck_same_records                 ; recheck same records
        jc .disk_error
        ret

.error:
        or ax, ax
        jz .cannot_hide

.disk_error:
        call show_disk_error
        ret

.cannot_hide:
        mov si, [str_idx.toggle_hid_failed]
        call error_box
.end:
        ret

;=============================================================================
;delete_record ---- delete a boot record
;=============================================================================
delete_record:
        cmp byte [good_record_number], 0
        je .end

        call confirm_root_passwd
        jc .end

        call get_record_pointer
        test word [si + struc_bootrecord.flags], INFOFLAG_HIDDEN
        jz .del_it

        call toggle_record_hidden           ; unhide it first.
        jnc .del_it                         ; unhide ok, del it.

        or ax, ax
        jz .cannot_hide
        call show_disk_error
        ret

.cannot_hide:
        mov si, [str_idx.toggle_hid_failed]
        call error_box
        ret

.del_it:
        xor al, al
        mov di, si
        mov cx, SIZE_OF_BOOTRECORD
        cld
        rep stosb

        inc byte [change_occured]               ; some changes occured.

        call init_good_record_list
        mov al, [good_record_number]
        or al, al
        jz .no_record
        
        dec al
        cmp al, [first_visible_rec]                     ; adjust the cursor
        jae .check_focus_pos                            ; and menu position.
        mov [first_visible_rec], al                     ;
.check_focus_pos:                                       ;
        cmp al, [focus_record]                          ;
        jae .end                                        ;
        mov [focus_record], al                          ;
        ret

.no_record:
        mov [first_visible_rec], al
        mov [focus_record], al
.end:
        ret
        

;=============================================================================
;rescan_all_drives ---- research all drives for boot records
;=============================================================================
rescan_all_records:
        and byte [kernel_flags], ~ KNLFLAG_ONLYPARTS
        jmp short rescan_records
        
;=============================================================================
;rescan_fixed_drives ---- research fixed drives for boot records
;=============================================================================
rescan_all_partitions:
        or byte [kernel_flags], KNLFLAG_ONLYPARTS
        
;=============================================================================
;rescan_records ---- research all drives for boot records
;=============================================================================
rescan_records:
        call confirm_root_passwd
        jc .end

        movzx cx, byte [good_record_number]
        or cl, cl                               ; if no good record then go to
        jz .init_it                             ; init directly.
        
        lea di, [good_record_list]
        mov dl, SIZE_OF_BOOTRECORD

; unhide all hidden partition first.
.loop_unhide:
        mov al, [di]
        inc di
        mul dl
        lea si, [boot_records]
        add si, ax
        test word [si + struc_bootrecord.flags], INFOFLAG_HIDDEN
        jz .not_hidden
        call toggle_record_hidden
        jc .hidden_error
        call recheck_same_records
        jc .disk_error

.not_hidden:
        loop .loop_unhide
        
.init_it:
        inc byte [change_occured]               ; some changes occured.

        call init_boot_records
        call init_good_record_list

        xor al, al
        mov byte [focus_record], al
        mov byte [first_visible_rec], al
        call draw_screen
        jmp short .end
        
.hidden_error:
        or ax, ax
        jz .cannot_hide
.disk_error:
        call show_disk_error
        ret

.cannot_hide:
        mov si, [str_idx.toggle_hid_failed]
        call error_box
.end:
        ret

;=============================================================================
;move_main_win_left ---- move the main window left
;=============================================================================
move_main_win_left:
        mov al, [main_window_col]
        or al, al
        jz .no_move
        dec al
        mov [main_window_col], al
        call draw_screen
.no_move:
        ret

;=============================================================================
;move_main_win_up ---- move the main window up
;=============================================================================
move_main_win_up:
        mov al, [main_window_row]
        cmp al, [size.copyright]
        jbe .no_move
        dec al
        mov [main_window_row], al
        call draw_screen
.no_move:
        ret

;=============================================================================
;move_main_win_right ---- move the main window right
;=============================================================================
move_main_win_right:
        mov al, [main_window_col]
        mov ah, [screen_width]
        sub ah, [main_win_width]
        sub ah, 2
        cmp al, ah
        jae .no_move
        inc al
        mov [main_window_col], al
        call draw_screen
.no_move:
        ret

;=============================================================================
;move_main_win_down ---- move the main window down
;=============================================================================
move_main_win_down:
        mov al, [main_window_row]
        mov ah, [screen_height]
        sub ah, [size.hint]
        cmp al, ah
        jae .no_move
        inc al
        mov [main_window_row], al
        call draw_screen
.no_move:
        ret

;=============================================================================
;set_delay_time ---- set the delay time
;=============================================================================
set_delay_time:
        call confirm_root_passwd
        jc .end

        movzx ax, [color.input_box_msg]
        mov bx, [color.input_box_frame]
        mov cl, 3
        mov si, [str_idx.delay_time]
        lea di, [tmp_buffer]
        mov byte [di], 0
        call input_box
        jc .end_clean

        mov si, di
        call atoi

        cmp ax, 255
        jbe .set_time
        mov al, 255
.set_time:
        mov [delay_time], al
        inc byte [change_occured]               ; some changes occured.
        
.end_clean:
        call draw_screen
.end:
        ret

;=============================================================================
;boot_it ---- boot the selected record
;=============================================================================
boot_it:
        cmp byte [good_record_number], 0
        je .end

        call confirm_record_passwd
        jc .end

        movzx dx, byte [focus_record]           ; get real record index
        lea si, [good_record_list]              ;
        add si, dx                              ;
        lodsb                                   ;
 
        push ax

        test byte [kernel_flags], KNLFLAG_REMLAST
        jz .no_remlast

        mov [default_record], al
       
        call save_boot_manager
        jnc .cont_boot

        call show_disk_error
        jmp short .cont_boot

.no_remlast:
        call ask_save_changes                   ; ask if save the changes.

.cont_boot:
        call hide_auto_hides
        pop ax
        jc .end
 
        call do_boot_record
.end:
        ret

;=============================================================================
;return_to_bios ---- give control back to BIOS
;=============================================================================
return_to_bios:
        call confirm_root_passwd
        jc .end

        call ask_save_changes                   ; ask if save the changes.
        
        call reset_video_mode
        
	call uninstall_myint13h
%ifdef EMULATE_PROG
        mov ax, 0x4c00                          ; exit to dos
        int 0x21                                ;
%else
        int 0x18                                ; return to BIOS
%endif

.end:
        ret


;=============================================================================
; Duplicate the boot record
;=============================================================================
dup_bootrecord:
        cmp byte [good_record_number], 0
        je .end

        call confirm_root_passwd
        jc .end

        mov ax, SIZE_OF_BOOTRECORD
        mov cx, MAX_RECORD_NUM
        lea di, [boot_records]

.search_empty_slot:
        test byte [di + struc_bootrecord.flags], DRVFLAG_DRIVEOK | INFOFLAG_ISSPECIAL
        jz .found_empty
        add di, ax
        loop .search_empty_slot
        jmp short .no_empty_slot

.found_empty:

        inc byte [change_occured]

        call get_record_pointer
        mov cx, ax 
        cld
        rep movsb
        call init_good_record_list

.no_empty_slot:

.end:
        ret



;=============================================================================
; move the boot record down 
;=============================================================================
move_record_down:
        movzx bx, byte [focus_record]
        mov al, [good_record_list + bx]
        inc bl
        mov ah, [good_record_list + bx]
        cmp bl, [good_record_number]
        jae .end

        cmp al, [default_record]
        jne .chknext
        mov [default_record], ah
        jmp short .swap_record
.chknext:
        cmp ah, [default_record]
        jne .swap_record
        mov [default_record], al

.swap_record:
        mov [focus_record], bl
        call swap_records
        dec byte [focus_record]
        call down_cursor
.end:
        ret

;=============================================================================
; move the boot record up
;=============================================================================
move_record_up:
        movzx bx, byte [focus_record]
        or bl, bl
        jz .end
        mov al, [good_record_list + bx]
        dec bl
        mov ah, [good_record_list + bx]

        cmp al, [default_record]
        jne .chknext
        mov [default_record], ah
        jmp short .swap_record
.chknext:
        cmp ah, [default_record]
        jne .swap_record
        mov [default_record], al

.swap_record:
  
        call swap_records
        call up_cursor
.end:
        ret

;=============================================================================
; swap current and previous boot record
;=============================================================================
swap_records:
        dec byte [focus_record]
        call get_record_pointer
	mov di, si
	inc byte [focus_record]
	call get_record_pointer			; si -> current  di -> prev

        mov cx, SIZE_OF_BOOTRECORD

.loop_swap:
	mov al, [si]
	mov bl, [di]
	mov [si], bl
	mov [di], al
	inc si
	inc di
	loop .loop_swap

        ret

;=============================================================================
;toggle_swapid ---- toggle the swap driver id flag 
;=============================================================================
toggle_swapid:
	call get_record_pointer
	test word [si + struc_bootrecord.flags], DRVFLAG_ISCDROM | INFOFLAG_ISSPECIAL
	jnz .end

	push si
        call auth_record_cmd
	pop si
        jc .end

        xor word [si + struc_bootrecord.flags], INFOFLAG_SWAPDRVID
        call check_bootrecord
        inc byte [change_occured]
.end:
        ret

;=============================================================================
;toggle_schedule ---- toggle the schedule of the bootrecord
;=============================================================================
toggle_schedule:
        call auth_record_cmd
        jc .end

        call get_record_pointer
        test word [si + struc_bootrecord.flags], INFOFLAG_SCHEDULED
        jnz .clear_schedule

        push si
        call input_schedule_time
        pop si
        jc .end

        or dx, dx
        jnz .set_schedule
        not dx

.set_schedule:
        call set_record_schedule
        jmp short .end_ok

.clear_schedule:
        and word [si + struc_bootrecord.flags], ~INFOFLAG_SCHEDULED

.end_ok:
        inc byte [change_occured]
.end:
        ret

;=============================================================================
;input_schedule_time ---- input the schedule time
;input:
;      none
;output:
;      cf = 0 success, 
;           ax = begin time (in minutes)
;           bx = end time (in minutes)
;           dx = days info (bit 0 to bit 7 indicate Mon to Sun)
;      cf = 1 cancel
;=============================================================================
input_schedule_time:
        pusha

        xor ax, ax
	mov cx, 4
	cld
	mov di, tmp_schedule_begin
	rep stosw

        mov al, [color.input_box_msg]
        mov bx, [color.input_box_frame]
        mov si, [str_idx.input_schedule]
        mov cl, 19
        lea di, [tmp_schedule_input]
        
        call input_box
        jc .failed

;convert begin time
        mov si, di
	call str_to_schtime
	jc .invalid_input
        mov [tmp_schedule_begin], ax

;convert end time
	lodsb
	cmp al,'-'
	jne .invalid_input

	call str_to_schtime
	jc .invalid_input
        mov [tmp_schedule_end], ax

;convert day info
        lodsb
        or al, al
        jz .end

        cmp al, ';'
        jne .invalid_input

        mov cx, 7
        xor dx, dx

.loop_get_days:
        lodsb
        or al, al
        jz .end_get_days
        sub al, '0'
        cmp al, 7
        jae .invalid_input
        mov bx, 1
        push cx
        mov cl, al
        shl bx, cl
        pop cx
        or dx, bx
        loop .loop_get_days

.end_get_days:
        mov [tmp_schedule_day], dx
.end:
	clc
.failed:
        pushf
        call draw_screen
        popf
	jmp short .exit

.invalid_input:
        call draw_screen
        mov si, [str_idx.invalid_schedule]
        call error_box
        stc
.exit:
        popa
        mov ax, [tmp_schedule_begin]
        mov bx, [tmp_schedule_end]
        mov dx, [tmp_schedule_day]
        ret


;=============================================================================
;input ds:si -> string
;output cf =0 ok, ax = time in minutes
;       cf =1 fail
;=============================================================================
str_to_schtime:
	xor bx, bx
	xor cx, cx

        call atoi
        cmp al, 24                          ; hh must be less than 24
        ja .fail

        mov bl, al
	lodsb
	cmp al, ':'
	jne .fail

        call atoi
        cmp al, 60                          ; mm must be less than 60
        jae .fail
        mov cl, al

        mov al, 60
        mul bl
        add ax, cx
        cmp ax, 24*60                       ; begin time must be no more than
        ja .fail                            ; 24*60 minutes
	clc
	ret
.fail:
	stc
	ret

;=============================================================================
;toggle_keystrokes ---- toggle the keystrokes switch of the bootrecord
;=============================================================================
toggle_keystrokes:
        call auth_record_cmd
        jc .end

        call get_record_pointer
        test word [si + struc_bootrecord.flags], INFOFLAG_HAVEKEYS
        jz .input_keys

        and word [si + struc_bootrecord.flags], ~INFOFLAG_HAVEKEYS
        jmp short .end_ok

.input_keys:
        lea di, [si + struc_bootrecord.keystrokes]
        mov cl, MAX_KEYSTROKES
        push si
        call input_keystrokes
        pop si
        or ch, ch
        jz .end

        or word [si + struc_bootrecord.flags], INFOFLAG_HAVEKEYS

.end_ok:
        inc byte [change_occured]
.end:
        ret

;=============================================================================
;input_keystrokes ---- input a set of key strokes
;input:
;      cl = max key strokes number
;      es:di -> the buffer
;output:
;      es:di -> the buffer filled by key strokes
;      ch = number of key strokes that inputed
;=============================================================================
input_keystrokes:

        call turnon_scrolllock

        push di

        xor ch, ch
        xor ax, ax

        cld

.loop_input:
        push cx
        push di
        call draw_ikm_box
        call read_keystroke
        pop di
        pop cx
        stosw
        jc .end

        inc ch
        cmp ch, cl
        jb .loop_input

.end:
        push cx
        call draw_screen
        pop cx
        pop di

        call turnoff_scrolllock

        ret

;=============================================================================
;draw_ikm_box ---- draw input keystrokes message box
;input:
;       ax = key code
;       ch = key count
;=============================================================================
draw_ikm_box:
        pusha

        mov si, [str_idx.input_keystrokes]
        lea di, [tmp_buffer]

        push di
        push cx

        call strcpy

        mov cl, 4
        call htoa                          ; fill in the key code string
        add di, 4

        mov si, [str_idx.key_count]
        call strcpy

        pop cx
        movzx ax, ch
        mov cl, 2
        call itoa                          ; fill in the key cound string

        pop si

        call count_lines
        mov dl, cl
        add dl, [size.box_width]
        mov dh, [size.box_height]
        add dh, ch
        mov al, [color.input_box_msg]
        mov bx, [color.input_box_frame]
        mov di, [str_idx.input]
        xchg di, si
        call message_box

        popa
        ret

;=============================================================================
;read_keystroke ---- read a key stroke
;input:
;      none (the scroll lock must be turned on before read keystrokes)
;output:
;      cf = 0 success, ax = key code
;      cf = 1 cancel (scroll lock was turned off)
;=============================================================================
read_keystroke:
.loop_read:
        mov ah, 0x01
        or ah, [keyboard_type]
        call bioskey
        jnz .have_key
        mov ah, 0x02
        or ah, [keyboard_type]
        call bioskey
        test al, kbScrollMask
        jz .cancel
        jmp short .loop_read

.have_key:
        mov ah, [keyboard_type]
        call bioskey
        clc
        ret

.cancel:
        xor ax, ax
        stc
        ret


;=============================================================================
;show_record_info ---- show the information of the boot record
;=============================================================================
show_record_info:
        push es
        push ds
        pop es
        cmp byte [good_record_number], 0
        jmpe .end

        call get_record_pointer
        lea di, [tmp_buffer]

        call get_record_schedule
        push dx
        push bx
        push ax

        push dword [si + struc_bootrecord.password]

        mov bx, [si + struc_bootrecord.flags]
        mov ax, [si + struc_bootrecord.drive_id]

        mov dx, si
        add si, struc_bootrecord.name
        push si                               ; save record name pointer
        push dx                               ; save record pointer
        push ax                               ; save drive_id and part_id

;write drive id
        mov si, [str_idx.drive_id]
        call strcpy

	test bx, INFOFLAG_ISSPECIAL
	jz .drvid_ok

	mov al, '-'
	stosb
	stosb
	jmp short .write_partid

.drvid_ok:
	mov dl, al
	call get_drvid_str

.write_partid:
;write part id
        mov si, [str_idx.part_id]
        call strcpy

        pop ax
	test bx, INFOFLAG_ISSPECIAL
	jz .partid_ok
	mov al, '-'
	stosb
	jmp short .write_rectype

.partid_ok:
        movzx ax, ah
        mov cx, 2
        call itoa
        add di, cx

.write_rectype:
;write record type
        mov si, [str_idx.record_type]
        call strcpy

        mov si, di
        call strlen

        mov ax, cx
        pop si
        call get_record_typestr
        mov si, di
        call strlen
        sub cx, ax
        add di, cx

;write record name 
        mov si, [str_idx.record_name]
        call strcpy
        pop si
        call strcpy

;write flags
	mov cx, 7
	mov dx, bx
	xor bx, bx
.loop_copy_flags:
	mov si, [str_idx.auto_active + bx]
	mov ax, [.flag_val + bx]
	call .copy_flag_stat
	inc bx
	inc bx
	loop .loop_copy_flags

;write password flag
        mov si, [str_idx.password]
        call strcpy
        pop ecx
        or ecx, ecx
        jz .no_pswd
        mov si, [str_idx.yes]
        jmp short .pswd
.no_pswd:
        mov si, [str_idx.no]
.pswd:
        call strcpy

;write schedule time
        mov si, [str_idx.schedule]
        call strcpy
        mov cx, dx

        pop ax
        pop bx
        pop dx

        test cx, INFOFLAG_SCHEDULED
        jz .no_sched
        call schedule_to_str
        jmp short .show_info

.no_sched:
        mov si, [str_idx.no]
        call strcpy

.show_info:
        lea si, [tmp_buffer]
        call info_box
.end:
        pop es
        ret

; si -> flag string
; ax = flag
.copy_flag_stat:
	call strcpy
        test dx, ax
        jz .no_this_flag
        mov si, [str_idx.yes] 
        jmp short .copy_flag
.no_this_flag:
        mov si, [str_idx.no]
.copy_flag:
        call strcpy
	ret

.flag_val	dw INFOFLAG_AUTOACTIVE, INFOFLAG_ACTIVE, INFOFLAG_AUTOHIDE, INFOFLAG_HIDDEN, INFOFLAG_SWAPDRVID
		dw INFOFLAG_LOGICAL, INFOFLAG_HAVEKEYS

;=============================================================================
;schedule_to_str ---- convert schedule time to string
;input:
;       ax = start time
;       bx = stop time
;       dx = days info
;       es:di -> buffer
;output:
;       none
;=============================================================================
schedule_to_str:
        pusha
        cld
        call sch_time_to_str
        mov si, di
        call strlen
        add di, cx
        mov al, '-'
        stosb
        mov ax, bx
        call sch_time_to_str
        mov si, di
        call strlen
        add di, cx
        mov al, ';'
        stosb
        call sch_days_to_str
        popa
        ret

;=============================================================================
;sch_days_to_str ---- convert days info string 0123456
;input:
;       dx = day bits
;       es:di -> buffer
;output:
;       none
;=============================================================================
sch_days_to_str:
        pusha
        mov cx, 7
        mov al, '0'
        mov bx, 1

.loop_chk:
        test dx, bx
        jz .nothisday
        stosb
.nothisday:
        shl bx, 1
        inc al
        loop .loop_chk

        xor al, al
        stosb

        popa
        ret

;=============================================================================
;sch_time_to_str ---- convert time in minute info string hh:mm
;input:
;       ax = time
;       es:di -> buffer
;output:
;       none
;=============================================================================
sch_time_to_str:
        pusha

        mov dl, 60
        div dl
        push ax

        xor ah, ah
        cmp al, 10
        jb .hlten
        mov cx, 2
        jmp short .showh
.hlten:
        mov cx,1
.showh:
        call itoa

        mov al,':'
        add di, cx
        stosb

        pop ax
        movzx ax, ah
        cmp al, 10
        jb .mlten
        mov cx, 2
        jmp short .showm
.mlten:
        mov cx,1
.showm:
        call itoa

        popa
        ret

       
;=============================================================================
; do_power_off ---- turn of the power
;=============================================================================
do_power_off:
        call power_off
        ret


;=============================================================================
;change_bootmenu_style ---- change the boot menu's draw style
;=============================================================================
change_bootmenu_style:
	mov al, [bootmenu_style]
	inc al
	cmp al, 4
	jb .ok
	xor al, al

.ok:
	mov [bootmenu_style], al
	call init_bootmenu_width

        call draw_screen
        inc byte [change_occured]
        ret

;=============================================================================
;toggle_rem_last ---- toggle the remember last switch.
;=============================================================================
toggle_rem_last:
        call confirm_root_passwd
        jc .end

        xor byte [kernel_flags], KNLFLAG_REMLAST
        inc byte [change_occured]
        call draw_screen

.end:
        ret

;=============================================================================
; show_cmd_menu ---- show a command menu
; input:
;       al = cmd menu mask
;       ds:si -> menu struct
; output:
;       none
;=============================================================================
show_cmd_menu:
        pusha
        mov bl, [cmd_menu_stat]
        push bx
        mov [cmd_menu_stat], al
        push si
        call draw_screen
        pop si
	xor al, al
        call popup_menu
        pop bx
        mov [cmd_menu_stat], bl
        call draw_screen
        popa
        ret

;=============================================================================
; show_main_menu ---- show the main commands menu
;=============================================================================
show_main_menu:
        mov al, MAIN_MENU_ON
        lea si, [main_menu]
        call show_cmd_menu
        ret

;=============================================================================
; show_record_menu ---- show the record commands menu
;=============================================================================
show_record_menu:
        mov al, RECORD_MENU_ON
        lea si, [record_menu]
        call show_cmd_menu
        ret

;=============================================================================
; show_sys_menu ---- show the system commands menu
;=============================================================================
show_sys_menu:
        mov al, SYS_MENU_ON
        lea si, [sys_menu]
        call show_cmd_menu
        ret

;=============================================================================
;move_menu_left ---- move the menu left
;input: 
;       ds:si -> point to menu structure
;=============================================================================
move_menu_left:
        mov al, [si + struc_menu.win_pos]
        or al, al
        jz .no_move
        dec al
        mov [si + struc_menu.win_pos], al
        call draw_screen
.no_move:
        ret

;=============================================================================
;move_menu_up ---- move the menu up
;input:
;       ds:si -> point to menu structure
;=============================================================================
move_menu_up:
        mov al, [si + struc_menu.win_pos + 1]
        cmp al, [size.copyright]
        jbe .no_move
        dec al
        mov [si + struc_menu.win_pos + 1], al
        call draw_screen
.no_move:
        ret

;=============================================================================
;move_menu_right ---- move the menu right
;input:
;       ds:si -> point to menu structure
;=============================================================================
move_menu_right:
        mov al, [si + struc_menu.win_pos]
        mov ah, [screen_width]
        sub ah, [si + struc_menu.win_size]
        sub ah, 2
        cmp al, ah
        jae .no_move
        inc al
        mov [si + struc_menu.win_pos], al
        call draw_screen
.no_move:
        ret

;=============================================================================
;move_menu_down ---- move the menu down
;=============================================================================
move_menu_down:
        mov al, [si + struc_menu.win_pos + 1]
        mov ah, [screen_height]
        sub ah, [si + struc_menu.win_size + 1]
        sub ah, [size.hint]
        cmp al, ah
        jae .no_move
        inc al
        mov [si + struc_menu.win_pos + 1], al
        call draw_screen
.no_move:
        ret


;=============================================================================
; boot_prev_in_menu ---- boot previous MBR in command menu
;=============================================================================
boot_prev_in_menu:
	call check_prev_mbr
	jc .end

        call confirm_root_passwd
        jc .end

	call boot_prev_mbr
.end:
	ret

;=============================================================================
; install_sbm
;=============================================================================
install_sbm:

%ifndef EMULATE_PROG
        cmp byte [good_record_number], 0
        je .end

        call get_record_pointer
	mov ax, [si + struc_bootrecord.flags]
        test ax , INFOFLAG_ISDRIVER
        jz .end
        test ax, DRVFLAG_ISCDROM
	jnz .end

        call confirm_root_passwd
        jc .end

        mov dl, [si + struc_bootrecord.drive_id]
	push dx

        lea di, [tmp_buffer]
        mov si, [str_idx.inst_confirm]
        push di
        call strcpy
	call get_drvid_str

        mov al, '?'
        stosb
        mov al, 0x0d
        stosb

        mov si, [str_idx.confirm]
        call strcpy
        pop si
        call info_box
	pop dx

        cmp al, [yes_key_lower]
        je .go_inst
        cmp al, [yes_key_upper]
        je .go_inst

        mov si, [str_idx.inst_abort]
        call error_box
.end:
        ret

.go_inst:
;read mbr into buffer
        xor ebx, ebx
        mov ax, (INT13H_READ << 8) | 0x01
        lea di, [disk_buf]
        call disk_access
        jmpc .disk_error

;backup old previous mbr
	lea si, [previous_mbr]
	mov cx, SECTOR_SIZE
	call xchg_buffer

;backup sbmk header data
        xor si, si
	lea di, [disk_buf1]
	mov cx, end_of_sbmk_header
	rep movsb

;set some variate
        xor eax, eax
	inc al
	mov cl, [kernel_sectors]

	mov [kernel_drvid], dl
	mov [kernel_sects1], cl
	mov [kernel_addr1], eax               ; kernel address = 1
	mov [kernel_sects2], ah               ; only one block of kernel

	mov [checksum], ah                    ; set checksum to zero

        mov [sbml_codes + struc_sbml_header.kernel_sects1], cl
        mov [sbml_codes + struc_sbml_header.kernel_addr1], eax
	mov [sbml_codes + struc_sbml_header.kernel_sects2], ah

;write sbmk to disk
        call save_boot_manager
	pushf

;restore sbmk header data
	xor di, di
	lea si, [disk_buf1]
	mov cx, end_of_sbmk_header
	rep movsb
	
;restore previous mbr
	lea si, [previous_mbr]
	lea di, [disk_buf]

	push di
	mov cx, SECTOR_SIZE
	call xchg_buffer
	pop di

	popf
        jc .disk_error

;copy sbml to disk_buf
	push di
	lea si, [sbml_codes]
	mov cx, SIZE_OF_MBR
	rep movsb
	pop di
	mov word [di + BR_FLAG_OFF], BR_GOOD_FLAG

;write loader to disk
        mov ax, (INT13H_WRITE << 8) | 0x01
	xor ebx,ebx
        call disk_access
        jc .disk_error

;install ok
        mov si, [str_idx.inst_ok]
        call info_box
        ret

.disk_error:
        call show_disk_error

%endif
        ret

; cx = count
; si -> source
; di -> dest
xchg_buffer:
	pusha
.xchg:
	mov al, [si]
	xchg al, [di]
	mov [si], al
	inc si
	inc di
	loop .xchg
	popa
	ret

;=============================================================================
; uninstall_sbm
;=============================================================================
uninstall_sbm:
%ifndef EMULATE_PROG

        call confirm_root_passwd
        jc .end

        lea di, [tmp_buffer]
        mov si, [str_idx.uninst_confirm]
        push di
        call strcpy
        mov si, [str_idx.confirm]
        call strcpy
        pop si
        call info_box

        cmp al, [yes_key_lower]
        je .go_uninst
        cmp al, [yes_key_upper]
        je .go_uninst

        mov si, [str_idx.uninst_abort]
        call error_box
.end:
        ret

.go_uninst:
        
;read mbr into buffer
        mov dl, [kernel_drvid]
        xor ebx, ebx
        mov ax, (INT13H_READ << 8) | 0x01
        lea di, [disk_buf]
        call disk_access
        jc .disk_error

;check if sbm is present
        cmp dword [di + struc_sbml_header.magic], SBML_MAGIC
        jne .no_sbml

        cmp word [di + struc_sbml_header.version], SBML_VERSION
        jne .no_sbml

;restore previous mbr
        push di
        lea si, [previous_mbr]
        mov cx, SIZE_OF_MBR
        cld
        rep movsb
        pop di
        mov word [di + BR_FLAG_OFF], BR_GOOD_FLAG

;write mbr back to disk
        xor ebx, ebx
        mov ax, (INT13H_WRITE << 8) | 0x01
        lea di, [disk_buf]
        call disk_access
        jc .disk_error
        mov si, [str_idx.uninst_ok]
        call info_box
        call reboot
        ret

.disk_error:
        call show_disk_error
        ret

.no_sbml:
        mov si, [str_idx.no_sbml]
        call error_box
%endif
        ret

;=============================================================================
; toggle_int13ext
;=============================================================================
toggle_int13ext:
        call confirm_root_passwd
        jc .end

        mov al, [kernel_flags]
        xor al, KNLFLAG_NOINT13EXT
        mov [kernel_flags], al

        test al, KNLFLAG_NOINT13EXT
        jnz .no_int13ext
        mov byte [use_int13_ext], 1
        jmp short .endok

.no_int13ext:
        mov byte [use_int13_ext], 0

.endok:
        inc byte [change_occured]
        call draw_screen

.end:
        ret

;=============================================================================
; set_cdrom_ioports
;=============================================================================

set_cdrom_ioports:
%ifndef DISABLE_CDBOOT
	test byte [kernel_flags], KNLFLAG_NOCDROM
	jnz .end

        call confirm_root_passwd
        jc .end

        lea di, [tmp_buffer]
	push di
	mov byte [di], 0 
	mov ax, [cdrom_ioports]
	or ax, ax
	jz .no_ports
	mov cl, 4
	call htoa
	add di, 4
	mov al, ','
	stosb
	mov ax, [cdrom_ioports+2]
	call htoa
.no_ports:
	pop di

        movzx ax, [color.input_box_msg]
        mov bx, [color.input_box_frame]
        mov cl, 9
        mov si, [str_idx.io_port]
	
        call input_box
        jc .end_clean

        mov si, di
	call atoh
	cmp byte [si], ','
	jne .invalid
	mov bx, ax
	inc si
	call atoh
	cmp byte [si], 0
	jne .invalid

	mov cx, ax
	mov [cdrom_ioports], bx
	mov [cdrom_ioports+2], cx

        inc byte [change_occured]               ; some changes occured.
	call set_io_ports
	jmp short .end_clean

.invalid:
	mov si, [str_idx.invalid_ioports]
	call error_box
	jmp .end
.end_clean:
        call draw_screen
.end:
%endif
        ret

;=============================================================================
; set_y2k_year
;=============================================================================

set_y2k_year:
%ifdef Y2K_BUGFIX
        call confirm_root_passwd
        jc .end

        lea di, [tmp_buffer]
	mov byte [di], 0 
	mov cl,4
	mov ax,[y2k_last_year]
	or ax,ax
	jz .nofix
	call bcd_to_str
.nofix:
        movzx ax, [color.input_box_msg]
        mov bx, [color.input_box_frame]
        mov si, [str_idx.year]
	
        call input_box
        jc .end_clean

	xor bx,bx
	or ch,ch
	jz .set

        mov si,di
.loop:
	shl bx,cl
	lodsb
	sub al,'0'
	or bl,al
	dec ch
	jnz .loop

	mov ah,4
	int 0x1a
	jc .end_clean

	mov cx,bx
	mov ah,5
	int 0x1a
.set:
	mov [y2k_last_year],bx
        inc byte [change_occured]               ; some changes occured.
.end_clean:
        call draw_screen
.end
%endif
        ret

%endif  ; END OF MAIN
