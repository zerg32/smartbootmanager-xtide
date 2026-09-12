; Diagnostic payload loaded by debug_mbr.asm for validating the shimless layout.
;
; Reports the BIOS drive number, EDD availability, and AH=08 geometry. It then
; reads and validates the future SBM kernel at LBA 1, XT-IDE at LBA 128, and a
; temporary normal SBM loader at LBA 63. After a key press it executes that
; loader, which loads the kernel from LBA 1 and continues normally.
;
; This payload occupies two reserved sectors starting at LBA 39.

    BITS 16
    ORG 0x8000

%define LOAD_BUFFER 0x7C00
%define SBM_KERNEL_LBA 1
%define DEBUG_LOADER_LBA 63
%define XTIDE_ROM_LBA 128
%define SBMK_MAGIC 0x4B4D4253
%define SBML_MAGIC 0x4C4D4253

    db "SDBG"

start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    cld
    mov [boot_drive], dl
    mov si, banner
    call puts
    mov si, drive_msg
    call puts
    mov al, [boot_drive]
    call hex8

    ; Query the geometry used by legacy INT 13h CHS calls.
    mov dl, [boot_drive]
    mov ah, 0x08
    int 0x13
    jc fatal_geometry
    mov al, cl
    and al, 0x3F
    xor ah, ah
    mov [spt], ax
    xor ax, ax
    mov al, dh
    inc ax
    mov [heads], ax
    xor ax, ax
    mov al, cl
    and ax, 0x00C0
    shl ax, 2
    mov al, ch
    inc ax
    mov [cylinders], ax

    ; Detect EDD unless this build deliberately forces the CHS path.
    mov byte [use_edd], 0
%ifndef FORCE_CHS
    mov dl, [boot_drive]
    mov ah, 0x41
    mov bx, 0x55AA
    stc
    int 0x13
    jc .edd_done
    cmp bx, 0xAA55
    jne .edd_done
    test cx, 1
    jz .edd_done
    mov byte [use_edd], 1
.edd_done:
%endif

    mov si, edd_msg
    call puts
    mov al, 'N'
    cmp byte [use_edd], 0
    je .edd_print
    mov al, 'Y'
.edd_print:
    call putc
    mov si, geom_msg
    call puts
    mov ax, [cylinders]
    call hex16
    mov al, '/'
    call putc
    mov ax, [heads]
    call hex16
    mov al, '/'
    call putc
    mov ax, [spt]
    call hex16
    call newline

    mov eax, SBM_KERNEL_LBA
    call read_sector
    mov si, kernel_msg
    mov di, LOAD_BUFFER + 4
    mov edx, SBMK_MAGIC
    call report_test

    mov eax, XTIDE_ROM_LBA
    call read_sector
    mov si, xtide_msg
    mov di, LOAD_BUFFER
    xor edx, edx
    mov dx, 0xAA55
    call report_test16

    mov eax, DEBUG_LOADER_LBA
    call read_sector
    mov si, loader_msg
    mov di, LOAD_BUFFER + 0x40
    mov edx, SBML_MAGIC
    call report_test

    mov si, key_msg
    call puts
    xor ah, ah
    int 0x16
    mov dl, [boot_drive]
    jmp 0:LOAD_BUFFER

fatal_geometry:
    mov si, geometry_error
    call puts
    jmp halt

; Print the test label, computed CHS, and read/signature status.
report_test:
    call puts
    call print_chs
    jc .read_error
    cmp [di], edx
    jne .bad_magic
    mov si, ok_msg
    jmp puts
.read_error:
    mov si, read_error_msg
    jmp puts
.bad_magic:
    mov si, magic_error_msg
    jmp puts

report_test16:
    call puts
    call print_chs
    jc .read_error
    cmp [di], dx
    jne .bad_magic
    mov si, ok_msg
    jmp puts
.read_error:
    mov si, read_error_msg
    jmp puts
.bad_magic:
    mov si, magic_error_msg
    jmp puts

; Read EAX LBA to 0000:7C00 and retain its computed CHS for display.
read_sector:
    mov [target_lba], eax
    call calculate_chs
    jc .done
    cmp byte [use_edd], 0
    je .chs
    mov word [dap], 0x10
    mov word [dap + 2], 1
    mov word [dap + 4], LOAD_BUFFER
    mov word [dap + 6], 0
    mov eax, [target_lba]
    mov [dap + 8], eax
    mov dword [dap + 12], 0
    mov si, dap
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jmp .done
.chs:
    mov ax, [chs_cylinder]
    mov ch, al
    mov cl, [chs_sector]
    mov al, ah
    and al, 3
    shl al, 6
    or cl, al
    mov dh, [chs_head]
    mov dl, [boot_drive]
    mov bx, LOAD_BUFFER
    mov ax, 0x0201
    int 0x13
.done:
    pushf
    pop word [read_flags]
    ret

calculate_chs:
    mov eax, [target_lba]
    movzx ecx, word [spt]
    jecxz .bad
    xor edx, edx
    div ecx
    inc dl
    mov [chs_sector], dl
    movzx ecx, word [heads]
    jecxz .bad
    xor edx, edx
    div ecx
    cmp eax, 1023
    ja .bad
    mov [chs_cylinder], ax
    mov [chs_head], dl
    clc
    ret
.bad:
    stc
    ret

print_chs:
    mov al, ' '
    call putc
    mov ax, [chs_cylinder]
    call hex16
    mov al, '/'
    call putc
    xor ax, ax
    mov al, [chs_head]
    call hex16
    mov al, '/'
    call putc
    xor ax, ax
    mov al, [chs_sector]
    call hex16
    push word [read_flags]
    popf
    ret

puts:
    lodsb
    test al, al
    jz .done
    call putc
    jmp puts
.done:
    ret

newline:
    mov al, 13
    call putc
    mov al, 10
putc:
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    ret

hex16:
    push ax
    mov al, ah
    call hex8
    pop ax
hex8:
    push ax
    shr al, 4
    call hex_digit
    pop ax
hex_digit:
    and al, 0x0F
    add al, '0'
    cmp al, '9'
    jbe putc
    add al, 7
    jmp putc

halt:
    cli
    hlt
    jmp halt

banner          db "SBM BIOS DEBUG", 13, 10, 0
drive_msg       db "DL=", 0
edd_msg         db " EDD=", 0
geom_msg        db " C/H/S=", 0
kernel_msg      db "K@00000001", 0
xtide_msg       db "X@00000080", 0
loader_msg      db "L@0000003F", 0
ok_msg          db " OK", 13, 10, 0
read_error_msg  db " READ ERR", 13, 10, 0
magic_error_msg db " MAGIC BAD", 13, 10, 0
key_msg         db "KEY TO START SBM", 13, 10, 0
geometry_error  db "GEOMETRY ERR", 13, 10, 0

boot_drive      db 0
use_edd         db 0
spt             dw 0
heads           dw 0
cylinders       dw 0
target_lba      dd 0
chs_cylinder    dw 0
chs_head        db 0
chs_sector      db 0
read_flags      dw 0
dap             times 16 db 0

    times 1024-($-$$) db 0
