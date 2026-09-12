; Stage-1 diagnostic MBR for the proposed shimless SBM layout.
;
; Relocates out of 0000:7C00, discovers EDD and legacy CHS geometry, then loads
; the two-sector diagnostic payload from reserved LBA 39 to 0000:8000. The
; payload displays the detailed results and continues into SBM.

    BITS 16
    ORG 0x600

%define LOAD_BUFFER 0x8000
%define DEBUG_STAGE_LBA 39
%define DEBUG_STAGE_SECTORS 2
%define DEBUG_MAGIC 0x47424453       ; "SDBG"

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    cld
    mov si, 0x7C00
    mov di, 0x600
    mov cx, 256
    rep movsw
    jmp 0:relocated

relocated:
    mov [boot_drive], dl

    ; Record the geometry required by the legacy read path.
    mov ah, 0x08
    int 0x13
    jc load_error
    and cx, 0x003F
    jz load_error
    mov [spt], cx
    xor ax, ax
    mov al, dh
    inc ax
    mov [heads], ax

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

    xor ax, ax
    mov es, ax
    mov di, LOAD_BUFFER
    mov ebx, DEBUG_STAGE_LBA
    mov cx, DEBUG_STAGE_SECTORS
.load:
    push cx
    call read_sector
    pop cx
    jc load_error
    inc ebx
    add di, 512
    loop .load

    cmp dword [LOAD_BUFFER], DEBUG_MAGIC
    jne load_error
    mov dl, [boot_drive]
    jmp 0:(LOAD_BUFFER + 4)

; Read EBX LBA to 0000:DI using EDD or runtime BIOS geometry.
read_sector:
    push ebx
    cmp byte [use_edd], 0
    je .chs
    mov word [dap], 0x10
    mov word [dap + 2], 1
    mov [dap + 4], di
    mov word [dap + 6], 0
    mov [dap + 8], ebx
    mov dword [dap + 12], 0
    mov si, dap
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    pop ebx
    ret
.chs:
    mov eax, ebx
    movzx ecx, word [spt]
    xor edx, edx
    div ecx
    inc dl
    push dx
    movzx ecx, word [heads]
    xor edx, edx
    div ecx
    cmp eax, 1023
    ja .bad_pop
    mov dh, dl
    pop cx
    xchg al, ah
    shl al, 6
    or cl, al
    mov ch, ah
    mov dl, [boot_drive]
    mov bx, di
    mov ax, 0x0201
    int 0x13
    pop ebx
    ret
.bad_pop:
    pop dx
    stc
    pop ebx
    ret

load_error:
    mov si, error_msg
.print:
    lodsb
    test al, al
    jz .halt
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    jmp .print
.halt:
    cli
    hlt
    jmp .halt

error_msg  db "DEBUG STAGE LOAD ERROR", 13, 10, 0
boot_drive db 0
use_edd    db 0
spt        dw 0
heads      dw 0
dap        times 16 db 0

    times 440-($-$$) db 0
