; asmsyntax=nasm
;
; main-utils.asm
;
; utility functions for main program
;
; Copyright (C) 2000, Suzhe. See file COPYING for details.
;

%ifdef MAIN

;=============================================================================
;init_theme ---- initialize the theme data.
;=============================================================================
init_theme:
        mov bx, [icon.brand]
        or bx, bx
        jz .adjust_bkgnd                            ; no brand icon
        add word [icon.brand], theme_start          ;
.adjust_bkgnd:
        mov bx, [icon.background]
        or bx, bx
        jz .adjust_font                             ; no background icon
        add word [icon.background], theme_start
.adjust_font:
        mov bx, [font.data]
        or bx, bx
        jz .adjust_keymap
        add word [font.data], theme_start
.adjust_keymap:
        mov bx, [keymap.data]
        or bx, bx
        jz .adjust_str
        add word [keymap.data], theme_start

.adjust_str:
        lea si, [str_idx]
        mov cx, (end_of_str_idx - str_idx)/2
        
.loop_adjust:
        mov bx, [si]
        add bx, theme_start
        mov [si], bx
        add si, 2
        loop .loop_adjust

        mov al, 0x10
        and [keyboard_type], al

        ret
        
;=============================================================================
;init_cmd_menus ---- initialize the command menus
;=============================================================================
init_cmd_menus:
        pusha
;initialize main menu
        lea si, [main_menu]
        mov bx, [str_idx.main_menu_title]
        call init_popup_menu
;initialize record menu
        lea si, [record_menu]
        mov bx, [str_idx.record_menu_title]
        call init_popup_menu
;initialize system menu
        lea si, [sys_menu]
        mov bx, [str_idx.sys_menu_title]
        call init_popup_menu
        popa
        ret

;ds:si -> menu struct
;bx = addr of string index
init_popup_menu:
        mov [si + struc_menu.title], bx
        mov ax, [position.cmd_menu_col]
        mov [si + struc_menu.win_pos], ax
        mov ax, [color.cmd_menu_winframe]
        mov [si + struc_menu.win_attr], ax
        mov ax, [color.cmd_menu_normal]
        mov [si + struc_menu.norm_attr], ax
        mov ax, [color.cmd_menu_focus]
        mov [si + struc_menu.focus_attr], ax
        call calc_menusize
        ret

;=============================================================================
;init_video ---- init the video mode
;input:
;      none
;output:
;      none
;=============================================================================
init_video:
        mov al, [video_mode]
        mov bl, 8
        mov bp, [font.data]
        mov cx, [font.number]
        
        call set_video_mode
        ret

;=============================================================================
;init_good_record_list ---- init the good boot record list
;input:
;      none
;output:
;      cf = 0 sucess
;      cf = 1 failed, no good record
;=============================================================================
init_good_record_list:
        cld
        pusha
        mov cx, MAX_RECORD_NUM
        lea di, [good_record_list]
        lea si, [boot_records]
        xor ax, ax
.loop_check:
        call check_bootrecord                   ; check if it's valid
        jc .check_next
        stosb                                   ; store it's index to buffer
        inc ah
        
.check_next:
        inc al
        add si, SIZE_OF_BOOTRECORD
        loop .loop_check

        mov [good_record_number], ah
        or ah, ah
        jnz .ok
        stc
.ok:
        popa
        ret

;=============================================================================
;init_boot_records ---- init the boot records list
;input:
;      none
;output:
;      none
;=============================================================================
init_boot_records:
        pusha
        inc byte [change_occured]         ; some changes occured.

        cld
        mov al, SIZE_OF_BOOTRECORD        ;
        mov cl, MAX_RECORD_NUM            ; ax = size of bootrecord
        xor ah, ah                        ;
        xor ch, ch                        ; cx = max record number

        lea si, [boot_records]
        lea di, [tmp_records_buf]
        push di
        push cx
        push ax
        mul cl                            ; cx = size of boot records array
        mov cx, ax                        ;
        xor ax, ax                        ;
        rep stosb                         ; clear tmp_records_buf
        pop ax
        pop cx
        pop di

        mov bl, cl

        push si
        push cx                           ; cx = MAX_RECORD_NUM
.bkp_good_records:
        call check_bootrecord
        jc .bad_record

        push si
        push cx
        mov cx, ax
        rep movsb
        pop cx
        pop si

        dec bl
        
.bad_record:
        add si, ax
        loop .bkp_good_records

        pop cx                           ; cx = MAX_RECORD_NUM
        pop si                           ; si -> boot_records
        xchg si, di                      ; di -> boot_records

        push di
	push ax
        xor dl, dl
        test byte [kernel_flags], KNLFLAG_ONLYPARTS
	setnz al
        call search_records
	pop ax
        pop di

;search finished, find out new records
        mov cl, MAX_RECORD_NUM
        xor ch, ch
        xchg si, di                      ; si -> boot_records

        push si

        or bl, bl
        jz .no_space

.search_news:
        push di
        lea di, [tmp_records_buf]
        call find_record_in_buf
        pop di

        jnc .found

        push cx
        push si
        mov cx, ax
        rep movsb
        pop si
        pop cx

        dec bl

.found:
        or bl, bl
        jz .no_space
        add si, ax
        loop .search_news

.no_space:

        pop si
        lea di, [tmp_records_buf]
        mov cl, MAX_RECORD_NUM
        mul cl
        mov cx, ax
        xchg di, si
        rep movsb

        popa
        ret

;=============================================================================
; find_record_in_buf ---- find a record in a buffer
; input:
;      ds:si -> the record
;      es:di -> the buffer
; output:
;      cf = 1 not found
;=============================================================================
find_record_in_buf:
        pusha
	mov bx, [si + struc_bootrecord.flags]
        test bx, DRVFLAG_DRIVEOK|INFOFLAG_ISSPECIAL

        jz .not_found

        mov cx, MAX_RECORD_NUM

.compare_next:
	test bx, INFOFLAG_ISSPECIAL
	jz .normal_rec
	test word [di + struc_bootrecord.flags], INFOFLAG_ISSPECIAL
	jnz .special_rec
	jmp short .not_same

.normal_rec:
	test word [di + struc_bootrecord.flags], DRVFLAG_DRIVEOK
	jz .not_same
        mov ax, [di + struc_bootrecord.drive_id]
        cmp [si + struc_bootrecord.drive_id], ax
        jne .not_same
        mov eax, [di + struc_bootrecord.father_abs_addr]
        cmp [si + struc_bootrecord.father_abs_addr], eax
        jne .not_same
        mov eax, [di + struc_bootrecord.abs_addr]
        cmp [si + struc_bootrecord.abs_addr], eax
        jne .not_same

.special_rec:
        mov al, [di + struc_bootrecord.type]
        cmp [si + struc_bootrecord.type], al
        jne .not_same

        jmp short .found_same

.not_same:
        add di, SIZE_OF_BOOTRECORD
        loop .compare_next

.not_found:
        stc
        popa
        ret

.found_same:
        clc
        popa
        ret

;=============================================================================
;draw_screen ---- draw the whole screen
;input:
;      none
;output:
;      none
;=============================================================================
draw_screen:
        call lock_screen

        mov bh, [color.background]              ;
        mov si, [icon.background]               ; draw background
        mov cx, [icon.background_size]          ;
        call draw_background                    ;

        xor dx, dx                              ;
        mov bx, [color.copyright]               ;
        mov al, [screen_width]                  ; draw copyright message
        push ax                                 ; save screen width
        mov cl, [size.copyright]
        mul cl
        mov cx, ax
        mov al, ' '                             ;
        call draw_char                          ;
        mov si, [str_idx.copyright]
        call draw_string_hl
        
        mov bx, [color.hint]                    ;
        mov dh, [screen_height]                 ;
        mov cl, [size.hint]                     ;
        sub dh, cl                              ; draw hint message
        pop ax                                  ; get screen width
        mul cl                                  ;
        mov cx, ax                              ;
        mov al, ' '                             ;
        call draw_char                          ;
        mov si, [str_idx.hint]                  ;
        call draw_string_hl                     ;

        mov dx, [position.brand_col]            ; draw brand icon
        mov cx, [icon.brand_size]               ;
        cmp dl, 0xFF                            ;
        jne .not_justify                        ;
        mov dl, [screen_width]                  ; right justify
        sub dl, cl                              ;
.not_justify:                                   ;
        mov si, [icon.brand]                    ;
        call draw_icon                          ;

        call draw_date
        call draw_time
        call draw_delay_time
        call draw_knl_flags
        call draw_main_window
        call draw_bootmenu

        mov al, [cmd_menu_stat]
        test al, MAIN_MENU_ON
        jz .chk_recordmenu
        lea si, [main_menu]
        jmp short .draw_cmd_menu

.chk_recordmenu:
        test al, RECORD_MENU_ON
        jz .chk_sysmenu
        lea si, [record_menu]
        jmp short .draw_cmd_menu

.chk_sysmenu:
        test al, SYS_MENU_ON
        jz .end
        lea si, [sys_menu]
 
.draw_cmd_menu:
        call draw_menu_box
        call draw_menu

.end:
        call unlock_screen
        ret
        
;=============================================================================
;draw_date ---- draw the date string
;input:
;      none
;output:
;      none
;=============================================================================
draw_date:
        pusha
        lea di, [tmp_buffer]                    ; draw date
        mov al, [show_date_method]              ;
        call get_cur_date_str                   ;
        mov si, di                              ;
        mov bl, [color.date]                    ;
        mov dx, [position.date_col]             ;
        call draw_string                        ;
        popa
        ret

;=============================================================================
;draw_time ---- draw the time string
;input:
;      none
;output:
;      none
;=============================================================================
draw_time:
        pusha
        lea di, [tmp_buffer]                    ; draw date
        mov al, [show_time_method]              ;
        call get_cur_time_str                   ;
        mov si, di                              ;
        mov bl, [color.time]                    ;
        mov dx, [position.time_col]             ;
        call draw_string                        ;
        popa
        ret

;=============================================================================
;update_time_info ---- update the time info, it the time is changed.
;=============================================================================
update_time_info:
        pusha
        mov ah, 0x02
        int 0x1a
        cmp [last_time], cx
        je .end

        call draw_date
        call draw_time

        mov [last_time], cx

.end:
        popa
        ret

;=============================================================================
;draw_main_window ---- draw the main window
;input:
;      none
;output:
;      none
;=============================================================================
draw_main_window:
        pusha
        mov cx, [main_window_col]                       ; get main window's
        mov dx, cx                                      ; coordinate
        add dh, [size.main_win_height]
        dec dh
        add dl, [main_win_width]
        dec dl

        mov bx, [color.main_win_frame]                  ; get main window's color
        mov si, [str_idx.main_win_title]                ; get main window's title

        call draw_window

        add cx, (MENU_TITLE_POS_ROW << 8) + MENU_TITLE_POS_COL
        mov dx, cx
        mov bl, [color.menu_title]
        mov al, ' '
        movzx cx, byte [menu_width]
        call draw_char
        inc dl
	mov si, [bootmenu_title_str]
        call draw_string                                ; draw title string
        popa
        ret

;=============================================================================
;draw_knl_flags ---- draw root passwd, login, secure mode, remember last 
;                    and int13 ext flags.
;=============================================================================
draw_knl_flags:
        mov dh, [screen_height]
        mov dl, [screen_width]
        sub dx, 0x0113

        mov bl, [color.hint]
        mov al, '|'
        mov cx, 1
        call draw_char
        inc dl

        lea di, [tmp_buffer]

	push di
	push dx
	mov dl, [kernel_drvid]
	call get_drvid_str
	pop dx
	pop si

        mov bl, [color.knl_drvid]

        call draw_string
        add dl, 3

        mov bl, [color.hint]
        mov cx, 1
        mov al, '|'
        call draw_char
        inc dl

        mov bl, [color.knl_flags]
        cmp dword [root_password], 0
        jz .no_root_password
        
        mov al, 'P'
        jmp short .draw_pwd
.no_root_password:
        mov al, '-'
.draw_pwd:
        call draw_char
        inc dl

        test byte [kernel_flags], KNLFLAG_SECURITY
        jz .no_security

        mov al, 'S'
        jmp short .draw_security
.no_security:
        mov al, '-'
.draw_security:
        call draw_char
        inc dl

        mov al, [root_login]
        or al, al
        jz .no_root_login

        mov al, 'A'
        jmp short .draw_login
.no_root_login:
        mov al, '-'
.draw_login:
        call draw_char

        inc dl

        test byte [kernel_flags], KNLFLAG_REMLAST
        jz .no_remlast
        mov al, 'L'
        jmp short .draw_remlast
.no_remlast:
        mov al, '-'
.draw_remlast:
        call draw_char

        inc dl

        test byte [kernel_flags], KNLFLAG_NOINT13EXT
        jnz .no_int13ext
        mov al, 'E'
        jmp .draw_int13ext
.no_int13ext:
        mov al, '-'
.draw_int13ext:
        call draw_char
        inc dl

        mov bl, [color.hint]
        mov al, '|'
        call draw_char

        ret

;=============================================================================
;draw_scrollbar ---- draw the scroll bar
;=============================================================================
draw_scrollbar:
        xor cx, cx
        inc cl

        mov bl, [color.scrollbar]
        mov dx, [main_window_col]
        add dx, (MENU_POS_ROW << 8) + MENU_POS_COL
        add dl, [menu_width]

        mov bh, [size.bootmenu_height]
        push dx
        push bx

;draw scroll bar
        mov al, 0x1e
        call draw_char

        mov al, ' '
        dec bh
.loop_draw_bar:
        dec bh
        inc dh
        call draw_char
        or bh, bh
        jnz .loop_draw_bar

        mov al, 0x1f
        call draw_char

;calculate the bar cursor position
        pop bx
        pop dx

        cmp bh, [good_record_number]
        jae .no_cursor
        cmp bh, 3
        jb .no_cursor

        sub bh, 2

        movzx ax, byte [focus_record]
        mul bh
        mov bh, [good_record_number]
        or bh, bh
        jz .no_cursor
        div bh

        add dh, al
        inc dh

        mov al, 'O'
        call draw_char

.no_cursor:
        ret
 
;=============================================================================
;draw_bootmenu_item ---- draw a boot menu item
;input:
;      bl = high 4 bit Background color and low 4 bit Foreground color
;      cl = item index in good_record_list
;output:
;      none
;=============================================================================
draw_bootmenu_item:
        pusha
        cmp byte [good_record_number], 0
        je .no_menu_item

        xor ch, ch
        lea si, [good_record_list]                  ; get real index of the
        add si, cx                                  ; boot record.
        lodsb                                       ; al = the index
        
        xor ah, ah                                  ; get the pointer of
        push ax                                     ;
        mov dl, SIZE_OF_BOOTRECORD                  ; selected boot record.
        mul dl                                      ;
        lea si, [boot_records]                      ;
        add si, ax                                  ;
        
        lea di, [tmp_buffer]
	mov al, [bootmenu_style]
        call get_record_string

        mov dh, cl                                  ; calculate the draw
        sub dh, [first_visible_rec]                 ; coordinate of the
        add dh, MENU_POS_ROW                        ; menu item.
        mov dl, MENU_POS_COL                        ;
        add dx, [main_window_col]

        mov cl, 1
        mov al, ' '
        call draw_char                              ; draw a leading space
        inc dl
        pop ax                                      ; al = the real index

        cmp al, [default_record]                    ;
        jne .not_default                            ;
        mov al, '*'                                 ; draw a flag before
        jmp .draw_def_flag                          ; the menu item, if
.not_default:                                       ; it's default record.
        mov al, ' '                                 ;
.draw_def_flag:                                     ;
        call draw_char                              ;
        inc dl                                      ;
        
        mov si, di
        call draw_string                            ; draw the menu item.

        call strlen                                 ; get the length of the item.
        mov al, ' '
        mov ah, [menu_width]
        sub ah, cl
        sub ah, 3
        add dl, cl
        mov cl, ah
        inc cl
        call draw_char                              ; fill ending space chars
.no_menu_item:
        popa
        ret

;=============================================================================
;draw_bootmenu ---- draw the boot menu
;input:
;      none
;output:
;      none
;=============================================================================
draw_bootmenu:
        pusha
        mov bl, [color.menu_normal]
        mov bh, bl
        mov cx, [main_window_col]                       ; get the top left
        add cx, (MENU_POS_ROW << 8) + MENU_POS_COL      ; and bottom right
        mov dx, cx                                      ; corner's coordinate
        add dh, [size.bootmenu_height]
        dec dh
        add dl, [menu_width]
        sub dl, 1                                       ; of menu area

        call clear_screen                               ; clear the menu area

        mov cl, [first_visible_rec]
        mov ch, cl
        add ch, [size.bootmenu_height]
.loop_draw:
        cmp cl, [good_record_number]
        jae .end
        cmp cl, ch
        jae .end
        call draw_bootmenu_item
        inc cl
        jmp .loop_draw
.end:

;draw focused item
        mov bl, [color.menu_focus]
        mov cl, [focus_record]

        call draw_bootmenu_item                     ; draw focus menu item
        call draw_scrollbar

        popa
        ret

;=============================================================================
;draw_delay_time ---- draw the delay_time and time_count
;=============================================================================
draw_delay_time:
        movzx ax, byte [time_count]
        mov cx, 3
        lea di, [tmp_buffer]
        call itoa
        
        mov bl, [color.delay_time]
        mov dh, [screen_height]
        mov dl, [screen_width]
        sub dx, 0x0108
        mov si, di
        call draw_string

        movzx ax, byte [delay_time]
        mov cx, 3
        call itoa

        mov al, ':'
        mov cl, 1
        add dl, 3
        call draw_char
        inc dl
        call draw_string
        mov al, ' '
        add dl, 3
        call draw_char
        ret
        

;=============================================================================
;get_key ---- get a key stroke while count down the delay time and refresh the
;             calendar info
;input:
;      none
;output:
;      ax = the key code
;=============================================================================
get_key:

.wait_key:
        call update_time_info

        cmp byte [delay_time], 0                        ; if delay_time set to zero
        je .no_count                                    ; then don't count time.
        cmp byte [key_pressed], 0                       ; if key pressed then don't
        jne .no_count                                   ; count time.

        xor ah, ah                                      ; get time ticks
        int 0x1a                                        ;

        cmp dx, [ticks_count]                           ;
        jae .next_time                                  ; dx must greater than
        mov [ticks_count], dx                           ; ticks_count
.next_time:
        mov cx, dx                                      ; every 18 ticks approxmiately
        sub cx, [ticks_count]                           ; equal to 1 second,
        cmp cx, 18                                      ; decrease time_count
        jbe .not_add                                    ; until to zero.
        mov [ticks_count], dx                           ;
        dec byte [time_count]                           ;
        call draw_delay_time                            ;
.not_add:
        cmp byte [time_count], 0                        ; if time is up, then
        jbe .esc_key                                    ; send ESC key.

.no_count:
        mov ah,1                                        ; if no key pressed
        or ah, [keyboard_type]
        call bioskey                                    ; go back to check
	jz .check_alt_key
        mov ah, [keyboard_type]                         ; if any key pressed

.read_key:
        call bioskey                                    ; then get it.
	jmp short .have_key

.check_alt_key:
	mov ah,2
	call bioskey
	test al, kbAltMask
	jz .wait_key

.wait_alt_release:
	mov ah, 2
	call bioskey
	test al, kbAltMask
	jnz .wait_alt_release

        mov ah,1                                        ; if no key pressed
        or ah, [keyboard_type]
        call bioskey                                    ; go back to check
	jnz .read_key

	mov ax, kbTab

.have_key:
	
        mov byte [key_pressed], 1
        ret

.esc_key:
        mov ax, kbEsc
        inc byte [key_pressed]
        ret

;=============================================================================
;recheck_same_records ---- recheck all records that same as given record
;input:
;      ds:si -> record
;output:
;      cf = 0  success
;      cf = 1  failed
;=============================================================================
recheck_same_records:
        pusha
        mov ax, [si + struc_bootrecord.drive_id]
        mov ebx, [si + struc_bootrecord.father_abs_addr]
        mov edx, [si + struc_bootrecord.abs_addr]

        lea si, [boot_records]
        mov cx, MAX_RECORD_NUM

.loop_check:
        test byte [si + struc_bootrecord.flags], DRVFLAG_DRIVEOK
        jz .check_next
        cmp [si + struc_bootrecord.drive_id], ax
        jne .check_next
        cmp [si + struc_bootrecord.father_abs_addr], ebx
        jne .check_next
        cmp [si + struc_bootrecord.abs_addr], edx
        jne .check_next

        call check_bootrecord
        jc .end

.check_next:
        add si, SIZE_OF_BOOTRECORD
        loop .loop_check
        clc
.end:
        popa
        ret

;=============================================================================
;get_realtime ---- get the machine real time in minutes
;input:
;      none
;output:
;      cf = 0 success, ax = real time in minutes, dx = day (set a bit)
;      cf = 1 failed
;=============================================================================
get_realtime:
        push bx
        push cx

        mov ah, 0x04
        int 0x1a
        jc .end

        movzx ax, dh
        call bcd_to_bin
        mov dh, al
        mov al, dl
        call bcd_to_bin
        mov dl, al

        mov ax, cx
        call bcd_to_bin

        call day_in_week

        mov dx, 1
        shl dx, cl

        push dx
        mov ah, 0x02
        int 0x1a
        pop dx
        jc .end

        movzx ax, ch
        call bcd_to_bin
        mov ch, al

        mov al, cl
        call bcd_to_bin
        mov cl, al

;convert hour and minute into minute
        mov al, 60
        mul ch
        xor ch, ch
        add ax, cx

        clc
.end:
        pop cx
        pop bx

        ret


;=============================================================================
; get_cur_time_str ---- get current time string
; input: al = show method, es:di -> buffer
;=============================================================================
get_cur_time_str:
       pusha
       or al, al
       jz .end

       mov ah, 0x02
       int 0x1a
       jc .end

       mov bx, cx

       mov cx, 2

       movzx ax, bh
       call bcd_to_str
       add di, cx
       mov al, ':'
       stosb

       mov al, bl
       call bcd_to_str
       add di, cx
       
.end:
       xor al, al
       stosb
       popa
       ret      


;=============================================================================
; get_cur_date_str ---- get current date string
; input: al = show method, es:di -> buffer
;        the method of show date:
;           0 = don't show date
;           1 = day mm-dd-yyyy
;           2 = day yyyy-mm-dd
;           3 = day dd-mm-yyyy
; output: none
;=============================================================================
get_cur_date_str:
       pusha

       or al, al
       jz .end

       push ax
       mov ah, 0x04
       int 0x1a
       pop ax
       jc .end

       push ax
       push cx
       push dx

       movzx ax, dh
       call bcd_to_bin
       mov dh, al
       mov al, dl
       call bcd_to_bin
       mov dl, al

       mov ax, cx
       call bcd_to_bin

       call day_in_week

       mov bx, cx
       shl bx, 1
       mov si, [str_idx.sunday+bx]

       call strcpy
       mov al, ' '
       stosb

       pop dx
       pop bx
       pop ax

       xor cx, cx

       cmp al, 1
       je .mmddyy
       cmp al, 2
       je .yymmdd
       cmp al, 3
       je .ddmmyy
       jmp .end

.end:       
       xor al, al
       stosb
       popa
       ret

.mmddyy:
       mov al, '-'
       push ax
       call .write_mm
       pop ax
       stosb
       push ax
       call .write_dd
       pop ax
       stosb
       call .write_yy

       jmp .end

.yymmdd:
       mov al, '-'
       push ax
       call .write_yy
       pop ax
       stosb
       push ax
       call .write_mm
       pop ax
       stosb
       call .write_dd

       jmp .end

.ddmmyy:
       mov al, '-'
       push ax
       call .write_dd
       pop ax
       stosb
       push ax
       call .write_mm
       pop ax
       stosb
       call .write_yy

       jmp .end

.write_mm:
       movzx ax, dh
       mov cl, 2
       call bcd_to_str
       add di, cx
       ret

.write_dd:
       movzx ax, dl
       mov cl, 2
       call bcd_to_str
       add di, cx
       ret

.write_yy:
       mov ax, bx
       mov cl, 4
       call bcd_to_str
       add di, cx
       ret
 
;=============================================================================
;get_record_pointer ---- get current record pointer
;input:
;      none
;output:
;      ds:si -> record pointer
;=============================================================================
get_record_pointer:
        push dx
        push ax
        movzx dx, [focus_record]                ; get real record index
        lea si, [good_record_list]              ;
        add si, dx                              ;
        lodsb                                   ;

        mov dl, SIZE_OF_BOOTRECORD              ; get the pointer to
        mul dl                                  ; the record.
        lea si, [boot_records]                  ;
        add si, ax                              ;
        pop ax
        pop dx
        ret
        
;=============================================================================
;confirm_root_passwd ---- confirm the root password
;input:
;      none
;output:
;      cf = 0 success
;      cf = 1 failed or cancel
;=============================================================================
confirm_root_passwd:
        pusha
        mov bx, [root_password]
        mov cx, [root_password+2]
        or bx, bx
        jnz .have_password
        or cx, cx
        jnz .have_password
        jmp .auth_ok
        
.have_password:                                     
        mov si, [str_idx.root_passwd]               ; check root
        call confirm_passwd                         ; password
.auth_ok:
        popa
        ret


;=============================================================================
;confirm_security_passwd ---- confirm the secure password
;                           in normal mode it confirms record password
;                           in security mode it confirms root password
;=============================================================================
confirm_security_passwd:
        test byte [kernel_flags], KNLFLAG_SECURITY
        jz confirm_record_passwd
        jmp confirm_root_passwd

;=============================================================================
;confirm_record_passwd ---- confirm the record password
;=============================================================================
confirm_record_passwd:
        pusha
        call get_record_pointer
        mov bx, [si + struc_bootrecord.password]
        mov cx, [si + struc_bootrecord.password+2]
        or bx, bx
        jnz .have_password
        or cx, cx
        jnz .have_password
        jmp .auth_ok
        
.have_password:
        mov si, [str_idx.record_passwd]             ; check record
        call confirm_passwd                         ; password
.auth_ok:
        popa
        ret

;=============================================================================
;confirm_passwd ---- let user input a password and confirm it.
;input:
;      bx:cx = password
;      ds:si -> message string
;output:
;      cf = 0 success
;      cf = 1 failed or cancel
;=============================================================================
confirm_passwd:
        mov al, [root_login]                        ; check if root
        or al, al                                   ; has login
        jnz .ok                                ;

        call input_passwd
        jc .cancel

        cmp bx, ax
        jne .cmp_root
        cmp cx, dx
        jne .cmp_root
        jmp .ok
        
.cmp_root:
        cmp [root_password], ax
        jne .failed
        cmp [root_password+2], dx
        jne .failed
.ok:
        clc
        ret
        
.failed:
        mov si, [str_idx.wrong_passwd]
        call error_box
        
.cancel:
        stc
        ret


;=============================================================================
;input_passwd ---- input a passwd
;input:
;      ds:si -> message string
;output:
;      cf = 0 success, ax:dx = password
;      cf = 1 cancel
;=============================================================================
input_passwd:
        push bx
        push cx
        
        mov ah, 1
        mov al, [color.input_box_msg]
        mov bx, [color.input_box_frame]
        mov cx, (MAX_PASSWORD_LENGTH << 8) | MAX_PASSWORD_LENGTH
        lea di, [tmp_buffer]
        mov byte [di], 0
        call input_box
        jc .cancel_input

        mov si, di
        movzx cx, ch
        call calc_password
        clc
.cancel_input:
        push ax
        push dx
        pushf
        call draw_screen
        popf
        pop dx
        pop ax
        pop cx
        pop bx
        ret

;=============================================================================
;error_box ---- draw error message box.
;input:
;      ds:si -> error message
;output:
;      ax = return keycode
;=============================================================================
error_box:
        call count_lines
        mov dl, cl
        add dl, [size.box_width]
        mov dh, [size.box_height]
        add dh, ch

        mov al, [color.error_box_msg]
        mov bx, [color.error_box_frame]
        mov di, [str_idx.error]
        xchg di, si
        call message_box
        xor ah, ah
        call bioskey
        push ax
        call draw_screen
        pop ax
        ret

;=============================================================================
;info_box ---- draw infomation message box.
;input:
;      ds:si -> infomation message
;output:
;      ax = return keycode
;=============================================================================
info_box:
        call count_lines
 
        mov dl, cl
        add dl, [size.box_width]
        mov dh, [size.box_height]
        add dh, ch

        mov al, [color.info_box_msg]
        mov bx, [color.info_box_frame]
        mov di, [str_idx.info]
        xchg di, si
        call message_box
        xor ah, ah
        call bioskey
        push ax
        call draw_screen
        pop ax
        ret

;=============================================================================
;boot_default ---- boot the default record
;=============================================================================
boot_default:
        mov ah, [default_record]
        lea si, [good_record_list]
        movzx cx, [good_record_number]
        or cl, cl
        jz .no_default
        cld
.loop_search:
        lodsb
        cmp al, ah
        je .found_it
        loop .loop_search
        
.no_default:                                ; no default record, do nothing.
        ret
        
.found_it:
	push ax
	call hide_auto_hides
	pop ax
	xor ah, ah
        call do_boot_record
        ret
        
;=============================================================================
;do_boot_record ---- really boot the given record.
;input:
;      ax =  the boot record number.
;=============================================================================
do_boot_record:
        mov bl, SIZE_OF_BOOTRECORD
        mul bl

        lea si, [boot_records]
        add si, ax

	mov bx, [si + struc_bootrecord.flags]

	test bx, INFOFLAG_ISSPECIAL
	jz .boot_drv_part

	call do_special_record
	jmp .end_clean

.boot_drv_part:
%ifndef DISABLE_CDBOOT
	test bx, DRVFLAG_ISCDROM
	jz .normal_boot

	mov dl, [si + struc_bootrecord.drive_id]
	mov di, disk_buf1
	call get_cdrom_boot_catalog
	jc .disk_error

	push si
	mov si, di
	mov di, disk_buf
	call find_boot_catalog
	pop si

	or cx, cx
	jz .no_system
	cmp cx, 1
	je .go_boot_cdrom

	push si
	mov si, di
	call choose_cdimg
	pop si
	jc .end_clean

	mov cl, SIZE_OF_BOOT_CATALOG
	mul cl

	add di, ax

.go_boot_cdrom:
	push dx
	push di
        call preload_keystrokes     ; preload the keystrokes into key buffer.
        call reset_video_mode
	pop di
	pop dx
	call boot_cdrom
	jmp short .boot_fail

%endif

.normal_boot:
        call boot_the_record

.boot_fail:
        or al, al
        jz .no_system

.disk_error:
        call show_disk_error
        ret

.no_system:
        mov si, [str_idx.no_system]
        call error_box
	ret

.end_clean:
	call draw_screen
        ret
        

;=============================================================================
;do_special_record ---- execute a special boot record.
;input:
;      si ->  the boot record.
;=============================================================================
do_special_record:
	call reset_video_mode
	mov al, [si + struc_bootrecord.type]

	cmp al, SPREC_POWEROFF
	jne .chk_rst
	call power_off

.chk_rst:
	cmp al, SPREC_RESTART
	jne .chk_quit
	call reboot

.chk_quit:
	cmp al, SPREC_QUIT
	jne .chk_bootprev

%ifdef EMULATE_PROG
        mov ax, 0x4c00                          ; exit to dos
        int 0x21                                ;
%else
        int 0x18                                ; return to BIOS
%endif

.chk_bootprev:
	cmp al, SPREC_BOOTPREV
	jne .end
	call boot_prev_mbr

.end:
	ret

;=============================================================================
;do_schedule ---- implement the schedule table
;input:
;      none
;output:
;      default_record set to the scheduled record
;=============================================================================
do_schedule:
        pusha
        call get_realtime
        jc .end

        mov [tmp_schedule_begin], ax
        mov [tmp_schedule_day], dx
        xor cx, cx
        lea si, [boot_records]

.loop_check:
        test word [si + struc_bootrecord.flags], INFOFLAG_SCHEDULED
        jz .check_next

        call check_bootrecord
        jc .check_next

        call get_record_schedule

        cmp [tmp_schedule_begin], ax 
        jb .check_next
        cmp [tmp_schedule_begin], bx
        ja .check_next

        test dx, [tmp_schedule_day]
        jz .check_next

        mov [default_record], cl

.check_next:
        inc cl
        add si, SIZE_OF_BOOTRECORD
        cmp cl, MAX_RECORD_NUM
        jb .loop_check

.end:
        popa
        ret

;=============================================================================
; auth_record_cmd ---- check if a record command can be ran.
; output:
;       cf = 0, auth granted.
;       cf = 1, auth failed.
;=============================================================================
auth_record_cmd:
        cmp byte [good_record_number], 0
        je .failed
        
        call confirm_security_passwd
        jc .failed

        ret

.failed:
        stc
        ret


;=============================================================================
; show_disk_error ---- show the disk error box.
;=============================================================================
show_disk_error:
        mov si, [str_idx.disk_error]
        lea di, [tmp_buffer]
        push di
        call strcpy
        movzx ax, [disk_errno]
        mov cl, 2
        call htoa
        pop si
        call error_box
        ret

;=============================================================================
init_bootmenu_width:
        mov byte [main_win_width], DEF_MAIN_WIN_WIDTH
        mov byte [menu_width], DEF_MENU_WIDTH

	mov al, [bootmenu_style]
	xor cx, cx

	or al, al
	jz .end
	add cl, BM_FLAGS_WIDTH

	cmp al, 1
	je .end
	add cl, BM_NUMBER_WIDTH

	cmp al, 2
	je .end
	add cl, BM_TYPE_WIDTH
.end:
	sub [main_win_width], cl
	sub [menu_width], cl
	mov bx, [str_idx.menu_title]
	add bx, cx
	mov [bootmenu_title_str], bx

        mov al, [main_window_col]
        mov ah, [screen_width]
        sub ah, [main_win_width]
        sub ah, 2
        cmp al, ah
        jbe .no_move

	mov [main_window_col], ah

.no_move:
	ret

;=============================================================================
;save_boot_manager ---- save boot manager to disk.
;input:
;      none
;output:
;      cf = 0 success
;      cf = 1 failed
;=============================================================================
save_boot_manager:
	pusha
	push es
	push ds

;Copy data area to backup seg
	xor si, si
	xor di, di

	push word KNLBACKUP_SEG
	pop es

	mov cx, end_of_sbmk_data
	cld
	rep movsb

;calculate checksum
	push es
	pop ds

	xor si, si
	mov cx, [total_size]
	mov byte [checksum], 0
	call calc_checksum                      ; calculate the checksum.
	neg bl
	mov [checksum], bl

	mov dl, [kernel_drvid]
	lea si, [kernel_sects1]
	mov cx, SBM_SAVE_NBLKS
	xor di, di

	pop ds

.loop_save_blk:
	push cx

	lodsb
	mov cl, al			; number of sectors for this block
	lodsd
	mov ebx,eax			; lba address for this block
        
	mov ax, ( INT13H_WRITE << 8 ) | 1 

	clc
	or cx, cx
	jz .write_end

.loop_write:
	call disk_access
	jc .write_end
        
	add di, SECTOR_SIZE
	inc ebx
	loop .loop_write

	pop cx
	loop .loop_save_blk

	clc
	jmp short .end

.write_end:
	pop cx

.end:
	pop es
	popa
	ret


;=============================================================================
;hide_auto_hides ---- hide all partitions that marked auto hide,
;                     except the focus record.
;input:
;      none
;output:
;      cf = 0 success
;      cf = 1 failed
;=============================================================================
hide_auto_hides:
        movzx cx, byte [good_record_number]
        or cl, cl                               ; if no good record then go to
        jz .end_ok                              ; init directly.
        
        lea di, [good_record_list]
        mov dl, SIZE_OF_BOOTRECORD

; hide all auto hide partitions.
.loop_hide:
        mov al, [di]
        inc di

        cmp ch, [focus_record]                  ; do not hide the focus record.
        je .not_hide

        mul dl
        lea si, [boot_records]
        add si, ax
        mov ax, [si + struc_bootrecord.flags]
        test ax, INFOFLAG_AUTOHIDE
        jz .not_hide
        test ax, INFOFLAG_HIDDEN
        jnz .not_hide
        call toggle_record_hidden
        jc .hidden_error
        call recheck_same_records
        jc .disk_error

.not_hide:
        inc ch
        cmp ch, cl
        jb .loop_hide
        
.end_ok:
        clc
        ret
        
.hidden_error:
        or ax, ax
        jz .cannot_hide
.disk_error:
        call show_disk_error
        jmp short .end

.cannot_hide:
        mov si, [str_idx.toggle_hid_failed]
        call error_box
.end:
        stc
        ret

;=============================================================================
; boot_prev_mbr ---- boot previous MBR
;=============================================================================
boot_prev_mbr:
; read partition table
        push es
        xor ebx, ebx
        mov es, bx
        mov dl, [kernel_drvid]
        mov di, BOOT_OFF
        mov ax, (INT13H_READ << 8) | 0x01
        call disk_access
        pop es
        jc .disk_failed

        push dx
        push di
        call ask_save_changes
        call hide_auto_hides
        call reset_video_mode
        pop di
        pop dx

	call uninstall_myint13h

; copy previous mbr to Boot Offset 0x7c00
        cld
        mov cx, SIZE_OF_MBR
        lea si, [previous_mbr]
        xor ax, ax
        push ax
        pop es
        rep movsb

        push ax
        pop ds

        xor bp, bp                          ; might help some boot problems
        mov ax, BR_GOOD_FLAG                ; boot signature (just in case ...)
        jmp 0:BOOT_OFF                      ; start boot sector

.disk_failed:
        call show_disk_error
.end:
        ret

;=============================================================================
;calc_checksum ---- calculate the checksum of the kernel program.
;input:
;      ds:si -> start of the checksum area
;      cx = checksum size
;output:
;      bl = the checksum value.
;=============================================================================
calc_checksum:
        push cx
        push ax
        push si
        xor bl, bl
        cld
.loop_calc:
        lodsb
        add bl, al
        loop .loop_calc
        pop si
        pop ax
        pop cx
        ret


;==============================================================================
; CD-ROM Boot Stuff
;==============================================================================

%ifndef DISABLE_CDBOOT
;==============================================================================
;choose_cdimg ---- let user choose a cdimg to boot
;input ds:si -> buffer to store boot catalogs
;      cx = number of entries
;output cf =0 ok, ax = user choice
;       cf =1 cancel
;==============================================================================
choose_cdimg:
	pusha

	cmp cl, 8
	jb .no_adjust
	mov cl, 8

.no_adjust:
	mov ax, [str_idx.cdimg_menu_title]
	mov [tmp_cdimg_menu + struc_menu.title], ax
	mov [tmp_cdimg_menu + struc_menu.n_items], cx
	xor ax, ax
	mov [tmp_cdimg_menu + struc_menu.cur_item], ax
	mov word [tmp_cdimg_menu + struc_menu.cmd_tbl], tmp_cmd_table
	mov word [tmp_cdimg_menu + struc_menu.hkey_tbl], tmp_hkey_table
	mov word [tmp_cdimg_menu + struc_menu.str_tbl], tmp_string_table

        mov ax, [color.cmd_menu_winframe]
        mov [tmp_cdimg_menu + struc_menu.win_attr], ax
        mov ax, [color.cmd_menu_normal]
        mov [tmp_cdimg_menu + struc_menu.norm_attr], ax
        mov ax, [color.cmd_menu_focus]
        mov [tmp_cdimg_menu + struc_menu.focus_attr], ax

	push cx

	xor bx, bx
	mov dx, '1 '
	mov di, tmp_menuitem_str

	cld
.loop_init_cdmenu:
	movzx ax, [si + struc_boot_catalog.media_type]
	or al, al
	jz .end_init

	shl al, 1

	push si
	push di
	push cx

	mov si, str_idx.cdimg_menu_strings
	add si, ax
	mov si, [si]

	mov ax, dx
	stosw
	mov ax, '- '
	stosw
	mov cx, 26
	call strncpy
	pop cx
	pop di
	pop si

	mov [tmp_string_table + bx], di
	mov ax, do_cdimg_choose
	mov [tmp_cmd_table + bx], ax

	inc bx
	inc bx
	inc dl
	add di, 32
	add si, SIZE_OF_BOOT_CATALOG
	loop .loop_init_cdmenu

.end_init:
	mov si, tmp_cdimg_menu
	call calc_menusize

	mov ax, [si + struc_menu.win_size]
	mov bx, [screen_width]
	mov cl, 1
	shr bx, cl
	shr ax, cl
	mov cx, 0x7F7F
	and bx, cx
	and ax, cx
	sub bx, ax
	mov [si + struc_menu.win_pos], bx

	xor ax, ax
	dec ax
	mov [cdimg_choice_result], ax

	pop cx
	call popup_menu
	cmp cx, [cdimg_choice_result]
	ja .ok
	stc
.ok:
	popa
	mov ax, [cdimg_choice_result]
	ret
	
do_cdimg_choose:
	mov ax, [si + struc_menu.cur_item]
	mov [cdimg_choice_result], ax
	ret

%endif

%endif
