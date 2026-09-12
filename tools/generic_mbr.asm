; Plain generic active-partition MBR.
;
; Classic DOS/GRUB-style MBR: find the single active primary partition, load
; its first sector to 0x0000:0x7C00 and jump to it.  It is deliberately free of
; any Syslinux-specific handling (the previous MBR carried over an "XFSB"
; magic check from the working Syslinux CF card), so the load path is purely:
;     MBR -> active partition's boot sector -> SBM loader shim.
;
; Runs in place at 0x0000:0x7C00.  Uses EDD (INT13 AH=42) when the BIOS
; supports it, otherwise a geometry-correct LBA->CHS read (INT13 AH=02) using
; the same CHS packing proven to boot on the real 486 hardware.
;
; Build:    nasm -f bin -o generic_mbr.bin generic_mbr.asm
; Size:     must be <= 440 bytes (make_cf_image copies the first 440 bytes to
;           MBR sector offset 0, then writes the 4-entry partition table and
;           the 0x55AA signature itself).

    BITS 16
    ORG 0x7C00

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov [bootdrive], dl         ; remembered for later reads

    ; ---- detect EDD (INT13 AH=41) ----
    mov byte [use_edd], 0
    mov ah, 0x41
    mov bx, 0x55AA
    xor cx, cx
    xor dh, dh
    stc
    int 0x13
    jc .full
    cmp bx, 0xAA55
    jne .full
    shr cx, 1
    jae .full
    mov byte [use_edd], 1
.full:

    ; ---- find the single active (0x80) primary partition ----
    mov bx, 0x7DBE
    mov cx, 0x0004
    xor dx, dx                  ; DX = active count
    mov si, 0x7DBE              ; SI = candidate active entry
.scan:
    cmp byte [bx], 0x80
    jne .next
    inc dx
    mov si, bx
.next:
    add bx, 0x10
    loop .scan

    cmp dx, 1
    je .one
    ja .multi
    jmp .missing

.one:
    ; SI = one active entry. Load its first sector (absolute start LBA at +8).
    mov eax, [si + 8]
    call read_sector
    jc .error

    ; ---- plain MBR: verify signature, then jump to the loaded boot sector ----
    cmp word [0x7DFE], 0xAA55
    jne .error
    mov dl, [bootdrive]
    jmp 0x0000:0x7C00

.multi:
    mov si, multi_msg
    call print
    jmp .halt

.missing:
    mov si, missing_msg
    call print
    jmp .halt

.error:
    mov si, error_msg
    call print
.halt:
    cli
    hlt
    jmp .halt

; ---------------------------------------------------------------- read -------
; read_sector: load one 512-byte sector at LBA (in EAX) to 0x0000:0x7C00.
; Sets CF on error.  Uses EDD if available, else BIOS-geometry CHS.
read_sector:
    cmp byte [use_edd], 0
    je .chs
    ; ---- EDD path (INT13 AH=42) ----
    mov si, dap
    mov word [si], 0x10         ; DAP size
    mov word [si+2], 1          ; count = 1
    mov word [si+4], 0x7C00     ; buffer offset
    mov word [si+6], 0x0000     ; buffer segment
    mov [si+8], eax             ; LBA low
    mov dword [si+12], 0        ; LBA high
    mov dl, [bootdrive]
    mov ah, 0x42
    int 0x13
    ret
.chs:
    ; ---- geometry (INT13 AH=08); preserve LBA (EAX) across the call ----
    push eax
    mov dl, [bootdrive]
    mov ah, 0x08
    int 0x13
    pop eax
    jc .fail
    and cx, 0x3F
    jz .cfail
    movzx ecx, cx               ; ECX = SPT
    mov [spt], ecx
    test dh, dh
    jnz .have_heads
    mov dh, 255
.have_heads:
    mov [heads], dh
    ; ---- LBA (EAX) -> CHS ----
    ;   sector-1 = LBA % SPT ; track = LBA / SPT
    ;   head = track % heads ; cylinder = track / heads
    xor edx, edx
    div dword [spt]             ; EAX=track, EDX=sector-1
    push edx                    ; save sector-1
    xor edx, edx
    movzx ecx, byte [heads]
    div ecx                     ; EAX=cylinder, EDX=head
    mov bh, dl                  ; BH = head
    pop cx                      ; CX = sector-1 (CL=value, CH=0)
    mov dx, ax                  ; DX = cylinder
    mov ch, dl                  ; CH = cylinder low 8 bits
    mov ax, dx                  ; AX = cylinder
    shr ax, 2
    and al, 0xC0                ; AL = (cyl>>2) & 0xC0  (cylinder bits 8-9)
    or cl, al                   ; CL = sector-1 | cylinder high bits
    mov dh, bh                  ; DH = head
    inc cx                      ; CL = sector (1-based)
    ; AH=02 read, AL=1; buffer 0:7C00
    mov ax, 0x0201
    mov dl, [bootdrive]
    mov bx, 0x7C00
    int 0x13
    ret
.cfail:
    stc
.fail:
    ret

; ---------------------------------------------------------------- printing --
print:
.loop:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    jmp .loop
.done:
    ret

; ---------------------------------------------------------------- messages --
missing_msg  db "Missing operating system.", 13, 10, 0
multi_msg    db "Multiple active partitions.", 13, 10, 0
error_msg    db "Operating system load error.", 13, 10, 0

; ---------------------------------------------------------------- globals ----
bootdrive    db 0x80
use_edd      db 0
spt          dd 63
heads        db 16
             align 8, db 0
dap          times 16 db 0

    times 440-($-$$) db 0
