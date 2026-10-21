.intel_syntax noprefix
.global _start
.text

.equ SYS_READ, 0
.equ SYS_WRITE, 1
.equ SYS_EXIT, 60
.equ IN_CAP, 1048576
.equ OUT_CAP, 2097152
.equ MAX_LABELS, 512

.equ EXIT_PARSE, 50
.equ EXIT_SYMBOL, 51
.equ EXIT_NUMBER, 52
.equ EXIT_OUTPUT, 53
.equ EXIT_JUMP, 54
.equ EXIT_OPCODE, 55

# Build with --defsym PARSER_MODE=1 for validator-only qparser.
.ifndef PARSER_MODE
.equ PARSER_MODE, 0
.endif

_start:
    # Read source text from stdin.
    lea r12, [input_buf]
    xor r13, r13
.Lread:
    mov rdx, IN_CAP
    sub rdx, r13
    jz fail_output
    xor edi, edi
    lea rsi, [r12+r13]
    xor eax, eax
    syscall
    test rax, rax
    jz .Lread_done
    js fail_parse
    add r13, rax
    jmp .Lread
.Lread_done:
    mov [input_len], r13

    # Pass 1: validate, collect labels, compute code/data lengths.
    mov qword ptr [pass_no], 1
    mov qword ptr [section_data], 0
    mov qword ptr [code_off], 0
    mov qword ptr [data_off], 0
    mov qword ptr [label_count], 0
    call scan_source
    mov rax, [code_off]
    mov [code_len], rax
    mov rax, [data_off]
    mov [data_len], rax

    # Pass 2: resolve symbols and emit canonical QBN1 bytes.
    mov qword ptr [pass_no], 2
    mov qword ptr [section_data], 0
    mov qword ptr [code_off], 0
    mov qword ptr [data_off], 0
    call scan_source

.if PARSER_MODE
    # Parser validates exactly the same grammar and symbol resolution.
    xor edi, edi
    mov eax, SYS_EXIT
    syscall
.else
    # Header: QBN1 | reserved u32=0 | code_len u32 little endian.
    lea rdi, [output_buf]
    mov byte ptr [rdi], 'Q'
    mov byte ptr [rdi+1], 'B'
    mov byte ptr [rdi+2], 'N'
    mov byte ptr [rdi+3], '1'
    mov dword ptr [rdi+4], 0
    mov rax, [code_len]
    mov edx, 0xffffffff
    cmp rax, rdx
    ja fail_output
    mov dword ptr [rdi+8], eax
    mov rdx, 12
    add rdx, [code_len]
    add rdx, [data_len]
    cmp rdx, OUT_CAP
    ja fail_output
    mov edi, 1
    lea rsi, [output_buf]
    mov eax, SYS_WRITE
    syscall
    test rax, rax
    js fail_output
    xor edi, edi
    mov eax, SYS_EXIT
    syscall
.endif

# ------------------------------------------------------------
# scan_source: line-oriented two-pass parser/emitter.
# ------------------------------------------------------------
scan_source:
    push rbp
    mov rbp, rsp
    lea r14, [input_buf]
    lea r15, [input_buf]
    add r15, [input_len]
.Lline_loop:
    cmp r14, r15
    jae .Lscan_done
    mov [line_start], r14
    mov rbx, r14
.Lfind_eol:
    cmp rbx, r15
    jae .Leol_found
    cmp byte ptr [rbx], 10
    je .Leol_found
    inc rbx
    jmp .Lfind_eol
.Leol_found:
    mov [line_end], rbx
    mov [cursor], r14

    call get_token
    test rax, rax
    jz .Lnext_line
    mov [t1p], rax
    mov [t1l], rcx
    call get_token
    mov [t2p], rax
    mov [t2l], rcx
    call get_token
    mov [t3p], rax
    mov [t3l], rcx
    call get_token
    mov [t4p], rax
    mov [t4l], rcx
    call get_token
    test rax, rax
    jnz fail_parse

    # .data switches section.
    mov rdi, [t1p]; mov rcx, [t1l]; lea rsi, [lit_data]
    call tok_eq
    test eax, eax
    jz .Lnot_data_switch
    cmp qword ptr [t2l], 0
    jne fail_parse
    mov qword ptr [section_data], 1
    jmp .Lnext_line
.Lnot_data_switch:
    cmp qword ptr [section_data], 0
    jne .Ldata_line

    # Label definition: a single token ending in ':'.
    mov rax, [t1l]
    test rax, rax
    jz fail_parse
    mov rdx, [t1p]
    cmp byte ptr [rdx+rax-1], ':'
    jne .Linstruction
    cmp qword ptr [t2l], 0
    jne fail_parse
    cmp rax, 1
    jbe fail_parse
    cmp qword ptr [pass_no], 1
    jne .Lnext_line
    dec rax
    mov rdi, rdx
    mov rcx, rax
    call add_label
    jmp .Lnext_line

.Linstruction:
    call handle_instruction
    jmp .Lnext_line

.Ldata_line:
    call handle_data

.Lnext_line:
    mov r14, [line_end]
    cmp r14, r15
    jae .Lline_loop
    inc r14
    jmp .Lline_loop
.Lscan_done:
    leave
    ret

# ------------------------------------------------------------
# Tokenizer. Comment begins at #. Whitespace = space/tab/CR.
# Returns rax=ptr (0 if no token), rcx=len. Updates cursor.
# ------------------------------------------------------------
get_token:
    mov r8, [cursor]
    mov r9, [line_end]
.Lskip_ws:
    cmp r8, r9
    jae .Lno_tok
    mov al, byte ptr [r8]
    cmp al, '#'
    je .Lno_tok
    cmp al, ' '
    je .Lskip_one
    cmp al, 9
    je .Lskip_one
    cmp al, 13
    je .Lskip_one
    jmp .Ltok_start
.Lskip_one:
    inc r8
    jmp .Lskip_ws
.Ltok_start:
    mov r10, r8
.Ltok_more:
    cmp r8, r9
    jae .Ltok_done
    mov al, byte ptr [r8]
    cmp al, '#'
    je .Ltok_done
    cmp al, ' '
    je .Ltok_done
    cmp al, 9
    je .Ltok_done
    cmp al, 13
    je .Ltok_done
    inc r8
    jmp .Ltok_more
.Ltok_done:
    mov [cursor], r8
    mov rax, r10
    mov rcx, r8
    sub rcx, r10
    ret
.Lno_tok:
    mov [cursor], r9
    xor eax, eax
    xor ecx, ecx
    ret

# tok_eq(rdi=ptr, rcx=len, rsi=NUL literal) => eax 1/0
# case-insensitive ASCII for op/directive names.
tok_eq:
    push rbx
    xor ebx, ebx
.Lte_loop:
    cmp rbx, rcx
    jae .Lte_endtok
    mov al, byte ptr [rdi+rbx]
    cmp al, 'a'
    jb .Lte_a_ok
    cmp al, 'z'
    ja .Lte_a_ok
    sub al, 32
.Lte_a_ok:
    mov dl, byte ptr [rsi+rbx]
    cmp dl, 'a'
    jb .Lte_b_ok
    cmp dl, 'z'
    ja .Lte_b_ok
    sub dl, 32
.Lte_b_ok:
    cmp al, dl
    jne .Lte_no
    inc rbx
    jmp .Lte_loop
.Lte_endtok:
    cmp byte ptr [rsi+rbx], 0
    jne .Lte_no
    mov eax, 1
    pop rbx
    ret
.Lte_no:
    xor eax, eax
    pop rbx
    ret

# add_label(rdi=ptr, rcx=len) at current code_off
add_label:
    cmp rcx, 63
    ja fail_symbol
    mov rax, [label_count]
    cmp rax, MAX_LABELS
    jae fail_symbol
    # reject duplicate
    xor r8, r8
.Ldup_loop:
    cmp r8, rax
    jae .Lstore_label
    mov r9, [label_len + r8*8]
    cmp r9, rcx
    jne .Ldup_next
    mov r10, [label_ptr + r8*8]
    xor r11, r11
.Ldup_cmp:
    cmp r11, rcx
    jae fail_symbol
    mov dl, byte ptr [rdi+r11]
    cmp dl, byte ptr [r10+r11]
    jne .Ldup_next
    inc r11
    jmp .Ldup_cmp
.Ldup_next:
    inc r8
    jmp .Ldup_loop
.Lstore_label:
    mov [label_ptr + rax*8], rdi
    mov [label_len + rax*8], rcx
    mov rdx, [code_off]
    mov [label_off + rax*8], rdx
    inc rax
    mov [label_count], rax
    ret

# find_label(rdi=ptr, rcx=len) => rax=offset or fail
find_label:
    xor r8, r8
    mov r9, [label_count]
.Lfl_loop:
    cmp r8, r9
    jae fail_symbol
    mov r10, [label_len+r8*8]
    cmp r10, rcx
    jne .Lfl_next
    mov r10, [label_ptr+r8*8]
    xor r11, r11
.Lfl_cmp:
    cmp r11, rcx
    jae .Lfl_found
    mov dl, byte ptr [rdi+r11]
    cmp dl, byte ptr [r10+r11]
    jne .Lfl_next
    inc r11
    jmp .Lfl_cmp
.Lfl_found:
    mov rax, [label_off+r8*8]
    ret
.Lfl_next:
    inc r8
    jmp .Lfl_loop

# parse_i64(rdi=ptr, rcx=len) => rax value; typed failure on invalid/overflow
parse_i64:
    test rcx, rcx
    jz fail_number
    # character literal 'X'
    cmp rcx, 3
    jne .Lnum_sign
    cmp byte ptr [rdi], 39
    jne .Lnum_sign
    cmp byte ptr [rdi+2], 39
    jne fail_number
    movzx eax, byte ptr [rdi+1]
    ret
.Lnum_sign:
    xor r8d, r8d       # negative flag
    xor r9d, r9d       # index
    cmp byte ptr [rdi], '-'
    jne .Lnum_base
    mov r8d, 1
    inc r9
    cmp r9, rcx
    jae fail_number
.Lnum_base:
    mov r10d, 10
    mov r11, r9
    add r11, 2
    cmp r11, rcx
    ja .Lnum_digits
    cmp byte ptr [rdi+r9], '0'
    jne .Lnum_digits
    mov dl, byte ptr [rdi+r9+1]
    cmp dl, 'x'
    je .Lhex
    cmp dl, 'X'
    jne .Lnum_digits
.Lhex:
    mov r10d, 16
    add r9, 2
    cmp r9, rcx
    jae fail_number
.Lnum_digits:
    xor eax, eax
.Ldigit_loop:
    cmp r9, rcx
    jae .Ldigits_done
    movzx edx, byte ptr [rdi+r9]
    cmp edx, '0'
    jb fail_number
    cmp edx, '9'
    jbe .Ldig_dec
    cmp r10d, 16
    jne fail_number
    cmp edx, 'A'
    jb .Ldig_lower
    cmp edx, 'F'
    jbe .Ldig_upper
.Ldig_lower:
    cmp edx, 'a'
    jb fail_number
    cmp edx, 'f'
    ja fail_number
    sub edx, 'a'-10
    jmp .Ldig_have
.Ldig_upper:
    sub edx, 'A'-10
    jmp .Ldig_have
.Ldig_dec:
    sub edx, '0'
.Ldig_have:
    imul rax, r10
    jo fail_number
    add rax, rdx
    jo fail_number
    inc r9
    jmp .Ldigit_loop
.Ldigits_done:
    test r8d, r8d
    jz .Lnum_ret
    neg rax
    jo fail_number
.Lnum_ret:
    ret

# hex_bytes_len(rdi ptr, rcx len) => rax=len/2 and validates hex.
hex_bytes_len:
    test rcx, 1
    jnz fail_parse
    xor r8, r8
.Lhbl:
    cmp r8, rcx
    jae .Lhbdone
    movzx edx, byte ptr [rdi+r8]
    call hex_nibble_validate
    inc r8
    jmp .Lhbl
.Lhbdone:
    mov rax, rcx
    shr rax, 1
    ret
hex_nibble_validate:
    cmp dl, '0'; jb fail_parse
    cmp dl, '9'; jbe .Lhn_ok
    cmp dl, 'A'; jb .Lhn_low
    cmp dl, 'F'; jbe .Lhn_ok
.Lhn_low:
    cmp dl, 'a'; jb fail_parse
    cmp dl, 'f'; ja fail_parse
.Lhn_ok:
    ret

# decode hex token into rdi destination. rsi ptr, rcx len.
decode_hex:
    push rbx
    xor r8, r8
    xor r9, r9
.Ldh_loop:
    cmp r8, rcx
    jae .Ldh_done
    movzx eax, byte ptr [rsi+r8]
    call hex_value
    shl eax, 4
    mov ebx, eax
    inc r8
    movzx eax, byte ptr [rsi+r8]
    call hex_value
    or eax, ebx
    mov byte ptr [rdi+r9], al
    inc r9
    inc r8
    jmp .Ldh_loop
.Ldh_done:
    pop rbx
    ret
hex_value:
    cmp al, '9'; jbe .Lhv_dec
    cmp al, 'F'; jbe .Lhv_up
    sub al, 'a'-10
    ret
.Lhv_up:
    sub al, 'A'-10
    ret
.Lhv_dec:
    sub al, '0'
    ret

# reserve code/data space during pass1 or get emit pointer during pass2.
# code_reserve rax=n => rdi=dest on pass2; updates code_off.
code_reserve:
    mov rdx, [code_off]
    mov rcx, rdx
    add rcx, rax
    cmp rcx, OUT_CAP-12
    ja fail_output
    mov [code_off], rcx
    cmp qword ptr [pass_no], 2
    jne .Lcr_none
    lea rdi, [output_buf+12]
    add rdi, rdx
    ret
.Lcr_none:
    xor edi, edi
    ret
# data_reserve rax=n => rdi=dest on pass2; updates data_off.
data_reserve:
    mov rdx, [data_off]
    mov rcx, rdx
    add rcx, rax
    mov r8, [code_len]
    add r8, rcx
    cmp r8, OUT_CAP-12
    ja fail_output
    mov [data_off], rcx
    cmp qword ptr [pass_no], 2
    jne .Ldr_none
    lea rdi, [output_buf+12]
    add rdi, [code_len]
    add rdi, rdx
    ret
.Ldr_none:
    xor edi, edi
    ret

# handle_instruction uses t1..t4 globals.
handle_instruction:
    # HALT and one-byte ops, no operands
    lea rsi, [lit_halt]; mov bl, 0x00; call match_onebyte; test eax,eax; jnz .Lhi_done
    lea rsi, [lit_add]; mov bl, 0x02; call match_onebyte; test eax,eax; jnz .Lhi_done
    lea rsi, [lit_sub]; mov bl, 0x03; call match_onebyte; test eax,eax; jnz .Lhi_done
    lea rsi, [lit_eq]; mov bl, 0x04; call match_onebyte; test eax,eax; jnz .Lhi_done
    lea rsi, [lit_next]; mov bl, 0x05; call match_onebyte; test eax,eax; jnz .Lhi_done
    lea rsi, [lit_hasnext]; mov bl, 0x06; call match_onebyte; test eax,eax; jnz .Lhi_done
    lea rsi, [lit_assert]; mov bl, 0x07; call match_onebyte; test eax,eax; jnz .Lhi_done
    lea rsi, [lit_emit]; mov bl, 0x08; call match_onebyte; test eax,eax; jnz .Lhi_done
    lea rsi, [lit_dup]; mov bl, 0x0b; call match_onebyte; test eax,eax; jnz .Lhi_done
    lea rsi, [lit_drop]; mov bl, 0x0c; call match_onebyte; test eax,eax; jnz .Lhi_done
    lea rsi, [lit_swap]; mov bl, 0x0d; call match_onebyte; test eax,eax; jnz .Lhi_done
    lea rsi, [lit_dataleft]; mov bl, 0x10; call match_onebyte; test eax,eax; jnz .Lhi_done
    lea rsi, [lit_gt]; mov bl, 0x11; call match_onebyte; test eax,eax; jnz .Lhi_done

    # PUSH imm64
    mov rdi,[t1p]; mov rcx,[t1l]; lea rsi,[lit_push]; call tok_eq; test eax,eax; jz .Lhi_jump
    cmp qword ptr [t2l],0; je fail_parse
    cmp qword ptr [t3l],0; jne fail_parse
    mov rdi,[t2p]; mov rcx,[t2l]; call parse_i64; mov r8,rax
    mov eax,9; call code_reserve
    cmp qword ptr [pass_no],2; jne .Lhi_done
    mov byte ptr [rdi],0x01
    mov [rdi+1],r8
    jmp .Lhi_done

.Lhi_jump:
    # JMP/JZ label
    mov rdi,[t1p]; mov rcx,[t1l]; lea rsi,[lit_jmp]; call tok_eq; mov r8d,eax
    mov rdi,[t1p]; mov rcx,[t1l]; lea rsi,[lit_jz]; call tok_eq; mov r9d,eax
    or r8d,r9d; jz .Lhi_pick
    cmp qword ptr [t2l],0; je fail_parse
    cmp qword ptr [t3l],0; jne fail_parse
    mov r11,[code_off]
    mov eax,3; call code_reserve
    cmp qword ptr [pass_no],2; jne .Lhi_done
    mov al,0x09; test r9d,r9d; jz .Ljop; mov al,0x0a
.Ljop: mov byte ptr [rdi],al
    push rdi
    mov rdi,[t2p]; mov rcx,[t2l]; call find_label
    # find_label clobbers r8-r11, so recover instruction start from code_off-3
    mov rdx,[code_off]; sub rdx,3; add rdx,3
    sub rax,rdx
    cmp rax,-32768; jl fail_jump
    cmp rax,32767; jg fail_jump
    pop rdi
    mov word ptr [rdi+1],ax
    jmp .Lhi_done

.Lhi_pick:
    mov rdi,[t1p]; mov rcx,[t1l]; lea rsi,[lit_pick]; call tok_eq; test eax,eax; jz .Lhi_emitbuf
    cmp qword ptr [t2l],0; je fail_parse
    cmp qword ptr [t3l],0; jne fail_parse
    mov rdi,[t2p]; mov rcx,[t2l]; call parse_i64
    cmp rax,0; jl fail_number
    cmp rax,255; ja fail_number
    mov r8,rax
    mov eax,2; call code_reserve
    cmp qword ptr [pass_no],2; jne .Lhi_done
    mov byte ptr [rdi],0x0f
    mov byte ptr [rdi+1],r8b
    jmp .Lhi_done

.Lhi_emitbuf:
    mov rdi,[t1p]; mov rcx,[t1l]; lea rsi,[lit_emitbuf]; call tok_eq; test eax,eax; jz .Lhi_rawcode
    cmp qword ptr [t2l],0; je fail_parse
    cmp qword ptr [t3l],0; je fail_parse
    cmp qword ptr [t4l],0; jne fail_parse
    mov rdi,[t2p]; mov rcx,[t2l]; call parse_i64
    cmp rax,0; jl fail_number
    mov edx,0xffffffff; cmp rax,rdx; ja fail_number
    mov rbx,rax
    mov rdi,[t3p]; mov rcx,[t3l]; lea rsi,[lit_end]; call tok_eq; test eax,eax; jz .Leb_num
    mov r9,0xffffffff
    jmp .Leb_ready
.Leb_num:
    mov rdi,[t3p]; mov rcx,[t3l]; call parse_i64
    cmp rax,0; jl fail_number
    mov edx,0xffffffff; cmp rax,rdx; ja fail_number
    mov r9,rax
.Leb_ready:
    mov eax,9; call code_reserve
    cmp qword ptr [pass_no],2; jne .Lhi_done
    mov byte ptr [rdi],0x0e
    mov dword ptr [rdi+1],ebx
    mov dword ptr [rdi+5],r9d
    jmp .Lhi_done

.Lhi_rawcode:
    mov rdi,[t1p]; mov rcx,[t1l]; lea rsi,[lit_rawcode]; call tok_eq; test eax,eax; jz fail_opcode
    cmp qword ptr [t2l],0; je fail_parse
    cmp qword ptr [t3l],0; jne fail_parse
    mov rdi,[t2p]; mov rcx,[t2l]; call hex_bytes_len
    mov r8,rax
    mov rax,r8; call code_reserve
    cmp qword ptr [pass_no],2; jne .Lhi_done
    mov rsi,[t2p]; mov rcx,[t2l]; call decode_hex
.Lhi_done:
    ret

# match one-byte opcode. Input rsi literal, bl opcode. returns eax=1 if matched.
match_onebyte:
    push rbx
    mov rdi,[t1p]; mov rcx,[t1l]; call tok_eq
    test eax,eax
    jz .Lmo_no
    cmp qword ptr [t2l],0
    jne fail_parse
    mov eax,1
    call code_reserve
    cmp qword ptr [pass_no],2
    jne .Lmo_yes
    pop rbx
    mov byte ptr [rdi], bl
    mov eax,1
    ret
.Lmo_yes:
    pop rbx
    mov eax,1
    ret
.Lmo_no:
    pop rbx
    xor eax,eax
    ret

handle_data:
    mov rdi,[t1p]; mov rcx,[t1l]; lea rsi,[lit_rec]; call tok_eq; test eax,eax; jz .Lhd_raw
    cmp qword ptr [t2l],0; je fail_parse
    cmp qword ptr [t3l],0; je fail_parse
    cmp qword ptr [t4l],0; jne fail_parse
    mov rdi,[t2p]; mov rcx,[t2l]; call parse_i64; mov rbx,rax
    mov rdi,[t3p]; mov rcx,[t3l]; call parse_i64; mov r9,rax
    mov eax,16; call data_reserve
    cmp qword ptr [pass_no],2; jne .Lhd_done
    mov [rdi],rbx
    mov [rdi+8],r9
    jmp .Lhd_done
.Lhd_raw:
    mov rdi,[t1p]; mov rcx,[t1l]; lea rsi,[lit_raw]; call tok_eq; test eax,eax; jz fail_parse
    cmp qword ptr [t2l],0; je fail_parse
    cmp qword ptr [t3l],0; jne fail_parse
    mov rdi,[t2p]; mov rcx,[t2l]; call hex_bytes_len; mov r8,rax
    mov rax,r8; call data_reserve
    cmp qword ptr [pass_no],2; jne .Lhd_done
    mov rsi,[t2p]; mov rcx,[t2l]; call decode_hex
.Lhd_done:
    ret

# typed failures
fail_parse:   lea rsi,[msg_parse];   mov edx,15;   mov edi,EXIT_PARSE;  jmp fail
fail_symbol:  lea rsi,[msg_symbol];  mov edx,16;  mov edi,EXIT_SYMBOL; jmp fail
fail_number:  lea rsi,[msg_number];  mov edx,16;  mov edi,EXIT_NUMBER; jmp fail
fail_output:  lea rsi,[msg_output];  mov edx,15;  mov edi,EXIT_OUTPUT; jmp fail
fail_jump:    lea rsi,[msg_jump];    mov edx,12;    mov edi,EXIT_JUMP;   jmp fail
fail_opcode:  lea rsi,[msg_opcode];  mov edx,19;  mov edi,EXIT_OPCODE; jmp fail
fail:
    push rdi
    mov edi,2
    mov eax,SYS_WRITE
    syscall
    pop rdi
    mov eax,SYS_EXIT
    syscall

.section .rodata
lit_data: .asciz ".DATA"
lit_halt: .asciz "HALT"
lit_push: .asciz "PUSH"
lit_add: .asciz "ADD"
lit_sub: .asciz "SUB"
lit_eq: .asciz "EQ"
lit_next: .asciz "NEXT"
lit_hasnext: .asciz "HASNEXT"
lit_assert: .asciz "ASSERT"
lit_emit: .asciz "EMIT"
lit_jmp: .asciz "JMP"
lit_jz: .asciz "JZ"
lit_dup: .asciz "DUP"
lit_drop: .asciz "DROP"
lit_swap: .asciz "SWAP"
lit_emitbuf: .asciz "EMITBUF"
lit_pick: .asciz "PICK"
lit_dataleft: .asciz "DATALEFT"
lit_gt: .asciz "GT"
lit_rawcode: .asciz ".RAWCODE"
lit_rec: .asciz "REC"
lit_raw: .asciz "RAW"
lit_end: .asciz "END"
msg_parse: .ascii "QPARSE_INVALID\n"; .equ msg_parse_len, .-msg_parse
msg_symbol: .ascii "QSYMBOL_INVALID\n"; .equ msg_symbol_len, .-msg_symbol
msg_number: .ascii "QNUMBER_INVALID\n"; .equ msg_number_len, .-msg_number
msg_output: .ascii "QOUTPUT_BOUNDS\n"; .equ msg_output_len, .-msg_output
msg_jump: .ascii "QJUMP_RANGE\n"; .equ msg_jump_len, .-msg_jump
msg_opcode: .ascii "QOP_SOURCE_UNKNOWN\n"; .equ msg_opcode_len, .-msg_opcode

.section .bss
.align 16
input_buf: .skip IN_CAP
output_buf: .skip OUT_CAP
input_len: .quad 0
pass_no: .quad 0
section_data: .quad 0
code_off: .quad 0
data_off: .quad 0
code_len: .quad 0
data_len: .quad 0
line_start: .quad 0
line_end: .quad 0
cursor: .quad 0
t1p: .quad 0
t1l: .quad 0
t2p: .quad 0
t2l: .quad 0
t3p: .quad 0
t3l: .quad 0
t4p: .quad 0
t4l: .quad 0
label_count: .quad 0
label_ptr: .skip MAX_LABELS*8
label_len: .skip MAX_LABELS*8
label_off: .skip MAX_LABELS*8
