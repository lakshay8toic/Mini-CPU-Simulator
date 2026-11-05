;=================================================================
;   MINI CPU SIMULATOR  -  8086 Assembly (emu8086)
;
;   This program simulates a very small CPU.
;   The small CPU runs the  FETCH -> DECODE -> EXECUTE  cycle,
;   and we press a key to see each step.
;
;   Registers of the small CPU:
;       PC  = Program Counter    (address of next instruction)
;       MAR = Memory Address Register
;       MDR = Memory Data Register
;       IR  = Instruction Register
;       ACC = Accumulator        (holds the result)
;
;   Memory : 16 bytes, addresses 00 to 0F
;
;   Every instruction is 1 byte :
;       high 4 bits = OPCODE      low 4 bits = ADDRESS
;       example  2E  ->  opcode 2 (ADD), address E
;
;   Opcode   Instruction    Meaning
;     1      LOAD  addr     ACC <- M[addr]
;     2      ADD   addr     ACC <- ACC + M[addr]
;     3      SUB   addr     ACC <- ACC - M[addr]
;     4      STORE addr     M[addr] <- ACC
;     5      JMP   addr     PC <- addr
;     0      HALT           stop the CPU
;=================================================================

org 100h

jmp start

;-----------------------------------------------------------------
; MEMORY of the small CPU  (program + data)
;
;   address  code   instruction
;     00      1D    LOAD  0D     ACC = 9
;     01      2E    ADD   0E     ACC = 9 + 5  = 14
;     02      3F    SUB   0F     ACC = 14 - 3 = 11
;     03      4C    STORE 0C     M[0C] = 11  (0B in hex)
;     04      56    JMP   06     jump over address 05
;     05      2E    ADD   0E     (skipped because of JMP)
;     06      00    HALT
;     0C      00    result will be stored here
;     0D      09    data  9
;     0E      05    data  5
;     0F      03    data  3
;-----------------------------------------------------------------
ram     db 1Dh, 2Eh, 3Fh, 4Ch, 56h, 2Eh, 00h, 00h
        db 00h, 00h, 00h, 00h, 00h, 09h, 05h, 03h

;-----------------------------------------------------------------
; REGISTERS of the small CPU
;-----------------------------------------------------------------
cpu_pc   db 0          ; Program Counter
cpu_mar  db 0          ; Memory Address Register
cpu_mdr  db 0          ; Memory Data Register
cpu_ir   db 0          ; Instruction Register
cpu_acc  db 0          ; Accumulator

op_code  db 0          ; opcode   (from IR, high 4 bits)
op_addr  db 0          ; address  (from IR, low 4 bits)
halted   db 0          ; becomes 1 after HALT

;-----------------------------------------------------------------
; MESSAGES  ('$' marks the end of each message)
;-----------------------------------------------------------------
msg_title  db '=========== MINI CPU SIMULATOR ===========', 13, 10
           db 'Program : 9 + 5 - 3, result stored at 0C', 13, 10
           db 'Press any key to run each step.', 13, 10, 13, 10, '$'

msg_addr   db 'Address : 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F', 13, 10, '$'
msg_mem    db 'Memory  : $'

msg_line   db '-----------------------------------------------', 13, 10, '$'
msg_fetch  db '[FETCH]   MAR<-PC, MDR<-M[MAR], IR<-MDR, PC<-PC+1', 13, 10, '$'
msg_dec1   db '[DECODE]  opcode = $'
msg_dec2   db ', address = $'
msg_exec   db '[EXECUTE] $'

msg_load   db 'LOAD  : ACC <- M[address]', 13, 10, '$'
msg_add    db 'ADD   : ACC <- ACC + M[address]', 13, 10, '$'
msg_sub    db 'SUB   : ACC <- ACC - M[address]', 13, 10, '$'
msg_store  db 'STORE : M[address] <- ACC', 13, 10, '$'
msg_jmp    db 'JMP   : PC <- address', 13, 10, '$'
msg_halt   db 'HALT  : CPU stopped', 13, 10, '$'

msg_pc     db '          PC=$'
msg_mar    db '  MAR=$'
msg_mdr    db '  MDR=$'
msg_ir     db '  IR=$'
msg_acc    db '  ACC=$'

msg_done   db 13, 10, '========== CPU HALTED ==========', 13, 10
           db 'Result at address 0C = $'
msg_hex    db ' (hex)', 13, 10, 13, 10, '$'
msg_exit   db 13, 10, 'Press any key to exit...$'
newline    db 13, 10, '$'

;=================================================================
;   MAIN PROGRAM
;=================================================================
start:
    lea dx, msg_title
    call print_str
    call show_memory            ; show the program in memory

cpu_cycle:
    lea dx, msg_line
    call print_str

    call wait_key
    call fetch                  ; step 1 : FETCH

    call wait_key
    call decode                 ; step 2 : DECODE

    call wait_key
    call execute                ; step 3 : EXECUTE

    mov al, halted
    cmp al, 1                   ; did the CPU execute HALT ?
    jne cpu_cycle               ; no  -> run the next instruction

    ; ---------- CPU has stopped : show the result ----------
    lea dx, msg_done
    call print_str
    mov al, ram[0Ch]            ; result is in memory address 0C
    call print_hex
    lea dx, msg_hex
    call print_str
    call show_memory

    lea dx, msg_exit
    call print_str
    call wait_key

    mov ah, 4Ch                 ; exit to DOS
    int 21h

;=================================================================
;   FETCH :  MAR <- PC,  MDR <- M[MAR],  IR <- MDR,  PC <- PC + 1
;=================================================================
fetch:
    mov al, cpu_pc
    mov cpu_mar, al             ; MAR <- PC

    mov bl, cpu_mar
    mov bh, 0                   ; BX = address in MAR
    mov al, ram[bx]
    mov cpu_mdr, al             ; MDR <- M[MAR]

    mov cpu_ir, al              ; IR <- MDR

    mov al, cpu_pc
    inc al
    and al, 0Fh                 ; keep PC between 00 and 0F
    mov cpu_pc, al              ; PC <- PC + 1

    lea dx, msg_fetch
    call print_str
    call show_regs
    ret

;=================================================================
;   DECODE :  split IR into opcode (high 4 bits) and address (low 4 bits)
;=================================================================
decode:
    mov al, cpu_ir
    mov cl, 4
    shr al, cl                  ; shift right 4 times -> high 4 bits
    mov op_code, al

    mov al, cpu_ir
    and al, 0Fh                 ; keep only the low 4 bits
    mov op_addr, al

    lea dx, msg_dec1
    call print_str
    mov al, op_code
    call print_hex
    lea dx, msg_dec2
    call print_str
    mov al, op_addr
    call print_hex
    lea dx, newline
    call print_str
    ret

;=================================================================
;   EXECUTE :  do the work of the instruction
;=================================================================
execute:
    lea dx, msg_exec
    call print_str

    mov bl, op_addr
    mov bh, 0                   ; BX = address part of the instruction

    mov al, op_code
    cmp al, 1
    je do_load
    cmp al, 2
    je do_add
    cmp al, 3
    je do_sub
    cmp al, 4
    je do_store
    cmp al, 5
    je do_jmp
    jmp do_halt                 ; opcode 0 (or unknown) = HALT

do_load:                        ; ACC <- M[address]
    mov cpu_mar, bl
    mov al, ram[bx]
    mov cpu_mdr, al
    mov cpu_acc, al
    lea dx, msg_load
    jmp exec_end

do_add:                         ; ACC <- ACC + M[address]
    mov cpu_mar, bl
    mov al, ram[bx]
    mov cpu_mdr, al
    add cpu_acc, al
    lea dx, msg_add
    jmp exec_end

do_sub:                         ; ACC <- ACC - M[address]
    mov cpu_mar, bl
    mov al, ram[bx]
    mov cpu_mdr, al
    sub cpu_acc, al
    lea dx, msg_sub
    jmp exec_end

do_store:                       ; M[address] <- ACC
    mov cpu_mar, bl
    mov al, cpu_acc
    mov cpu_mdr, al
    mov ram[bx], al
    lea dx, msg_store
    jmp exec_end

do_jmp:                         ; PC <- address
    mov cpu_pc, bl
    lea dx, msg_jmp
    jmp exec_end

do_halt:                        ; stop the CPU
    mov al, 1
    mov halted, al
    lea dx, msg_halt

exec_end:
    call print_str              ; print what was executed
    call show_regs
    ret

;=================================================================
;   SHOW_REGS :  print PC, MAR, MDR, IR and ACC
;=================================================================
show_regs:
    lea dx, msg_pc
    call print_str
    mov al, cpu_pc
    call print_hex

    lea dx, msg_mar
    call print_str
    mov al, cpu_mar
    call print_hex

    lea dx, msg_mdr
    call print_str
    mov al, cpu_mdr
    call print_hex

    lea dx, msg_ir
    call print_str
    mov al, cpu_ir
    call print_hex

    lea dx, msg_acc
    call print_str
    mov al, cpu_acc
    call print_hex

    lea dx, newline
    call print_str
    ret

;=================================================================
;   SHOW_MEMORY :  print all 16 bytes of memory
;=================================================================
show_memory:
    lea dx, msg_addr
    call print_str
    lea dx, msg_mem
    call print_str

    mov bx, 0
mem_loop:
    mov al, ram[bx]
    call print_hex
    mov dl, ' '
    mov ah, 2
    int 21h                     ; print a space
    inc bx
    cmp bx, 16
    jb mem_loop

    lea dx, newline
    call print_str
    ret

;=================================================================
;   HELPER ROUTINES
;=================================================================

; print_str : print the '$'-ended message whose address is in DX
print_str:
    mov ah, 9
    int 21h
    ret

; wait_key : wait until a key is pressed (no echo)
wait_key:
    mov ah, 7
    int 21h
    ret

; print_hex : print the byte in AL as 2 hex digits (example 3F)
print_hex:
    push ax
    push cx
    mov ch, al                  ; save the number
    mov cl, 4
    shr al, cl                  ; high 4 bits
    call print_digit
    mov al, ch
    and al, 0Fh                 ; low 4 bits
    call print_digit
    pop cx
    pop ax
    ret

; print_digit : print AL (0 to 15) as one hex digit 0-9 / A-F
print_digit:
    push dx
    cmp al, 10
    jb is_number
    add al, 7                   ; 10..15 -> 'A'..'F'
is_number:
    add al, '0'
    mov dl, al
    mov ah, 2
    int 21h
    pop dx
    ret
