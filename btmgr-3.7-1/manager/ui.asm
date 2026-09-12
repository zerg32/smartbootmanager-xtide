; asmsyntax=nasm
;
; ui.asm
;
; Functions for User Interface
;
; Copyright (C) 2000, Suzhe. See file COPYING for details.
;

%ifndef HAVE_UI

%ifndef MAIN
%include "ui.h"
%include "utils.asm"
	section .text
%endif

%define HAVE_UI
%define DIRECT_DRAW

%define SCR_BUF_SEG0    0xB800
%define SCR_BUF_SEG1    0xB900
%define SCR_BUF_SEG2    0xBA00
%define SCR_PAGE_SEGS   0x0100

%define SCR_BAK_SEG     0x0900
%define BIOS_DATA_SEG   0x0040

%define BIOS_KEYSTAT_OFF 0x0017

      bits 16

%if 1
;=============================================================================
;draw_string_hl ---- Draw a zero ending string with highlighted characters 
;                    at special position
;input:
;      bl = attribute for normal characters
;           high 4 bit Background color and low 4 bit Foreground color
;      bh = attribute for hightlight characters
;      dh = start row
;      dl = start column
;      ds:si -> the string to be displayed
;output:
;      none
;=============================================================================
draw_string:
draw_string_hl:
        pusha
        push dx
        mov cx,1
        cld
.start:

        lodsb
        or al,al
        jz .end

        cmp al,0x0d                ; if need Change row
        jne .no_cr
        pop dx
        inc dh
        push dx
        jmp short .start

.no_cr:
        cmp al, '~'
        jne .draw_it
        xchg bh, bl
        jmp short .next_char

.draw_it:
        call draw_char

        inc dl
.next_char:
        jmp short .start
.end:
        pop dx
        popa
        ret
;=============================================================================
%endif

%if 0
;=============================================================================
;draw_string ---- Draw a zero ending string at special position
;input:
;      bl = high 4 bit Background color and low 4 bit Foreground color
;      dh = start row
;      dl = start column
;      ds:si -> the string to be displayed
;output:
;      none
;=============================================================================
draw_string_hl:
draw_string:
        pusha
        push dx
        mov cx,1
        cld
.start:

        lodsb
        or al,al
        jz .end

        cmp al,0x0d                ; if need Change row
        jne .no_cr
        pop dx
        inc dh
        push dx
        jmp short .start

.no_cr:
        call draw_char

        inc dl
        jmp short .start
.end:
        pop dx
        popa
        ret
;=============================================================================
%endif

;=============================================================================
;draw_char ---- Draw chars at special position
;input:
;      bl = high 4 bit Background color and low 4 bit Foreground color
;      dh = start row
;      dl = start column
;      al = the char to be displayed
;      cx = repeat times
;output:
;      none
;=============================================================================
draw_char:
%ifdef DIRECT_DRAW                            ; directly write to video buffer
        pusha
        push es
        mov ah, bl
        push ax

        mov ax, [screen_bufseg]
        mov es, ax
        mov al, [screen_width]
        mul dh
        xor dh, dh
        add ax, dx
        shl ax, 1
        mov di, ax

        pop ax
        rep stosw
        pop es
        popa
%else
        push bx
        mov ah,2
        mov bh, [screen_page]
        int 0x10
        mov ah,0x09
        int 0x10
        pop bx
%endif
        ret
;=============================================================================

;=============================================================================
;clear_screen ---- clear a screen area
;input:
;      ch = row of top left corner
;      cl = column of top left corner
;      dh = row of bottom right corner
;      dl = column of bottom right corner
;      bh = attribute
;output:
;      none
;=============================================================================
clear_screen:
        pusha
;%ifdef DIRECT_DRAW
        push es
        mov ah, bh
        mov al, ' '
        mov bx, [screen_bufseg]
        mov es, bx

        sub dl, cl
        inc dl

.loop_fill:
        push cx
        push ax

        mov al, [screen_width]
        mul ch
        xor ch, ch
        add ax, cx
        shl ax, 1
        mov di, ax
        mov cl, dl

        pop ax
        rep stosw
        pop cx
        inc ch
        cmp ch, dh
        jbe .loop_fill

        pop es
;%else
;        mov ax, 0x0600
;        int 0x10
;%endif
        popa
        ret

;=============================================================================
;read_scrchar ---- read a char from the screen
;input:
;       dh = row
;       dl = column
;output:
;       ax = char with attribute
;=============================================================================
read_scrchar:
%ifdef DIRECT_DRAW
        push ds
        push dx
        push si

        mov al, [screen_width]
        mul dh
        xor dh, dh
        add ax, dx
        shl ax, 1
        mov si, ax

        mov ax, [screen_bufseg]
        mov ds, ax

        lodsw
        pop si
        pop dx
        pop ds
%else
        push bx
        mov bh, [screen_page]
        mov ah,0x02
        int 0x10
        mov ah,0x08
        int 0x10
        pop bx
%endif
        ret

%if 0
;=============================================================================
;draw_string_tty ---- Draw a string ending by zero ( tty mode )
;input:
;      ds:si -> string
;output:
;      none
;=============================================================================
draw_string_tty:
        pusha
        cld
.draw1:
        lodsb
        or al, al
        jz .end
        mov bx,7
        mov ah,0x0e
        int 0x10
        jmp .draw1
.end:
        popa
        ret
;=============================================================================
%endif

;=============================================================================
;draw_window ---- Draw a framed window
;input:
;      ch = row of top left corner
;      cl = column of top left corner
;      dh = row of bottom right corner
;      dl = column of bottom right corner
;      bl = high 4 bit Background color and low 4 bit Foreground color
;      bh = title attribute (define same as bl)
;      ds:si -> title
;output:
;      none
;=============================================================================
draw_window:
        pusha
        mov [ui_tmp.left_col], cx          ;
        mov [ui_tmp.right_col], dx         ; save window pos and attribute
        mov [ui_tmp.frame_attr], bx        ;

;Clear frame background
        xchg bh,bl
        call clear_screen

        xchg dx,cx
        mov cx,1

;Draw four corners
        cmp byte [draw_frame_method], 2             ; check draw method.
        jb .draw_top_corner_as_frame
        mov bl, [ui_tmp.title_attr]
        jmp short .draw_top_corner
.draw_top_corner_as_frame:
        mov bl, [ui_tmp.frame_attr]
.draw_top_corner:
        mov al, [frame_char.tl_corner]
        call draw_char

        mov dl, [ui_tmp.right_col]
        mov al, [frame_char.tr_corner]
        call draw_char

        mov bl, [ui_tmp.frame_attr]
        mov dh, [ui_tmp.bottom_row]
        mov al, [frame_char.br_corner]
        call draw_char
  
        mov dl, [ui_tmp.left_col]
        mov al, [frame_char.bl_corner]
        call draw_char

;Draw bottom horizontal line
        inc dl
        mov cl, [ui_tmp.right_col]
        sub cl, dl
        mov al, [frame_char.bottom]
        call draw_char

;Draw top horizontal line
        cmp byte [draw_frame_method], 1             ; check draw method.
        jb .draw_top_line_as_frame
        mov bl, [ui_tmp.title_attr]
        jmp short .draw_top_line
.draw_top_line_as_frame:
        mov bl, [ui_tmp.frame_attr]
.draw_top_line:
        mov dh, [ui_tmp.top_row]
        mov al, [frame_char.top]
        call draw_char

;Draw title
        call strlen
        or cx,cx
        jz .no_title

        mov al, [ui_tmp.right_col]
        sub al, [ui_tmp.left_col]
        sub al, cl
        inc al
        shr al,1
        mov dl, [ui_tmp.left_col]
        add dl,al
        mov dh, [ui_tmp.top_row]

        mov bl, [ui_tmp.title_attr]
        call draw_string

.no_title:

;Draw vertical line
        mov bl, [ui_tmp.frame_attr]
        mov dh, [ui_tmp.top_row]
        inc dh

        mov cx,1

.draw_vert_line:
        mov al, [frame_char.left]
        mov dl, [ui_tmp.left_col]
        call draw_char
        mov al, [frame_char.right]
        mov dl, [ui_tmp.right_col]
        call draw_char

        inc dh
        cmp dh, [ui_tmp.bottom_row]
        jb .draw_vert_line

;Draw shadow
        mov bl, 0x08
        mov ch, [ui_tmp.bottom_row]
        mov cl, [ui_tmp.left_col]
        inc ch
        inc cl
        inc cl
        mov dh, [ui_tmp.bottom_row]
        mov dl, [ui_tmp.right_col]
        inc dh
        call draw_shadow
        mov ch, [ui_tmp.top_row]
        mov cl, [ui_tmp.right_col]
        inc ch
        inc cl
        inc dl
        inc dl
        call draw_shadow

        popa
        ret

;=============================================================================

;=============================================================================
;draw_shadow ---- Draw shadow block
;input:
;      ch = row of top left corner
;      cl = column of top left corner
;      dh = row of bottom right corner
;      dl = column of bottom right corner
;      bl = high 4 bit Background color and low 4 bit Foreground color
;output:
;      none
;=============================================================================
draw_shadow:
        pusha
.loop_row:
        push dx
.loop_col:
        push cx
        mov cx,1
        call read_scrchar
        call draw_char
        pop cx
        dec dl
        cmp cl, dl
        jbe .loop_col
        pop dx
        dec dh
        cmp ch, dh
        jbe .loop_row

        popa
        ret
;=============================================================================

;=============================================================================
;message_box ---- Draw a message box
;input:
;      ds:si -> title
;      ds:di -> message
;      al = message attribute
;      bh = title attribute
;      bl = frame attribute
;      dh = box height
;      dl = box width
;output:
;      none
;=============================================================================
message_box:
        pusha
        push ax
;Calculate Window position
	call center_window

;Draw window and message
        push cx
        call draw_window
        pop dx
        add dh, 2
        add dl, 3
        xchg si,di
        pop bx
        or si,si
        jz .end
        call draw_string
.end:
        popa
        ret
;=============================================================================


;=============================================================================
;input_box ---- draw a input box and input a string
;input:
;      ah = input method ( 0 = normal, 1 = security )
;      al = message attribute
;      bh = title attribute
;      bl = frame attribute
;      ch = input area length
;      cl = max input length
;      ds:si -> message ( no more than one line )
;      es:di -> buffer to store input string
;output:
;      cf = 0 , ah = 0 ok, ch = number of inputed character
;      cf = 1 , ah != 0 cancel, ch = 0
;=============================================================================
input_box:
        or ch, ch
	jnz .go_input
	mov ch, cl
.go_input:
	push ax
        push cx

        mov dh, [size.box_height]               ; dh = box height
        inc dh
        mov dl, ch                              ; dl = box width
        add dl, [size.box_width]

        call strlen                             ; box width = msg length +
        push cx                                 ; max input lenght + 4
        add dl, cl

	call center_window
        
        push cx                                 ; save top left position
        push si
        mov si, [str_idx.input]                 ; get the title of input box
        call draw_window                        ;
        pop si
        pop dx
        
        add dl, 2                               ;
        add dh, 2                               ; display the input message
        mov bl, al                              ;
        call draw_string                        ;

        pop cx
        add dl, cl
        
        pop cx
        pop ax
        mov bh, ah
        mov bl, 0x0F
        call input_string
        ret
;=============================================================================


;=============================================================================
; move a window to center of the screen.
;input:
;	dh = window high
;	dl = window width
;output:
;	cx = upper left corner
;	dx = bottom right corner
;=============================================================================
center_window:
	mov ch, [screen_height]                 ; calculate the coordinate
	sub ch, dh                              ; of input box.
	shr ch, 1                               ; ch = top left row
	mov cl, [screen_width]                  ; cl = top left column
	sub cl, dl                              ; dh = bottom right row
	shr cl, 1                               ; dl = bottom right column
	add dh, [screen_height]                 ;
	shr dh, 1                               ;
	dec dh
	add dl, [screen_width]                  ;
	shr dl, 1                               ;
	ret

;=============================================================================
;input_string ---- input a string from keyboard (zero ending)
;input:
;      bh = input type ( 0=normal, 1=security )
;      bl = text attribute
;      ch = input area length
;      cl = max length
;      dh = start row
;      dl = start column
;      es:di -> buffer
;output:
;      cf = 0, ah = 0 ok, ch = number of inputed character
;      cf = 1, ah != 0 cancel, ch = 0
;=============================================================================
input_string:
        push di
        push si
        cld

	mov [ui_input_tmp.arealen], ch
	mov [ui_input_tmp.maxlen], cl
	mov [ui_input_tmp.areapos], dx

	xor ax, ax
	mov [ui_input_tmp.startp], ax
	mov [ui_input_tmp.curp], ax

        call show_cursor

	jmp .end_cur

.loop_input:
        call set_cursor                         ; set cursor position
	call .draw_input_area			; draw input area

        xor ah,ah
        call bioskey

        cmp ax, kbBack
        jz .back_space
        cmp ax, kbDel
        jz .delete
	cmp ax, kbLeft
	jz .left_cur
	cmp ax, kbRight
	jz .right_cur
	cmp ax, kbEnd
	jz .end_cur
	cmp ax, kbHome
	jz .home_cur
        cmp ax, kbEsc
        jz near .cancel
        cmp ax, kbEnter
        jz near .end_input
	
        or al,al
        jz .loop_input

;input a char
;check string len
	call .get_strlen
	cmp cx, [ui_input_tmp.maxlen]
	jae .loop_input

	mov cl, [ui_input_tmp.curp]
	call .insert_char
	inc byte [ui_input_tmp.curp]

	jmp short .post_input

;delete forward char
.back_space:
	call .get_strlen
	or cx, cx
	jz .loop_input
	cmp byte [ui_input_tmp.curp], 0
	jz .loop_input
	dec byte [ui_input_tmp.curp]
	mov cl, [ui_input_tmp.curp]

	call .delete_char
	jmp short .post_input

;delete current char
.delete:
	call .get_strlen
	or cx, cx
	jz near .loop_input
	mov cl, [ui_input_tmp.curp]

	call .delete_char
	jmp short .post_input

.right_cur:
	call .get_strlen
	cmp cl, [ui_input_tmp.curp]
	jbe near .loop_input

	inc byte [ui_input_tmp.curp]
	jmp short .post_input

.left_cur:
	cmp byte [ui_input_tmp.curp], 0
	jz near .loop_input

	dec byte [ui_input_tmp.curp]
	jmp short .post_input

.end_cur:
	call .get_strlen
	mov [ui_input_tmp.curp], cl
	jmp short .post_input

.home_cur:
	mov byte [ui_input_tmp.curp], 0

.post_input:
	mov ax, [ui_input_tmp.curp]
	mov cx, [ui_input_tmp.startp]
	cmp cx, ax
	jb .st_below_cur
	mov [ui_input_tmp.startp], ax
	jmp short .adjust_cur

.st_below_cur:
	sub ax, cx
	cmp ax, [ui_input_tmp.arealen]
	jbe .adjust_cur
	sub ax, [ui_input_tmp.arealen]
	add [ui_input_tmp.startp], ax

.adjust_cur:
	mov dl, [ui_input_tmp.areapos]
	add dl, [ui_input_tmp.curp]
	sub dl, [ui_input_tmp.startp]
	jmp .loop_input

.end_input:
	call .get_strlen
	mov ch, cl
	mov cl, [ui_input_tmp.maxlen]
	clc
        jmp short .end
.cancel:
        xor ch,ch
        stc
.end:
	pushf
        call hide_cursor
	popf
        pop si
        pop di
        ret

;=============================================================================
; es:di -> buffer
; al = char 
; cl = position
;=============================================================================
.insert_char:
	pusha

	xor ch, ch
	mov si, di
	add si, cx

	mov di, ui_input_tmp.tmpbuf
	push di
	push ds

	push si
	push es

	push ds				;
	push es				; es <-> ds
	pop ds				;
	pop es

	mov cl, 255
	call strncpy

	pop es
	pop di
	stosb

	mov cl, 255
	pop ds
	pop si
	call strncpy

	popa
	ret

;=============================================================================
; es:di -> buffer
; cl = position
;=============================================================================
.delete_char:
	pusha
	push ds
	push es
	pop ds
	xor ch, ch
	add di, cx
	mov si, di
	cmp byte [si], 0
	jz .delete_end
	inc si
	mov cl, 255
	call strncpy
.delete_end:
	pop ds
	popa
	ret

;=============================================================================
.draw_input_area:
	pusha
	movzx cx, byte [ui_input_tmp.arealen]
	mov dx, [ui_input_tmp.areapos]
        mov al, 0x20
        call draw_char

	push ds
	push es
	pop ds

	mov si, di
	add si, [ui_input_tmp.startp]

.dia_loop:
	lodsb
	or al, al
	jz .dia_end
	or bh, bh
	jz .dia_norm
	mov al, '*'
.dia_norm:
	push cx
	mov cl, 1
	call draw_char
	pop cx
	inc dl
	loop .dia_loop

.dia_end:
	pop ds
	popa
	ret

;=============================================================================
.get_strlen:
	push ds
	push es
	pop ds
	mov si, di
	call strlen
	pop ds
	ret
;=============================================================================


;=============================================================================
;set_video_mode ---- Set the Alphabet Video Mode
;input:
;      al = 0 , set screen resolution to 90x25,
;           otherwise set to 80x25
;      bl = character bit size ( 8 or 9 )
;      cx = fonts number
;      es:bp -> fonts data
;output:
;      none
;=============================================================================
BIOS_CRT_COLS        equ 0x4A
BIOS_ADDR_6845       equ 0x63

set_video_mode:
        push es
        push bx
        push ax

        call reset_video_mode

;Establish CRTC vertical timing and cursor position in character matrix
;and set user fonts table
        or cx, cx
        jz .set_res                          ; no font data
        or bp, bp
        jz .set_res                          ; no font data
        
.loop_set_fonts:                             ; set user defined chars
        push cx
        xor cx,cx
        inc cl
        movzx dx, byte [es:bp]
        inc bp
        mov ax,0x1100
        mov bx,0x1000
        int 0x10
        pop cx
        add bp, 16
        loop .loop_set_fonts

.set_res:
        mov byte [screen_width], 80
        mov byte [screen_height], 25

        mov ax,0x40
        mov es,ax
        pop ax

        or al,al
        jnz .skip_res_set

        mov dx,[es:BIOS_ADDR_6845]                   ; CRTC I/O port

;Enable I/O writes to CRTC registers
        mov al,0x11
        out dx,al
        inc dx
        in al,dx
        dec dx
        mov ah,al
        mov al,0x11
        push ax
        and ah,01111111b
        out dx,ax

;Establish CRTC horizontal timing
        lea si, [VideoHorizParams]

        mov cx,7
        
        cld
.set_CRTC:
        lodsw
        out dx,ax
        loop .set_CRTC

;write-protect CRTC registers
        pop ax
        out dx,ax

;Program the Sequencer and Attribute Controller for 9 dots per character
        
        mov dx, 0x3c4
        mov ax, 0x0100
        cli
        out dx,ax

        mov ax,0x0101
        out dx,ax
        mov ax,0x0300
        out dx,ax
        sti

        mov bx,0x0013
        mov ax,0x1000
        int 0x10

        mov byte [screen_width], 90
.skip_res_set:

;Program the Attribute Controller for 8- or 9-bit character codes
        mov ax,0x1000
        mov bx,0x0f12
        pop dx
        cmp dl,8
        je .svm01
        mov bh,7
.svm01:
        int 0x10

;Update video BIOS data area
        mov al,[screen_width]
        mov [es:BIOS_CRT_COLS],al

;Set background highlight attribute
        pop es
        mov ax,0x1003
        xor bl,bl
        int 0x10
        call hide_cursor

        ret
;=============================================================================

;=============================================================================
;set_cursor ---- move the cursor
;input:
;       dh = row
;       dl = column
;=============================================================================
set_cursor:
	pusha
        mov bh, [screen_page]
        mov ah, 0x02
        int 0x10
	popa
        ret

;=============================================================================
;hide_cursor ---- Hide the cursor
;input:
;      none
;output:
;      none
;=============================================================================
hide_cursor:
        pusha
        mov ah,1
        mov cx,0x6f00
        int 0x10
        popa
        ret
;=============================================================================

;=============================================================================
;show_cursor ---- Show the cursor
;input:
;      none
;output:
;      none
;=============================================================================
show_cursor:
        pusha
        mov ah,1
        mov cx,0x0e0f
        int 0x10
        popa
        ret
;=============================================================================

;=============================================================================
;reset_video_mode ---- Reset the VideoMode
;input:
;      none
;output:
;      none
;=============================================================================
reset_video_mode
        pusha
        mov ax,3
        int 0x10
        call show_cursor
        popa
        ret
;=============================================================================


;=============================================================================
;draw_icon ---- Draw a icon at special position
;input:
;      dh = start row
;      dl = start column
;      ch = number of row
;      cl = number of column
;      ds:si -> icon data , which is a two dim word array, each elements
;               indicates a char. high byte is the attribute, low byte is
;               is the char code.
;output:
;      none
;=============================================================================
draw_icon:
        or si, si
        jz .end
        or cx, cx
        jz .end
        
        pusha
        cld
.loop_row:
        push dx
        push cx
.loop_col:
        push cx
        mov cx,1
        lodsw
        xchg ah,bl
        call draw_char
        
        pop cx
        inc dl
        dec cl
        jnz .loop_col
        
        pop cx
        pop dx
        inc dh
        dec ch
        jnz .loop_row

        popa
.end:
        ret
;=============================================================================

;=============================================================================
;draw_background ---- Draw the background using specified icon
;input:
;      bh = background color when no icon
;      cx = icon size (ch = row, cl = col)
;      ds:si -> icon data , which is a two dim word array, each elements
;               indicates a char. high byte is the attribute, low byte is
;               is the char code.
;output:
;      none
;=============================================================================
draw_background:
        pusha
        or si,si
        jnz .normal_bg

;no icon. clear background.
        xor cx,cx
        mov dh,[screen_height]
        mov dl,[screen_width]
        dec dh
        dec dl
        call clear_screen
        popa
        ret

.normal_bg:
        xor dx,dx

.loop_row:
        push dx
.loop_col:
        call draw_icon
        add dl, cl
        cmp dl, [screen_width]
        jb .loop_col
        pop dx
        add dh, ch
        cmp dh, [screen_height]
        jb .loop_row
        popa
        ret
;=============================================================================

;=============================================================================
;turnon_scrolllock ---- turn on the scroll lock key
;input: none
;output: none
;=============================================================================
turnon_scrolllock:
        pusha
        push es
        mov ax, BIOS_DATA_SEG
        mov es, ax
        mov di, BIOS_KEYSTAT_OFF
        or byte [es:di], kbScrollMask
        pop es
        popa
        ret

;=============================================================================
;turnoff_scrolllock ---- turn off the scroll lock key
;input: none
;output: none
;=============================================================================
turnoff_scrolllock:
        pusha
        push es
        mov ax, BIOS_DATA_SEG
        mov es, ax
        mov di, BIOS_KEYSTAT_OFF
        and byte [es:di], ~ kbScrollMask
        pop es
        popa
        ret

%if 1
;=============================================================================
;lock_screen ---- lock the screen, any output will be stored in SCR_BAK_SEG
;=============================================================================
lock_screen:
        mov al, [screen_page]
        xor al, 0x02
        mov word [screen_bufseg], SCR_BUF_SEG0
        or al, al
        jz .set_seg0
        mov word [screen_bufseg], SCR_BUF_SEG2
.set_seg0:
        mov [screen_page], al
        ret

;=============================================================================
;unlock_screen ---- unlock the screen, copy SCR_BAK_SEG to SCR_BUF_SEG
;=============================================================================
unlock_screen:
        mov ah, 0x05
        mov al, [screen_page]
        int 0x10
        ret

%endif


%if 1
;=============================================================================
; Command menu functions
;=============================================================================

;=============================================================================
;calc_menusize ---- calc the size of a menu 
;input:
;     ds:si - > pointer to struc_menu
;output: 
;     none
;=============================================================================
calc_menusize:
        pusha
        mov cx, [si + struc_menu.n_items]     ; number of items
        mov bx, [si + struc_menu.str_tbl]     ; string table

        mov dh, cl                            ; menu height
        mov [si + struc_menu.menu_size + 1], dh
        add dh, 2                             ; menu window height
        mov [si + struc_menu.win_size + 1], dh

        push si

;calculate the width of menu area
        xor dl, dl
.loop_cal_strlen:
        mov si, [bx]
        push cx
        call strlen_hl
        cmp dl, cl
        ja .cnt_cal_strlen
        mov dl, cl
.cnt_cal_strlen:
        pop cx
        add bx, 2                             ; point to the next item
        loop .loop_cal_strlen

        pop si
        add dl, 2
        mov [si + struc_menu.menu_size], dl
        add dl, 2
        mov [si + struc_menu.win_size], dl
        popa
        ret

;=============================================================================
;draw_menu_item ---- draw a menu item on the screen
;input:
;     bl = attribute for normal characters 
;     bh = attribute for highlighted characters
;     cx = item number to be displayed
;     dh = start row
;     dl = start column
;     ds:si - > pointer to struc_menu
;=============================================================================
draw_menu_item:
        pusha
        add dh, cl
        shl cx, 1
        mov ax, [si + struc_menu.menu_size]
        mov si, [si + struc_menu.str_tbl]
        add si, cx
        mov si, [si]
        movzx cx, al
        mov al, ' '
        call draw_char
        inc dl
        call draw_string_hl
        popa
        ret

;=============================================================================
;draw_menu ---- draw a menu on the screen
;input:
;     ds:si - > pointer to struc_menu
;output:
;     none
;=============================================================================
draw_menu:
        pusha
        mov ax, [si + struc_menu.cur_item]
        mov cx, [si + struc_menu.n_items]
        mov dx, [si + struc_menu.win_pos]

        add dx, 0x0101
        dec cx

.loop_draw:
        cmp ax, cx
        je .focus_item
        mov bx, [si + struc_menu.norm_attr]
        jmp short .draw_item
.focus_item:
        mov bx, [si + struc_menu.focus_attr]
.draw_item:
        call draw_menu_item
        or cx, cx
        jz .end
        dec cx
        jmp short .loop_draw

.end:
        popa
        ret

;=============================================================================
;draw_menu_box ---- draw a menu box on the screen
;input:
;     ds:si - > pointer to struc_menu
;output:
      none
;=============================================================================
draw_menu_box:
      pusha
      mov cx, [si + struc_menu.n_items]     ; number of items
      mov bx, [si + struc_menu.str_tbl]     ; string table

      mov dx, [si + struc_menu.win_size]    ; the size of menu box

      mov cx, [si + struc_menu.win_pos]     ; menu position
      mov bx, [si + struc_menu.win_attr]    ; window attribute

      add dx, cx                            ; dx = bottom right corner
      sub dx, 0x0101

      mov si, [si + struc_menu.title]
      call draw_window                      ; draw menu box
      popa
      ret

;=============================================================================
;popup_menu ---- popup a menu on the screen and wait user input
;input:
;     al = menu mode, 0 = mod, 1=non-mod
;     ds:si - > pointer to struc_menu
;output: 
;     none
;=============================================================================
popup_menu:
        pusha

	mov [tmp_menu_mod], al

.loop_showmnu:
        call draw_menu_box

.loop_input:
        call draw_menu

.loop_rdkbd:
	call get_key

.have_key:
        mov dx, ax

        push si
        mov bx, [si + struc_menu.mnu_cmd_tbl]
        mov cx, [si + struc_menu.mnu_cmd_num]
        mov si, [si + struc_menu.mnu_hkey_tbl]
        cld
	or cx, cx

	jz .chk_other_key

.loop_search_mnucmd:
        lodsw
        cmp dx, ax
        je .found_mnucmd
        add bx, 2
        loop .loop_search_mnucmd
        jmp short .chk_other_key

.found_mnucmd:
        pop si                        ; restore menu pointer
        push si
        push dx
        call word [bx]
        pop dx

.chk_other_key:
        pop si

        cmp dx, kbUp
        je .focus_up
        cmp dx, kbEnhUp
        je .focus_up
        cmp dx, kbDown
        je .focus_down
        cmp dx, kbEnhDown
        je .focus_down
        cmp dx, kbEnter
        je .focus_run
        cmp dx, kbEnhEnter
        je .focus_run
        cmp dx, kbEsc
        je .exit
        cmp dx, kbTab
        je .exit

        jmp short .chk_cmd_hkeys

.focus_up:
        mov ax, [si + struc_menu.cur_item]
        or ax, ax
        ja .up_ok
        mov ax, [si + struc_menu.n_items]
.up_ok:
        dec ax
        mov [si + struc_menu.cur_item], ax
        jmp short .loop_input

.focus_down:
        mov ax, [si + struc_menu.cur_item]
        inc ax
        cmp ax, [si + struc_menu.n_items]
        jb .down_ok
        xor ax, ax
.down_ok:
        mov [si + struc_menu.cur_item], ax
        jmp short .loop_input

.focus_run:
        mov ax, [si + struc_menu.cur_item]
        mov bx, [si + struc_menu.cmd_tbl]
        push si
        shl ax, 1
        add bx, ax
        call word [bx]
        pop si
        jmp short .chk_post

.chk_cmd_hkeys:
        push si
        mov bx, [si + struc_menu.cmd_tbl]
        mov cx, [si + struc_menu.n_items]
        mov si, [si + struc_menu.hkey_tbl]
        cld

.loop_search_cmd:
        lodsw
        cmp dx, ax
        je .found_cmd
        add bx, 2
        loop .loop_search_cmd
	pop si
        jmp .loop_showmnu

.found_cmd:
	pop si
	push si
        call word [bx]
	pop si

.chk_post:
        mov bx, [si + struc_menu.post_req_cmd]
        or bx, bx
        jnz .call_post
        jmp short .check_mod

.call_post:
        push si
        call bx

.end_chk:
        pop si

.check_mod:
	cmp byte [tmp_menu_mod], 0
	jz near .loop_showmnu

.exit:
        popa
        ret

%endif

%ifndef MAIN
get_key:
	mov ah, [keyboard_type]
	call bioskey
	ret
%endif

;=============================================================================
; Data Area
;=============================================================================
VideoHorizParams dw 0x6B00,0x5901,0x5A02,0x8E03,0x5F04,0x8C05,0x2D13 ;8-wide

screen_width      db     90
screen_height     db     25

screen_bufseg     dw     SCR_BUF_SEG0
screen_page       db     0

%ifndef MAIN

; how to draw window frame
keyboard_type       db  0x10       ; keyboard type, 0x10 = enhanced keyboard
draw_frame_method   db  0          ; = 0 means draw all frame using frame attr.
                                   ; = 1 means draw top horizontal line using
                                   ;     title attr.
                                   ; = 2 means draw top corner and horizontal
                                   ;     line using title attr.
frame_char:
.top             db     0x020
.bottom          db     0x0CD
.left            db     0x0BA
.right           db     0x0BA
.tl_corner       db     0x0C9               ; top left corner
.tr_corner       db     0x0BB               ; top right corner
.bl_corner       db     0x0C8               ; bottom left corner
.br_corner       db     0x0BC               ; bottom right corner

size:
.box_height      db  4
.box_width       db  5

str_idx:
.input          dw  string.input

string:
.input          db     'Input',0

	section .bss
%include "tempdata.asm"

%endif

%endif	;End of HAVE_UI
