; I tried really hard to do this in inline asm but it just wasn't gonna work lol

[BITS 32]
section .bootrodata

GDT:
    .Null: equ $ - GDT
	    dq 0
    .Code: equ $ - GDT
	    .Code.limit_lo: dw 0xFFFF
		.Code.base_lo: dw 0
		.Code.base_mid: db 0
		.Code.access: db 0b10011010
		.Code.flags: db 0b10101111
		.Code.base_hi: db 0
    .Data: equ $ - GDT
	    .Data.limit_lo: dw 0xFFFF
		.Data.base_lo: dw 0
		.Data.base_mid: db 0
		.Data.access: db 0b10010010
		.Data.flags: db 0b11001111
		.Data.base_hi: db 0
    .Pointer: equ $ - GDT
	    dw $ - GDT - 1
		dq GDT

section .boottext

global farJump
farJump:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    lgdt [GDT.Pointer]
	;jmp GDT.Code:realm64
	jmp 0x8:trampoline64


[BITS 64]

EXTERN kmain

section .boottext
global trampoline64
trampoline64:
    cli
	hlt
	jmp kmain
