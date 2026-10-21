.intel_syntax noprefix
.global _start
.text

.equ SYS_READ, 0
.equ SYS_WRITE, 1
.equ SYS_EXIT, 60
.equ CAP, 2097152

.ifndef TOOL_MODE
.equ TOOL_MODE, 1
.endif

.macro EXIT code
    mov edi, \code
    mov eax, SYS_EXIT
    syscall
.endm

.macro WRITE fd, label, len
    mov edi, \fd
    lea rsi, [\label]
    mov edx, OFFSET FLAT:\len
    mov eax, SYS_WRITE
    syscall
.endm

_start:
.if TOOL_MODE == 1
    jmp qreader
.elseif TOOL_MODE == 2
    jmp qinspect
.elseif TOOL_MODE == 3
    jmp qverify
.elseif TOOL_MODE == 4
    jmp qgate
.elseif TOOL_MODE == 5
    jmp qnode
.elseif TOOL_MODE == 6
    jmp qouter
.elseif TOOL_MODE == 7
    jmp qabi
.elseif TOOL_MODE == 8
    jmp qidentity
.elseif TOOL_MODE == 9
    jmp qselftest
.else
    EXIT 99
.endif

# QREADER: lossless bounded stdin -> stdout. No normalization.
qreader:
    xor r12d, r12d
.Lqr_read:
    cmp r12, CAP
    jae .Lqr_bounds
    xor edi, edi
    lea rsi, [buf+r12]
    mov rdx, CAP
    sub rdx, r12
    xor eax, eax
    syscall
    test rax, rax
    js .Lqr_fail
    jz .Lqr_emit
    add r12, rax
    jmp .Lqr_read
.Lqr_emit:
    xor r13d, r13d
.Lqr_write:
    cmp r13, r12
    jae .Lqr_ok
    mov edi, 1
    lea rsi, [buf+r13]
    mov rdx, r12
    sub rdx, r13
    mov eax, SYS_WRITE
    syscall
    test rax, rax
    jle .Lqr_fail
    add r13, rax
    jmp .Lqr_write
.Lqr_ok:
    EXIT 0
.Lqr_bounds:
    WRITE 2, msg_bounds, msg_bounds_len
    EXIT 61
.Lqr_fail:
    WRITE 2, msg_io, msg_io_len
    EXIT 62

# QINSPECT: identify QBN1 or QSOURCE without transforming input.
qinspect:
    call read_all
    cmp r12, 4
    jb .Lqi_text
    cmp dword ptr [buf], 0x314e4251
    jne .Lqi_text
    WRITE 1, msg_qbn1, msg_qbn1_len
    EXIT 0
.Lqi_text:
    WRITE 1, msg_qsource, msg_qsource_len
    EXIT 0

# QVERIFY: structural QBN1 validation, including opcode/operand walk.
qverify:
    call read_all
    call validate_qbn1
    WRITE 1, msg_verified, msg_verified_len
    EXIT 0

# QGATE: same structural verifier, silent success for piping gates.
qgate:
    call read_all
    call validate_qbn1
    EXIT 0

# QNODE: native node health identity/status endpoint.
qnode:
    WRITE 1, msg_node, msg_node_len
    EXIT 0

# QOUTER: argv[1] dispatcher. status/identity/abi supported; others explicit.
qouter:
    mov rbx, [rsp]
    cmp rbx, 2
    jb .Lqo_usage
    mov rdi, [rsp+16]
    lea rsi, [tok_status]
    call streq
    test eax, eax
    jnz .Lqo_status
    mov rdi, [rsp+16]
    lea rsi, [tok_identity]
    call streq
    test eax, eax
    jnz .Lqo_identity
    mov rdi, [rsp+16]
    lea rsi, [tok_abi]
    call streq
    test eax, eax
    jnz .Lqo_abi
    WRITE 2, msg_unsupported, msg_unsupported_len
    EXIT 66
.Lqo_status:
    WRITE 1, msg_node, msg_node_len
    EXIT 0
.Lqo_identity:
    WRITE 1, msg_identity, msg_identity_len
    EXIT 0
.Lqo_abi:
    WRITE 1, msg_abi, msg_abi_len
    EXIT 0
.Lqo_usage:
    WRITE 2, msg_router_usage, msg_router_usage_len
    EXIT 65

qabi:
    WRITE 1, msg_abi, msg_abi_len
    EXIT 0

qidentity:
    WRITE 1, msg_identity, msg_identity_len
    EXIT 0

# QSELFTEST: deterministic checks of constants and validator path on embedded stream.
qselftest:
    lea rsi, [self_qbn]
    lea rdi, [buf]
    mov ecx, OFFSET FLAT:self_qbn_len
    rep movsb
    mov r12, OFFSET FLAT:self_qbn_len
    call validate_qbn1
    WRITE 1, msg_selftest, msg_selftest_len
    EXIT 0

# read_all => r12=len, typed failures 61/62
read_all:
    xor r12d, r12d
.Lra:
    cmp r12, CAP
    jae .Lra_bounds
    xor edi, edi
    lea rsi, [buf+r12]
    mov rdx, CAP
    sub rdx, r12
    xor eax, eax
    syscall
    test rax, rax
    js .Lra_io
    jz .Lra_done
    add r12, rax
    jmp .Lra
.Lra_done:
    ret
.Lra_bounds:
    WRITE 2, msg_bounds, msg_bounds_len
    EXIT 61
.Lra_io:
    WRITE 2, msg_io, msg_io_len
    EXIT 62

# validate_qbn1 on buf/r12. Checks header, reserved, code bounds, and known opcodes.
validate_qbn1:
    cmp r12, 12
    jb .Lv_bad
    cmp dword ptr [buf], 0x314e4251
    jne .Lv_bad
    cmp dword ptr [buf+4], 0
    jne .Lv_bad
    mov eax, dword ptr [buf+8]
    mov r13, rax
    add rax, 12
    cmp rax, r12
    ja .Lv_bad
    lea r14, [buf+12]
    lea r15, [r14+r13]
.Lv_op:
    cmp r14, r15
    jae .Lv_ok
    movzx eax, byte ptr [r14]
    inc r14
    cmp eax, 0x11
    ja .Lv_opbad
    cmp eax, 0x01
    je .Lv_need8
    cmp eax, 0x09
    je .Lv_need2
    cmp eax, 0x0A
    je .Lv_need2
    cmp eax, 0x0E
    je .Lv_need8
    cmp eax, 0x0F
    je .Lv_need1
    jmp .Lv_op
.Lv_need8:
    add r14, 8
    cmp r14, r15
    ja .Lv_bad
    jmp .Lv_op
.Lv_need2:
    add r14, 2
    cmp r14, r15
    ja .Lv_bad
    jmp .Lv_op
.Lv_need1:
    inc r14
    cmp r14, r15
    ja .Lv_bad
    jmp .Lv_op
.Lv_ok:
    ret
.Lv_bad:
    WRITE 2, msg_format, msg_format_len
    EXIT 63
.Lv_opbad:
    WRITE 2, msg_opcode, msg_opcode_len
    EXIT 64

# streq: rdi C-string A, rsi C-string B => eax 1 equal else 0
streq:
.Lse:
    mov al, [rdi]
    mov dl, [rsi]
    cmp al, dl
    jne .Lse_no
    test al, al
    jz .Lse_yes
    inc rdi
    inc rsi
    jmp .Lse
.Lse_yes:
    mov eax, 1
    ret
.Lse_no:
    xor eax, eax
    ret

.section .rodata
msg_bounds: .ascii "QINPUT_BOUNDS\n"
.equ msg_bounds_len, .-msg_bounds
msg_io: .ascii "QIO_FAIL\n"
.equ msg_io_len, .-msg_io
msg_qbn1: .ascii "QBN1\n"
.equ msg_qbn1_len, .-msg_qbn1
msg_qsource: .ascii "QSOURCE\n"
.equ msg_qsource_len, .-msg_qsource
msg_verified: .ascii "QVERIFIED\n"
.equ msg_verified_len, .-msg_verified
msg_format: .ascii "QFORMAT_INVALID\n"
.equ msg_format_len, .-msg_format
msg_opcode: .ascii "QOP_UNKNOWN\n"
.equ msg_opcode_len, .-msg_opcode
msg_node: .ascii "JLSQ_V17_QNODE READY\n"
.equ msg_node_len, .-msg_node
msg_abi: .ascii "JLSQ_V17_ABI QBN1/QSOURCE-1\n"
.equ msg_abi_len, .-msg_abi
msg_identity: .ascii "JLSQ V17 NATIVE FOUNDATION TOOLSUITE 001\n"
.equ msg_identity_len, .-msg_identity
msg_selftest: .ascii "QSELFTEST PASS\n"
.equ msg_selftest_len, .-msg_selftest
msg_unsupported: .ascii "QOUTER_UNSUPPORTED\n"
.equ msg_unsupported_len, .-msg_unsupported
msg_router_usage: .ascii "QOUTER_USAGE status|identity|abi\n"
.equ msg_router_usage_len, .-msg_router_usage
tok_status: .asciz "status"
tok_identity: .asciz "identity"
tok_abi: .asciz "abi"
# QBN1 header, code_len=1, HALT
self_qbn: .ascii "QBN1"; .long 0; .long 1; .byte 0
.equ self_qbn_len, .-self_qbn

.bss
.align 16
buf: .skip CAP
