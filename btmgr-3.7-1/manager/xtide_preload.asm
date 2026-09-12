; Load a checksum-valid option ROM from reserved low disk sectors and run it.
; This runs before SBM enumerates partitions, while the original BIOS can
; still address the reserved first cylinder.

%ifndef XTIDE_ROM_LBA
%define XTIDE_ROM_LBA 64
%endif

%ifndef XTIDE_MAX_SECTORS
%define XTIDE_MAX_SECTORS 32
%endif

preload_xtide:
	pushad
	push ds
	push es

	push cs
	pop ds
	mov byte [xtide_failure_code], '1'
	mov dl, [kernel_drvid]
	mov ebx, XTIDE_ROM_LBA
	push cs
	pop es
	mov di, xtide_header
	call preload_read_sector
	jc .failed

	mov byte [xtide_failure_code], '2'
	cmp word [xtide_header], 0AA55h
	jne .failed
	mov cl, [xtide_header + 2]
	xor ch, ch
	mov byte [xtide_failure_code], '3'
	or cx, cx
	jz near .failed
	mov byte [xtide_failure_code], '4'
	cmp cx, XTIDE_MAX_SECTORS
	ja .failed
	mov [xtide_sector_count], cx

	; Reserve the ROM at the top of conventional memory, below SBM's stack.
	mov ax, cx
	inc ax
	shr ax, 1
	mov bx, ax
	int 12h
	mov byte [xtide_failure_code], '5'
	cmp ax, bx
	jb .failed
	sub ax, bx
	mov dx, ax
	push ds
	mov ax, 40h
	mov ds, ax
	mov [13h], dx
	pop ds
	mov ax, dx
	mov cl, 6
	shl ax, cl
	mov [xtide_segment], ax

	; Load one sector at a time so the original BIOS CHS fallback is safe.
	mov es, ax
	xor di, di
	mov cx, [xtide_sector_count]
	mov ebx, XTIDE_ROM_LBA
.load:
	push cx
	mov dl, [kernel_drvid]
	call preload_read_sector
	mov byte [xtide_failure_code], '6'
	pop cx
	jc .failed
	inc ebx
	add di, SECTOR_SIZE
	jnc .next
	mov ax, es
	add ax, 1000h
	mov es, ax
.next:
	loop .load

	; Option ROM checksums sum to zero across the advertised sector count.
	mov bx, [xtide_segment]
	mov cx, [xtide_sector_count]
	xor dl, dl
.checksum_sector:
	mov ds, bx
	xor si, si
	push cx
	mov cx, SECTOR_SIZE
.checksum_byte:
	lodsb
	add dl, al
	loop .checksum_byte
	pop cx
	add bx, 20h
	loop .checksum_sector
	or dl, dl
	mov byte [xtide_failure_code], '7'
	jnz .failed

	; The checksum loop advanced DS through the ROM. Restore SBM's segment
	; before reading the stored target segment for the far call.
	push cs
	pop ds
	push cs
	push word .rom_return
	push word [xtide_segment]
	push word 3
	retf
.rom_return:
	int 19h
	push cs
	pop ds
	clc
	jmp short .done

.failed:
	push cs
	pop ds
	stc
.done:
	pop es
	pop ds
	popad
	ret

; Read EBX LBA to ES:DI. Prefer EDD but retain a geometry-correct CHS path
; for the old BIOS that must fetch XT-IDE before it is initialized.
preload_read_sector:
	push bx
	push si
	mov [xtide_dap + 8], ebx
	mov dword [xtide_dap + 12], 0
	mov bx, 55AAh
	mov ah, 41h
	int 13h
	jc .chs
	cmp bx, 0AA55h
	jne .chs
	test cl, 1
	jz .chs

	mov si, xtide_dap
	mov word [si], 10h
	mov word [si + 2], 1
	mov [si + 4], di
	mov [si + 6], es
	mov ah, 42h
	int 13h
	jmp short .done

.chs:
	mov ebx, [xtide_dap + 8]
	push di
	mov ah, 08h
	int 13h
	pop di
	jc .done
	; Save the geometry heads now: the divisions below clobber EDX/DH.
	mov [xtide_heads], dh
	mov [xtide_spt], cl
	movzx esi, cl
	and si, 3Fh
	jz .bad_geometry
	mov eax, ebx
	xor edx, edx
	div esi
	inc dx
	push dx
	movzx esi, byte [xtide_heads]
	jz .bad_geometry_pop
	xor edx, edx
	div esi
	cmp ax, 1023
	ja .bad_geometry_pop
	mov dh, dl
	pop cx
	xchg al, ah
	shl al, 6
	or cl, al
	mov ch, ah
	; Record the computed CHS for the debug dump.
	mov [xtide_debug_chs], dh       ; head
	mov [xtide_debug_chs + 1], cl   ; sector (low 6 bits)
	mov [xtide_debug_chs + 2], ch   ; cylinder low
	mov bl, cl
	shr bl, 6
	mov [xtide_debug_chs + 3], bl   ; cylinder high 2 bits
	call preload_debug_chs
	mov dl, [kernel_drvid]
	mov bx, di
	mov ax, 0201h
	int 13h
	jmp short .done

.bad_geometry_pop:
	pop dx
.bad_geometry:
	stc
.done:
	pop si
	pop bx
	ret

; Print the reported geometry and the computed CHS via BIOS INT 10h.
;  XTIDE CHS  SPT=3F HEADS=10  CHS=02/03/00
preload_debug_chs:
	pushad
	push ds
	push cs
	pop ds
	mov si, dbg_pre0
	call dbg_puts
	movzx eax, byte [xtide_spt]
	and al, 3Fh
	call dbg_hex8
	mov si, dbg_pre1
	call dbg_puts
	movzx eax, byte [xtide_heads]
	call dbg_hex8
	mov si, dbg_pre2
	call dbg_puts
	movzx eax, byte [xtide_debug_chs]
	call dbg_hex8
	mov al, '/'
	call dbg_putc
	movzx eax, byte [xtide_debug_chs + 1]
	and al, 3Fh
	call dbg_hex8
	mov al, '/'
	call dbg_putc
	movzx eax, byte [xtide_debug_chs + 2]
	call dbg_hex8
	mov al, '/'
	call dbg_putc
	movzx eax, byte [xtide_debug_chs + 3]
	call dbg_hex8
	mov si, dbg_nl
	call dbg_puts
	pop ds
	popad
	ret

dbg_puts:
	lodsb
	or al, al
	jz .done
	mov ah, 0Eh
	mov bx, 0007h
	int 10h
	jmp dbg_puts
.done:
	ret

dbg_putc:
	mov ah, 0Eh
	mov bx, 0007h
	int 10h
	ret

dbg_hex8:
	push ax
	shr al, 4
	call dbg_hexnybble
	pop ax
	call dbg_hexnybble
	ret

dbg_hexnybble:
	and al, 0Fh
	add al, '0'
	cmp al, '9'
	jbe .write
	add al, 7
.write:
	jmp dbg_putc

dbg_pre0 db "XTIDE CHS SPT=", 0
dbg_pre1 db " HEADS=", 0
dbg_pre2 db " CHS=", 0
dbg_nl   db 13, 10, 0

xtide_sector_count dw 0
xtide_segment      dw 0
xtide_failure_code db '0'
xtide_heads        db 0
xtide_spt          db 0
xtide_debug_chs    db 0, 0, 0, 0
xtide_header       times SECTOR_SIZE db 0
xtide_dap          times 16 db 0
