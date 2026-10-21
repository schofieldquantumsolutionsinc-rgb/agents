# QSEED-1 — JLSQ V17 native bootstrap seed (x86-64 Linux)
#
# Hand-authored assembly. Static ELF, no libc, raw syscalls only.
# Executes programs in the QBN1 native byte encoding (see SPEC.md):
# a small exact-integer stack machine implementing the core gate
# operations the bootstrap sequence needs. Every failure is typed:
# a named message on stderr and a distinct non-zero exit code.
# No C, no JSON, no foreign implementation anywhere in the
# execution path: this binary is the first native rung.
#
# Register plan:
#   rbp = input buffer base        r12 = VM stack pointer (next free)
#   r13 = program counter          r14 = code end
#   r15 = data pointer             rbx = data end
#   [input_len] = total bytes read [stack_base]/[stack_top] bounds

    .intel_syntax noprefix
    .global _start
    .text

.equ SYS_READ, 0
.equ SYS_WRITE, 1
.equ SYS_EXIT, 60
.equ EXIT_ASSERT, 42
.equ EXIT_ARITH, 43
.equ EXIT_FORMAT, 44
.equ EXIT_UNDERFLOW, 45
.equ EXIT_OPCODE, 46
.equ EXIT_DATA, 47
.equ EXIT_EMIT, 48
.equ EXIT_OVERFLOW, 49

_start:
    # --- read all of stdin into input_buf ---
    lea rbp, [input_buf]
    mov rsi, rbp
    xor rbx, rbx                # bytes read so far
read_loop:
    mov rdx, 4194304
    sub rdx, rbx
    jz fail_format              # input larger than buffer: typed refusal
    lea rsi, [rbp + rbx]
    xor edi, edi                # fd 0
    mov eax, SYS_READ
    syscall
    test rax, rax
    jz read_done
    js read_done                # read error: treat as end of input
    add rbx, rax
    jmp read_loop
read_done:
    mov [input_len], rbx

    # --- validate header: magic "QBN1" + u32 code length ---
    cmp rbx, 12
    jb fail_format
    cmp byte ptr [rbp], 'Q'
    jne fail_format
    cmp byte ptr [rbp + 1], 'B'
    jne fail_format
    cmp byte ptr [rbp + 2], 'N'
    jne fail_format
    cmp byte ptr [rbp + 3], '1'
    jne fail_format
    mov eax, dword ptr [rbp + 8]   # code length
    lea r13, [rbp + 12]            # pc = code start
    mov r14, r13
    add r14, rax                   # code end
    lea rax, [rbp + rbx]           # input end
    cmp r14, rax
    ja fail_format                 # code overruns the stream
    mov r15, r14                   # data pointer = code end
    mov rbx, rax                   # data end = input end
    lea r12, [vm_stack]            # VM stack starts empty

# ================= interpreter main loop =================
fetch:
    cmp r13, r14
    jae fail_format                # ran off the end of code: QPC_BOUNDS
    movzx eax, byte ptr [r13]
    inc r13
    cmp eax, 0x11
    ja fail_opcode
    lea rcx, [op_table]
    movsxd rdx, dword ptr [rcx + rax * 4]
    add rdx, rcx
    jmp rdx

op_table:
    .long op_halt - op_table
    .long op_push - op_table
    .long op_add - op_table
    .long op_sub - op_table
    .long op_eq - op_table
    .long op_next - op_table
    .long op_hasnext - op_table
    .long op_assert - op_table
    .long op_emit - op_table
    .long op_jmp - op_table
    .long op_jz - op_table
    .long op_dup - op_table
    .long op_drop - op_table
    .long op_swap - op_table
    .long op_emitbuf - op_table
    .long op_pick - op_table
    .long op_dataleft - op_table
    .long op_gt - op_table

# ---- stack primitives (inline at each use site via macros not available;
# ---- push/pop written out per op, bounds-checked) ----

op_halt:                            # 0x00 — clean stop
    xor edi, edi
    mov eax, SYS_EXIT
    syscall

op_push:                            # 0x01 — push imm64 (8 bytes follow)
    lea rax, [r13 + 8]
    cmp rax, r14
    ja fail_format
    mov rax, [r13]
    add r13, 8
    lea rdx, [stack_top]
    cmp r12, rdx
    jae fail_overflow
    mov [r12], rax
    add r12, 8
    jmp fetch

op_add:                             # 0x02 — exact add, overflow traps
    lea rax, [vm_stack]
    lea rdx, [rax + 16]
    cmp r12, rdx
    jb fail_underflow
    mov rax, [r12 - 8]              # b (top)
    mov rdx, [r12 - 16]             # a
    add rdx, rax
    jo fail_arith
    sub r12, 8
    mov [r12 - 8], rdx
    jmp fetch

op_sub:                             # 0x03 — exact subtract a - b
    lea rax, [vm_stack]
    lea rdx, [rax + 16]
    cmp r12, rdx
    jb fail_underflow
    mov rax, [r12 - 8]
    mov rdx, [r12 - 16]
    sub rdx, rax
    jo fail_arith
    sub r12, 8
    mov [r12 - 8], rdx
    jmp fetch

op_eq:                              # 0x04 — exact equality -> 1/0
    lea rax, [vm_stack]
    lea rdx, [rax + 16]
    cmp r12, rdx
    jb fail_underflow
    mov rax, [r12 - 8]
    mov rdx, [r12 - 16]
    cmp rdx, rax
    sete al
    movzx rdx, al
    sub r12, 8
    mov [r12 - 8], rdx
    jmp fetch

op_gt:                              # 0x11 — signed a > b -> 1/0
    lea rax, [vm_stack]
    lea rdx, [rax + 16]
    cmp r12, rdx
    jb fail_underflow
    mov rax, [r12 - 8]
    mov rdx, [r12 - 16]
    cmp rdx, rax
    setg al
    movzx rdx, al
    sub r12, 8
    mov [r12 - 8], rdx
    jmp fetch

op_next:                            # 0x05 — push next record (stage, event)
    mov rax, rbx
    sub rax, r15
    cmp rax, 16
    jb fail_data
    lea rdx, [stack_top]
    lea rcx, [rdx - 16]
    cmp r12, rcx
    ja fail_overflow
    mov rax, [r15]                  # stage
    mov [r12], rax
    mov rax, [r15 + 8]              # event_ok
    mov [r12 + 8], rax
    add r12, 16
    add r15, 16
    jmp fetch

op_hasnext:                         # 0x06 — push 1 if a full record remains
    mov rax, rbx
    sub rax, r15
    cmp rax, 16
    setae al
    movzx rax, al
    lea rdx, [stack_top]
    cmp r12, rdx
    jae fail_overflow
    mov [r12], rax
    add r12, 8
    jmp fetch

op_assert:                          # 0x07 — pop; zero is a typed failure
    lea rax, [vm_stack]
    cmp r12, rax
    jbe fail_underflow
    sub r12, 8
    mov rax, [r12]
    test rax, rax
    jz fail_assert
    jmp fetch

op_emit:                            # 0x08 — pop value; write its low byte
    lea rax, [vm_stack]
    cmp r12, rax
    jbe fail_underflow
    sub r12, 8
    mov rax, [r12]
    lea rsi, [scratch]
    mov [rsi], al
    mov edi, 1
    mov edx, 1
    mov eax, SYS_WRITE
    syscall
    jmp fetch

op_jmp:                             # 0x09 — pc += rel16 (signed)
    lea rax, [r13 + 2]
    cmp rax, r14
    ja fail_format
    movsx rax, word ptr [r13]
    add r13, 2
    add r13, rax
    lea rax, [rbp + 12]
    cmp r13, rax
    jb fail_format
    cmp r13, r14
    ja fail_format
    jmp fetch

op_jz:                              # 0x0A — pop; jump if zero
    lea rax, [r13 + 2]
    cmp rax, r14
    ja fail_format
    movsx rax, word ptr [r13]
    add r13, 2
    lea rdx, [vm_stack]
    cmp r12, rdx
    jbe fail_underflow
    sub r12, 8
    mov rdx, [r12]
    test rdx, rdx
    jnz fetch
    add r13, rax
    lea rax, [rbp + 12]
    cmp r13, rax
    jb fail_format
    cmp r13, r14
    ja fail_format
    jmp fetch

op_dup:                             # 0x0B — duplicate top
    lea rax, [vm_stack]
    cmp r12, rax
    jbe fail_underflow
    lea rdx, [stack_top]
    cmp r12, rdx
    jae fail_overflow
    mov rax, [r12 - 8]
    mov [r12], rax
    add r12, 8
    jmp fetch

op_drop:                            # 0x0C — discard top
    lea rax, [vm_stack]
    cmp r12, rax
    jbe fail_underflow
    sub r12, 8
    jmp fetch

op_swap:                            # 0x0D — swap top two
    lea rax, [vm_stack]
    lea rdx, [rax + 16]
    cmp r12, rdx
    jb fail_underflow
    mov rax, [r12 - 8]
    mov rdx, [r12 - 16]
    mov [r12 - 8], rdx
    mov [r12 - 16], rax
    jmp fetch

op_emitbuf:                         # 0x0E — write stream bytes (u32 off, u32 len; len=0xFFFFFFFF = to end)
    lea rax, [r13 + 8]
    cmp rax, r14
    ja fail_format
    mov edi, dword ptr [r13]        # offset
    mov esi, dword ptr [r13 + 4]    # length
    add r13, 8
    mov rax, [input_len]
    mov ecx, edi
    cmp rcx, rax
    ja fail_emit
    cmp esi, 0xFFFFFFFF
    je emitbuf_toend
    mov edx, esi
    add rdx, rcx
    cmp rdx, rax
    ja fail_emit
    jmp emitbuf_go
emitbuf_toend:
    mov rdx, rax
    sub rdx, rcx
    mov esi, edx
emitbuf_go:
    mov r9d, esi                    # bytes remaining (capture BEFORE rsi reuse)
    lea rsi, [rbp + rcx]            # source
    mov r8, rsi
emitbuf_loop:
    test r9, r9
    jz fetch
    mov edi, 1
    mov rsi, r8
    mov rdx, r9
    mov eax, SYS_WRITE
    syscall
    test rax, rax
    jle fail_emit
    add r8, rax
    sub r9, rax
    jmp emitbuf_loop

op_pick:                            # 0x0F — copy nth value (u8 follows; 0 = top)
    lea rax, [r13 + 1]
    cmp rax, r14
    ja fail_format
    movzx eax, byte ptr [r13]
    inc r13
    inc rax                         # slots down from next-free
    shl rax, 3
    mov rdx, r12
    sub rdx, rax
    lea rax, [vm_stack]
    cmp rdx, rax
    jb fail_underflow
    mov rax, [rdx]
    lea rdx, [stack_top]
    cmp r12, rdx
    jae fail_overflow
    mov [r12], rax
    add r12, 8
    jmp fetch

op_dataleft:                        # 0x10 — push remaining data bytes
    mov rax, rbx
    sub rax, r15
    lea rdx, [stack_top]
    cmp r12, rdx
    jae fail_overflow
    mov [r12], rax
    add r12, 8
    jmp fetch

# ================= typed failures =================
fail_assert:
    lea rsi, [msg_assert]
    mov edx, offset msg_assert_len
    mov edi, EXIT_ASSERT
    jmp fail_common
fail_arith:
    lea rsi, [msg_arith]
    mov edx, offset msg_arith_len
    mov edi, EXIT_ARITH
    jmp fail_common
fail_format:
    lea rsi, [msg_format]
    mov edx, offset msg_format_len
    mov edi, EXIT_FORMAT
    jmp fail_common
fail_underflow:
    lea rsi, [msg_underflow]
    mov edx, offset msg_underflow_len
    mov edi, EXIT_UNDERFLOW
    jmp fail_common
fail_opcode:
    lea rsi, [msg_opcode]
    mov edx, offset msg_opcode_len
    mov edi, EXIT_OPCODE
    jmp fail_common
fail_data:
    lea rsi, [msg_data]
    mov edx, offset msg_data_len
    mov edi, EXIT_DATA
    jmp fail_common
fail_emit:
    lea rsi, [msg_emit]
    mov edx, offset msg_emit_len
    mov edi, EXIT_EMIT
    jmp fail_common
fail_overflow:
    lea rsi, [msg_overflow]
    mov edx, offset msg_overflow_len
    mov edi, EXIT_OVERFLOW
    jmp fail_common

fail_common:                        # rsi=msg, rdx=len, rdi=exit code
    mov r8, rdi
    mov edi, 2                      # stderr
    mov eax, SYS_WRITE
    syscall
    mov rdi, r8
    mov eax, SYS_EXIT
    syscall

    .section .rodata
msg_assert:     .ascii "QASSERT_FAIL\n"
    .equ msg_assert_len, . - msg_assert
msg_arith:      .ascii "QARITH_OVERFLOW\n"
    .equ msg_arith_len, . - msg_arith
msg_format:     .ascii "QFORMAT_INVALID\n"
    .equ msg_format_len, . - msg_format
msg_underflow:  .ascii "QSTACK_UNDERFLOW\n"
    .equ msg_underflow_len, . - msg_underflow
msg_opcode:     .ascii "QOP_UNKNOWN\n"
    .equ msg_opcode_len, . - msg_opcode
msg_data:       .ascii "QDATA_EXHAUSTED\n"
    .equ msg_data_len, . - msg_data
msg_emit:       .ascii "QEMIT_BOUNDS\n"
    .equ msg_emit_len, . - msg_emit
msg_overflow:   .ascii "QSTACK_OVERFLOW\n"
    .equ msg_overflow_len, . - msg_overflow

    .section .bss
    .align 8
input_buf:      .skip 4194304
input_len:      .skip 8
vm_stack:       .skip 32768
stack_top:
scratch:        .skip 8
