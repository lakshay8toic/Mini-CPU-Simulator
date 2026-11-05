;=============================================================================
;  MINI CPU SIMULATOR  -  5-Stage Processor, written in 8086 Assembly
;-----------------------------------------------------------------------------
;  Course   : Computer Organization & System Architecture (Units I - III)
;  Target   : emu8086  (assembles as a .COM program, org 100h)
;
;  This program simulates a tiny 8-bit processor, built on the five-stage
;  organisation used in "Execution of a Complete Instruction" (Unit II):
;
;      1 FETCH  ->  2 DECODE  ->  3 ALU  ->  4 MEMORY  ->  5 WRITE-BACK
;
;  Each key press runs ONE stage (one clock cycle).  The screen shows the
;  register-transfer (RTL) action, the control signals that are active, the
;  processor registers (PC, IR, MA, MD), the inter-stage registers
;  (RA, RB, RZ, RM, RY), the register file (R0-R3), the flags and memory.
;
;  Simulated machine
;    * 64 bytes of memory (addresses 00h - 3Fh)
;    * 4 general registers R0..R3   (R0 is hard-wired to 0)
;    * 16-bit instructions = 2 bytes:
;          byte 0 : [ OPCODE (7-4) | Rdst (3-2) | Rsrc (1-0) ]
;          byte 1 : Rsrc2 (R-format)  or  immediate / address X
;    * Flags : Z (zero), C (carry / borrow)
;
;  Opcodes
;    0 HALT                 1 ADD  Rd,Rs,Rt      2 SUB  Rd,Rs,Rt
;    3 AND  Rd,Rs,Rt        4 OR   Rd,Rs,Rt      5 ADDI Rd,Rs,#imm
;    6 LOAD Rd,X(Rs)        7 STORE Rd,X(Rs)     8 BEQ  Rd,Rs,X
;    9 JMP  X               A OUT  Rs
;
;  Keys while simulating
;    Enter / Space : run the next stage (one clock cycle)
;    I             : run until the current instruction completes
;    R             : run the whole program up to HALT
;    Q / Esc       : back to the main menu
;=============================================================================

org 100h

jmp start

;=============================================================================
;                                   DATA
;=============================================================================

; ---------------- simulated memory, registers and CPU state -----------------
mem         db 64 dup(0)        ; main memory of the simulated CPU
regs        db 4 dup(0)         ; register file R0..R3

v_pc        db 0                ; program counter
v_ipc       db 0                ; address of the instruction being executed
v_ir0       db 0                ; instruction register, byte 0
v_ir1       db 0                ; instruction register, byte 1
v_ma        db 0                ; memory address register  (MA / MAR)
v_md        db 0                ; memory data register     (MD / MDR)
v_ra        db 0                ; inter-stage register RA (ALU input A)
v_rb        db 0                ; inter-stage register RB (ALU input B)
v_rz        db 0                ; inter-stage register RZ (ALU output)
v_rm        db 0                ; inter-stage register RM (store data)
v_ry        db 0                ; inter-stage register RY (write-back data)
v_zf        db 0                ; zero flag
v_cf        db 0                ; carry flag

v_op        db 0                ; decoded fields of the IR
v_rd        db 0
v_rs        db 0
v_rt        db 0

v_step      db 1                ; next stage to execute (1..5)
v_shown     db 0                ; stage that was just executed (0 = reset)
v_halt      db 0                ; 0 run, 1 HALT, 2 step limit, 3 illegal
v_fetched   db 0                ; 1 once an instruction has been fetched
v_lastw     db 0FFh             ; address of the last memory write
v_mode      db 0                ; 0 stage, 1 instruction, 2 run
v_icount    dw 0                ; instructions completed
v_clock     dw 0                ; clock cycles (stages) executed

v_outlen    db 0                ; values sent to the output port
outbuf      db 20 dup(0)

p_act       dw 0                ; text: RTL action of the shown stage
p_sig       dw 0                ; text: control signals of the shown stage
p_name      dw 0                ; text: name of the loaded program

d_op        db 0                ; scratch fields for the disassembler
d_rd        db 0
d_rs        db 0
d_rt        db 0
d_b1        db 0

; ------------------------------ demo programs -------------------------------
; Demo 1 : the three instructions from the slides - Load, Add, Store
;   00  64 30   LOAD  R1, 30h(R0)    R1 <- Mem[30h]  (= 7)
;   02  68 31   LOAD  R2, 31h(R0)    R2 <- Mem[31h]  (= 5)
;   04  1D 02   ADD   R3, R1, R2     R3 <- R1 + R2   (= 0Ch = 12)
;   06  7C 32   STORE R3, 32h(R0)    Mem[32h] <- R3
;   08  A3 00   OUT   R3             print R3
;   0A  00 00   HALT
demo1   db 064h,030h,068h,031h,01Dh,002h,07Ch,032h,0A3h,000h,000h,000h,0,0,0,0
        db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        db 007h,005h,0,0,0,0,0,0,0,0,0,0,0,0,0,0

; Demo 2 : countdown loop 5..0 - immediate mode, BEQ and JMP
;   00  54 05   ADDI  R1, R0, #5     R1 <- 5
;   02  A1 00   OUT   R1             loop: print R1
;   04  55 FF   ADDI  R1, R1, #-1    R1 <- R1 - 1
;   06  84 0A   BEQ   R1, R0, 0Ah    if R1 = 0 goto done
;   08  90 02   JMP   02h            goto loop
;   0A  A1 00   OUT   R1             done: print R1 (0)
;   0C  00 00   HALT
demo2   db 054h,005h,0A1h,000h,055h,0FFh,084h,00Ah,090h,002h,0A1h,000h,000h,000h,0,0
        db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

; Demo 3 : sum of an array of 5 numbers - index addressing X(Rs)
;   00  54 00   ADDI  R1, R0, #0     sum = 0
;   02  58 05   ADDI  R2, R0, #5     i = 5
;   04  6E 2F   LOAD  R3, 2Fh(R2)    loop: R3 <- Mem[2Fh + i]
;   06  15 03   ADD   R1, R1, R3     sum = sum + R3
;   08  5A FF   ADDI  R2, R2, #-1    i = i - 1
;   0A  88 0E   BEQ   R2, R0, 0Eh    if i = 0 goto done
;   0C  90 04   JMP   04h            goto loop
;   0E  74 3F   STORE R1, 3Fh(R0)    done: Mem[3Fh] <- sum
;   10  A1 00   OUT   R1             print sum (12h = 18)
;   12  00 00   HALT
;   30..34 = 03 05 02 07 01          the array
demo3   db 054h,000h,058h,005h,06Eh,02Fh,015h,003h,05Ah,0FFh,088h,00Eh,090h,004h,074h,03Fh
        db 0A1h,000h,000h,000h,0,0,0,0,0,0,0,0,0,0,0,0
        db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        db 003h,005h,002h,007h,001h,0,0,0,0,0,0,0,0,0,0,0

; --------------------------------- text --------------------------------------
m_crlf      db 13,10,'$'
m_sp2       db '  $'
m_sp3       db '   $'
m_comma     db ', $'

m_menu      db 13,10
            db '  +==========================================================+',13,10
            db '  |            M I N I   C P U   S I M U L A T O R           |',13,10
            db '  |      5-stage processor : Fetch-Decode-ALU-Memory-WB      |',13,10
            db '  |           COA  Units I-III  project  (8086 / emu8086)    |',13,10
            db '  +==========================================================+',13,10
            db 13,10
            db '     1.  Demo 1 : Load - Add - Store   (7 + 5 = 12)',13,10
            db '     2.  Demo 2 : Countdown loop 5..0  (immediate, BEQ, JMP)',13,10
            db '     3.  Demo 3 : Array sum            (index addressing)',13,10
            db '     4.  Enter your own program        (hex machine code)',13,10
            db '     5.  Show the instruction set',13,10
            db '     6.  Exit',13,10
            db 13,10
            db '     Choose 1-6 : $'

m_n1        db 'Demo 1 - Load / Add / Store$'
m_n2        db 'Demo 2 - Countdown loop$'
m_n3        db 'Demo 3 - Array sum (index mode)$'
m_n4        db 'Your own program$'

m_bye       db 13,10,'  Mini CPU Simulator - goodbye!',13,10,'$'

m_isa       db ' INSTRUCTION SET   (2-byte instructions, registers R0-R3, R0 is always 0)',13,10
            db ' Byte 0 = [ OPCODE bits 7-4 | Rdst bits 3-2 | Rsrc bits 1-0 ]',13,10
            db ' Byte 1 = Rsrc2 (register form)  or  immediate / address X',13,10
            db ' -------------------------------------------------------------------------',13,10
            db ' Op  Instruction        Operation                      Addressing mode',13,10
            db ' -------------------------------------------------------------------------',13,10
            db ' 0   HALT               stop the processor             -',13,10
            db ' 1   ADD   Rd,Rs,Rt     Rd <- [Rs] + [Rt]              register',13,10
            db ' 2   SUB   Rd,Rs,Rt     Rd <- [Rs] - [Rt]              register',13,10
            db ' 3   AND   Rd,Rs,Rt     Rd <- [Rs] AND [Rt]            register',13,10
            db ' 4   OR    Rd,Rs,Rt     Rd <- [Rs] OR [Rt]             register',13,10
            db ' 5   ADDI  Rd,Rs,#imm   Rd <- [Rs] + imm               immediate',13,10
            db ' 6   LOAD  Rd,X(Rs)     Rd <- Mem[X + [Rs]]            index, absolute if R0',13,10
            db ' 7   STORE Rd,X(Rs)     Mem[X + [Rs]] <- [Rd]          index, absolute if R0',13,10
            db ' 8   BEQ   Rd,Rs,X      if [Rd] = [Rs] then PC <- X    absolute branch',13,10
            db ' 9   JMP   X            PC <- X                        absolute',13,10
            db ' A   OUT   Rs           output port <- [Rs]            register',13,10
            db ' -------------------------------------------------------------------------',13,10
            db ' Examples:  64 30 = LOAD R1,30h(R0)   1D 02 = ADD R3,R1,R2   90 02 = JMP 02h',13,10
            db ' Every instruction: 1 FETCH -> 2 DECODE -> 3 ALU -> 4 MEMORY -> 5 WRITE-BACK',13,10
            db 13,10
            db ' Press any key to return to the menu...$'

m_cust      db 13,10
            db ' ENTER YOUR OWN PROGRAM',13,10
            db ' Type 2 hex digits for each memory byte (00-3F).',13,10
            db ' Type a dot  .  to finish - all remaining bytes become 00.',13,10
            db ' Data usually goes at address 30h and above.',13,10,13,10,'$'
m_cust_a    db '   [$'
m_cust_b    db 'h] = $'

m_lst_t     db 13,10,' PROGRAM LISTING : $'
m_lst_h     db 13,10,' ADDR   CODE    INSTRUCTION',13,10
            db ' ----   -----   ---------------------------',13,10,'$'
m_lst_d     db ' DATA  30h-3Fh : $'
m_start     db ' Press any key to start the simulator...$'

m_title     db ' MINI CPU SIMULATOR  -  5-stage processor            8086 / emu8086',13,10,'$'
m_sep       db ' ------------------------------------------------------------------------------',13,10,'$'
m_prog      db ' Program: $'
m_instr     db '    Instructions: $'
m_clock     db '   Clock: $'
m_ir        db ' Instruction : $'
m_at        db '   @ $'
m_nofetch   db '-- --   (nothing fetched yet)$'
m_stage     db ' Stage : $'
m_act       db ' Action  : $'
m_sig       db ' Signals : $'

st_1        db '1 FETCH$'
st_2        db '2 DECODE$'
st_3        db '3 ALU$'
st_4        db '4 MEMORY$'
st_5        db '5 WRITE-BACK$'

l_pc        db ' PC=$'
l_ir        db '  IR=$'
l_ma        db '  MA=$'
l_md        db '  MD=$'
l_flags     db '        Flags: Z=$'
l_c         db '  C=$'
l_ra        db ' RA=$'
l_rb        db '  RB=$'
l_rz        db '  RZ=$'
l_rm        db '  RM=$'
l_ry        db '  RY=$'
l_inter     db '      (inter-stage registers)$'
l_r0        db ' R0=$'
l_r1        db '  R1=$'
l_r2        db '  R2=$'
l_r3        db '  R3=$'
l_file      db '             (register file)$'

m_memhdr    db ' MEMORY   +0 +1 +2 +3 +4 +5 +6 +7 +8 +9 +A +B +C +D +E +F',13,10,'$'
m_legend    db '          > = current instruction    * = last memory write',13,10,'$'
m_out       db ' OUTPUT : $'
m_none      db '(none)$'
m_lastdec   db '  (last = $'
m_dec       db ' decimal)$'

m_help      db ' [Enter] next stage  [I] next instruction  [R] run to HALT  [Q] menu$'
m_hlt1      db ' *** HALT : program finished.  Press any key for the menu ***$'
m_hlt2      db ' *** Stopped : step limit reached.  Press any key for the menu ***$'
m_hlt3      db ' *** Illegal opcode : CPU stopped.  Press any key for the menu ***$'

; mnemonic table : 7 bytes per entry (6 characters + '$')
mn_tbl      db 'HALT  $'
            db 'ADD   $'
            db 'SUB   $'
            db 'AND   $'
            db 'OR    $'
            db 'ADDI  $'
            db 'LOAD  $'
            db 'STORE $'
            db 'BEQ   $'
            db 'JMP   $'
            db 'OUT   $'
            db '???   $'

; ------------------- RTL actions and control signals ------------------------
a_reset     db 'CPU reset, PC = 00h.  Press Enter to fetch the first instruction.$'
a_fetch     db 'MA <- [PC], IR <- Mem[MA], PC <- [PC] + 2$'
s_fetch     db 'PCout, MAin, MEMread, MDout, IRin, INC2, PCin$'
a_dec       db 'Decode IR, RA <- [Rsrc], RB <- [Rsrc2]$'
s_dec       db 'RF_Aout, RF_Bout, RAin, RBin$'
a_decj      db 'Decode IR, JMP needs no register operands$'
s_decj      db 'decoder only$'
a_halt      db 'Decode IR, HALT -> the control unit stops the clock$'
s_halt      db 'HALT$'
a_ill       db 'Decode IR, unknown opcode -> CPU stopped$'
a_limit     db 'Step limit reached (infinite loop?) - simulation stopped$'
a_add       db 'RZ <- [RA] + [RB]$'
s_add       db 'RAout, MuxB=RB, ALU_add, RZin$'
a_sub       db 'RZ <- [RA] - [RB]$'
s_sub       db 'RAout, MuxB=RB, ALU_sub, RZin$'
a_and       db 'RZ <- [RA] AND [RB]$'
s_and       db 'RAout, MuxB=RB, ALU_and, RZin$'
a_or        db 'RZ <- [RA] OR [RB]$'
s_or        db 'RAout, MuxB=RB, ALU_or, RZin$'
a_addi      db 'RZ <- [RA] + Immediate$'
s_imm       db 'RAout, MuxB=Imm, ALU_add, RZin$'
a_ea        db 'RZ <- [RA] + X   (effective address)$'
a_eas       db 'RZ <- [RA] + X (effective address), RM <- [RB]$'
s_eas       db 'RAout, MuxB=Imm, ALU_add, RZin, RMin$'
a_beqt      db 'Compare [RB] - [RA] = 0 : equal -> PC <- X  (branch taken)$'
s_beqt      db 'ALU_sub, Imm out, MuxPC, PCin$'
a_beqn      db 'Compare [RB] - [RA] <> 0 : not equal -> PC unchanged$'
s_beqn      db 'ALU_sub$'
a_jmp       db 'PC <- X   (jump target taken from the IR)$'
s_jmp       db 'Imm out, MuxPC, PCin$'
a_pass      db 'RZ <- [RA]   (ALU passes the value through)$'
s_pass      db 'RAout, ALU_pass, RZin$'
a_ry        db 'RY <- [RZ]   (no memory access needed)$'
s_ry        db 'RZout, MuxY=RZ, RYin$'
a_load      db 'MA <- [RZ], MD <- Mem[MA], RY <- [MD]$'
s_load      db 'MAin, MEMread, MuxY=MD, RYin$'
a_store     db 'MA <- [RZ], Mem[MA] <- [RM]$'
s_store     db 'MAin, RMout, MEMwrite$'
a_out       db 'OUTPUT PORT <- [RZ]$'
s_out       db 'RZout, IOwrite$'
a_none      db 'No action in this stage$'
s_none      db '-$'
a_wb        db 'Rdst <- [RY]$'
s_wb        db 'RYout, RF_Cin$'
a_wb0       db 'Rdst is R0 (hard-wired 0) : write ignored$'

;=============================================================================
;                                   CODE
;=============================================================================

start:
main_menu:
    call cls
    mov dx, offset m_menu
    call puts
mm_key:
    call getkey
    cmp al, '1'
    jne mm_2
    mov si, offset demo1
    mov dx, offset m_n1
    jmp mm_load
mm_2:
    cmp al, '2'
    jne mm_3
    mov si, offset demo2
    mov dx, offset m_n2
    jmp mm_load
mm_3:
    cmp al, '3'
    jne mm_4
    mov si, offset demo3
    mov dx, offset m_n3
    jmp mm_load
mm_4:
    cmp al, '4'
    jne mm_5
    call custom_prog
    jmp mm_run
mm_5:
    cmp al, '5'
    jne mm_6
    call show_isa
    jmp main_menu
mm_6:
    cmp al, '6'
    je mm_exit
    cmp al, 27
    je mm_exit
    jmp mm_key
mm_load:
    call load_prog
mm_run:
    call show_listing
    call run_sim
    jmp main_menu
mm_exit:
    call cls
    mov dx, offset m_bye
    call puts
    mov ax, 4C00h
    int 21h

;-----------------------------------------------------------------------------
; load_prog : copy 64 bytes from DS:SI into mem, DX = program name
;-----------------------------------------------------------------------------
load_prog:
    mov word ptr [p_name], dx
    mov di, offset mem
    mov cx, 64
    cld
    rep movsb
    ret

;-----------------------------------------------------------------------------
; custom_prog : let the user type machine code byte by byte
;-----------------------------------------------------------------------------
custom_prog:
    mov word ptr [p_name], offset m_n4
    mov di, offset mem
    mov cx, 64
    mov al, 0
    cld
    rep stosb
    call cls
    mov dx, offset m_cust
    call puts
    xor bx, bx
cp_loop:
    mov dx, offset m_cust_a
    call puts
    mov al, bl
    call put_hex8
    mov dx, offset m_cust_b
    call puts
    call get_hex_byte
    jc cp_done
    mov [mem+bx], al
    call newline
    inc bx
    cmp bx, 64
    jb cp_loop
cp_done:
    call newline
    ret

; get_hex_byte : read 2 hex digits -> AL.  CF = 1 if '.' was typed
get_hex_byte:
    push bx
    call get_nib
    jc ghb_end
    mov bl, al
    call get_nib
    jc ghb_end
    mov cl, 4
    shl bl, cl
    or al, bl
    clc
ghb_end:
    pop bx
    ret

; get_nib : read one hex digit (echoed) -> AL = 0..15.  CF = 1 on '.'
get_nib:
    call getkey
    cmp al, '.'
    jne gn_1
    stc
    ret
gn_1:
    cmp al, 'a'
    jb gn_2
    cmp al, 'f'
    ja gn_bad
    sub al, 20h                 ; to upper case
gn_2:
    cmp al, '0'
    jb gn_bad
    cmp al, '9'
    jbe gn_dig
    cmp al, 'A'
    jb gn_bad
    cmp al, 'F'
    ja gn_bad
    mov dl, al
    call putc
    sub al, 37h                 ; 'A'..'F' -> 10..15
    clc
    ret
gn_dig:
    mov dl, al
    call putc
    sub al, '0'
    clc
    ret
gn_bad:
    mov dl, 7                   ; beep and try again
    call putc
    jmp get_nib

;-----------------------------------------------------------------------------
; show_isa : print the instruction set table
;-----------------------------------------------------------------------------
show_isa:
    call cls
    mov dx, offset m_isa
    call puts
    call getkey
    ret

;-----------------------------------------------------------------------------
; show_listing : disassemble the program in memory
;-----------------------------------------------------------------------------
show_listing:
    call cls
    mov dx, offset m_lst_t
    call puts
    mov dx, word ptr [p_name]
    call puts
    call newline
    mov dx, offset m_lst_h
    call puts
    xor bx, bx
sl_loop:
    mov dx, offset m_sp2
    call puts
    mov al, bl
    call put_hex8
    mov dx, offset m_sp3
    call puts
    mov al, [mem+bx]
    call put_hex8
    mov dl, ' '
    call putc
    mov al, [mem+bx+1]
    call put_hex8
    mov dx, offset m_sp3
    call puts
    mov al, [mem+bx]
    mov ah, [mem+bx+1]
    call disasm
    call newline
    mov al, [mem+bx]
    and al, 0F0h
    jz sl_data                  ; stop after HALT
    add bx, 2
    cmp bx, 30h
    jb sl_loop
sl_data:
    call newline
    mov dx, offset m_lst_d
    call puts
    mov bx, 30h
sl_d1:
    mov al, [mem+bx]
    call put_hex8
    mov dl, ' '
    call putc
    inc bx
    cmp bx, 40h
    jb sl_d1
    call newline
    call newline
    mov dx, offset m_start
    call puts
    call getkey
    ret

;=============================================================================
;                          SIMULATOR MAIN LOOP
;=============================================================================
run_sim:
    call cpu_reset
rs_draw:
    call draw
    cmp byte ptr [v_halt], 0
    jne rs_stopped
    call getkey
    cmp al, 'q'
    je rs_quit
    cmp al, 'Q'
    je rs_quit
    cmp al, 27
    je rs_quit
    mov byte ptr [v_mode], 0
    cmp al, 'i'
    je rs_m1
    cmp al, 'I'
    je rs_m1
    cmp al, 'r'
    je rs_m2
    cmp al, 'R'
    je rs_m2
    jmp rs_exec
rs_m1:
    mov byte ptr [v_mode], 1
    jmp rs_exec
rs_m2:
    mov byte ptr [v_mode], 2
rs_exec:
    call do_step
    cmp byte ptr [v_halt], 0
    jne rs_draw
    cmp byte ptr [v_mode], 0
    je rs_draw
    cmp byte ptr [v_mode], 1
    jne rs_run
    cmp byte ptr [v_step], 1    ; instruction finished ?
    je rs_draw
    jmp rs_exec
rs_run:
    cmp word ptr [v_clock], 2000
    jb rs_exec
    mov byte ptr [v_halt], 2
    mov word ptr [p_act], offset a_limit
    mov word ptr [p_sig], offset s_none
    jmp rs_draw
rs_stopped:
    call getkey
rs_quit:
    ret

;-----------------------------------------------------------------------------
; cpu_reset : clear every register (memory keeps the loaded program)
;-----------------------------------------------------------------------------
cpu_reset:
    mov al, 0
    mov byte ptr [regs], al
    mov byte ptr [regs+1], al
    mov byte ptr [regs+2], al
    mov byte ptr [regs+3], al
    mov [v_pc], al
    mov [v_ipc], al
    mov [v_ir0], al
    mov [v_ir1], al
    mov [v_ma], al
    mov [v_md], al
    mov [v_ra], al
    mov [v_rb], al
    mov [v_rz], al
    mov [v_rm], al
    mov [v_ry], al
    mov [v_zf], al
    mov [v_cf], al
    mov [v_op], al
    mov [v_rd], al
    mov [v_rs], al
    mov [v_rt], al
    mov [v_shown], al
    mov [v_halt], al
    mov [v_fetched], al
    mov [v_mode], al
    mov [v_outlen], al
    mov byte ptr [v_step], 1
    mov byte ptr [v_lastw], 0FFh
    mov word ptr [v_icount], 0
    mov word ptr [v_clock], 0
    mov word ptr [p_act], offset a_reset
    mov word ptr [p_sig], offset s_none
    ret

;=============================================================================
; do_step : execute ONE stage (one clock cycle) of the current instruction
;=============================================================================
do_step:
    inc word ptr [v_clock]
    mov al, [v_step]
    mov [v_shown], al
    cmp al, 1
    jne dstep_2
    jmp st_fetch
dstep_2:
    cmp al, 2
    jne dstep_3
    jmp st_decode
dstep_3:
    cmp al, 3
    jne dstep_4
    jmp st_alu
dstep_4:
    cmp al, 4
    jne dstep_5
    jmp st_mem
dstep_5:
    jmp st_wb

; advance to the next stage; after stage 5 the instruction is complete
dstep_adv:
    cmp byte ptr [v_step], 5
    jb dstep_inc
    mov byte ptr [v_step], 1
    inc word ptr [v_icount]
    ret
dstep_inc:
    inc byte ptr [v_step]
    ret

; ---------------------------------------------------------------- STAGE 1 --
; FETCH : MA <- PC, IR <- Mem[MA], PC <- PC + 2
st_fetch:
    mov bl, [v_pc]
    xor bh, bh
    mov [v_ipc], bl
    mov [v_ma], bl
    mov al, [mem+bx]
    mov [v_ir0], al
    mov [v_md], al
    inc bl
    and bl, 3Fh
    mov al, [mem+bx]
    mov [v_ir1], al
    inc bl
    and bl, 3Fh
    mov [v_pc], bl
    mov byte ptr [v_fetched], 1
    ; split the instruction into its fields (hard-wired decoding)
    mov al, [v_ir0]
    mov ah, al
    mov cl, 4
    shr al, cl
    mov [v_op], al
    mov al, ah
    shr al, 1
    shr al, 1
    and al, 3
    mov [v_rd], al
    mov al, ah
    and al, 3
    mov [v_rs], al
    mov al, [v_ir1]
    and al, 3
    mov [v_rt], al
    mov word ptr [p_act], offset a_fetch
    mov word ptr [p_sig], offset s_fetch
    jmp dstep_adv

; ---------------------------------------------------------------- STAGE 2 --
; DECODE : RA <- [Rsrc], RB <- [Rsrc2]   (HALT stops here)
st_decode:
    mov al, [v_op]
    cmp al, 0
    jne dc_1
    mov byte ptr [v_halt], 1
    inc word ptr [v_icount]
    mov word ptr [p_act], offset a_halt
    mov word ptr [p_sig], offset s_halt
    ret
dc_1:
    cmp al, 0Ah
    jbe dc_2
    mov byte ptr [v_halt], 3
    mov word ptr [p_act], offset a_ill
    mov word ptr [p_sig], offset s_none
    ret
dc_2:
    mov bl, [v_rs]
    xor bh, bh
    mov al, [regs+bx]
    mov [v_ra], al
    mov bl, [v_rd]              ; port B reads Rd ...
    cmp byte ptr [v_op], 4
    ja dc_3
    mov bl, [v_rt]              ; ... or Rt for register-form ALU ops
dc_3:
    xor bh, bh
    mov al, [regs+bx]
    mov [v_rb], al
    mov word ptr [p_act], offset a_dec
    mov word ptr [p_sig], offset s_dec
    cmp byte ptr [v_op], 9
    jne dc_4
    mov word ptr [p_act], offset a_decj
    mov word ptr [p_sig], offset s_decj
dc_4:
    jmp dstep_adv

; ---------------------------------------------------------------- STAGE 3 --
; ALU : compute a result, an effective address, or a branch decision
st_alu:
    mov al, [v_op]
    cmp al, 1
    jne alu_2
    mov al, [v_ra]
    add al, [v_rb]
    call set_flags
    mov [v_rz], al
    mov word ptr [p_act], offset a_add
    mov word ptr [p_sig], offset s_add
    jmp dstep_adv
alu_2:
    cmp al, 2
    jne alu_3
    mov al, [v_ra]
    sub al, [v_rb]
    call set_flags
    mov [v_rz], al
    mov word ptr [p_act], offset a_sub
    mov word ptr [p_sig], offset s_sub
    jmp dstep_adv
alu_3:
    cmp al, 3
    jne alu_4
    mov al, [v_ra]
    and al, [v_rb]
    call set_flags
    mov [v_rz], al
    mov word ptr [p_act], offset a_and
    mov word ptr [p_sig], offset s_and
    jmp dstep_adv
alu_4:
    cmp al, 4
    jne alu_5
    mov al, [v_ra]
    or al, [v_rb]
    call set_flags
    mov [v_rz], al
    mov word ptr [p_act], offset a_or
    mov word ptr [p_sig], offset s_or
    jmp dstep_adv
alu_5:
    cmp al, 5
    jne alu_6
    mov al, [v_ra]
    add al, [v_ir1]
    call set_flags
    mov [v_rz], al
    mov word ptr [p_act], offset a_addi
    mov word ptr [p_sig], offset s_imm
    jmp dstep_adv
alu_6:
    cmp al, 6
    jne alu_7
    mov al, [v_ra]
    add al, [v_ir1]
    and al, 3Fh
    mov [v_rz], al
    mov word ptr [p_act], offset a_ea
    mov word ptr [p_sig], offset s_imm
    jmp dstep_adv
alu_7:
    cmp al, 7
    jne alu_8
    mov al, [v_ra]
    add al, [v_ir1]
    and al, 3Fh
    mov [v_rz], al
    mov al, [v_rb]
    mov [v_rm], al
    mov word ptr [p_act], offset a_eas
    mov word ptr [p_sig], offset s_eas
    jmp dstep_adv
alu_8:
    cmp al, 8
    jne alu_9
    mov al, [v_rb]
    sub al, [v_ra]
    call set_flags
    mov [v_rz], al
    cmp byte ptr [v_zf], 1
    jne alu_8n
    mov al, [v_ir1]
    and al, 3Fh
    mov [v_pc], al
    mov word ptr [p_act], offset a_beqt
    mov word ptr [p_sig], offset s_beqt
    jmp dstep_adv
alu_8n:
    mov word ptr [p_act], offset a_beqn
    mov word ptr [p_sig], offset s_beqn
    jmp dstep_adv
alu_9:
    cmp al, 9
    jne alu_a
    mov al, [v_ir1]
    and al, 3Fh
    mov [v_pc], al
    mov word ptr [p_act], offset a_jmp
    mov word ptr [p_sig], offset s_jmp
    jmp dstep_adv
alu_a:
    mov al, [v_ra]              ; OUT : pass RA through the ALU
    mov [v_rz], al
    mov word ptr [p_act], offset a_pass
    mov word ptr [p_sig], offset s_pass
    jmp dstep_adv

; copy the 8086 Z and C flags of the last ALU instruction into v_zf / v_cf
; (MOV and the jumps below do not change the flags)
set_flags:
    mov byte ptr [v_zf], 0
    mov byte ptr [v_cf], 0
    jnz sf_1
    mov byte ptr [v_zf], 1
sf_1:
    jnc sf_2
    mov byte ptr [v_cf], 1
sf_2:
    ret

; ---------------------------------------------------------------- STAGE 4 --
; MEMORY : load / store data, or pass RZ to RY
st_mem:
    mov al, [v_op]
    cmp al, 5
    ja me_6
    mov al, [v_rz]              ; ALU instructions : RY <- RZ
    mov [v_ry], al
    mov word ptr [p_act], offset a_ry
    mov word ptr [p_sig], offset s_ry
    jmp dstep_adv
me_6:
    cmp al, 6
    jne me_7
    mov bl, [v_rz]              ; LOAD
    xor bh, bh
    mov [v_ma], bl
    mov al, [mem+bx]
    mov [v_md], al
    mov [v_ry], al
    mov word ptr [p_act], offset a_load
    mov word ptr [p_sig], offset s_load
    jmp dstep_adv
me_7:
    cmp al, 7
    jne me_a
    mov bl, [v_rz]              ; STORE
    xor bh, bh
    mov [v_ma], bl
    mov al, [v_rm]
    mov [v_md], al
    mov [mem+bx], al
    mov [v_lastw], bl
    mov word ptr [p_act], offset a_store
    mov word ptr [p_sig], offset s_store
    jmp dstep_adv
me_a:
    cmp al, 0Ah
    jne me_none
    mov bl, [v_outlen]          ; OUT : append RZ to the output port
    cmp bl, 20
    jae me_a2
    xor bh, bh
    mov al, [v_rz]
    mov [outbuf+bx], al
    inc byte ptr [v_outlen]
me_a2:
    mov word ptr [p_act], offset a_out
    mov word ptr [p_sig], offset s_out
    jmp dstep_adv
me_none:
    mov word ptr [p_act], offset a_none
    mov word ptr [p_sig], offset s_none
    jmp dstep_adv

; ---------------------------------------------------------------- STAGE 5 --
; WRITE-BACK : Rdst <- RY
st_wb:
    mov al, [v_op]
    cmp al, 6
    ja wb_none
    mov bl, [v_rd]
    cmp bl, 0
    jne wb_1
    mov word ptr [p_act], offset a_wb0
    mov word ptr [p_sig], offset s_none
    jmp dstep_adv
wb_1:
    xor bh, bh
    mov al, [v_ry]
    mov [regs+bx], al
    mov word ptr [p_act], offset a_wb
    mov word ptr [p_sig], offset s_wb
    jmp dstep_adv
wb_none:
    mov word ptr [p_act], offset a_none
    mov word ptr [p_sig], offset s_none
    jmp dstep_adv

;=============================================================================
; draw : paint the whole simulator screen
;=============================================================================
draw:
    call cls
    mov dx, offset m_title
    call puts
    ; program name, instruction and clock counters
    mov dx, offset m_prog
    call puts
    mov dx, word ptr [p_name]
    call puts
    mov dx, offset m_instr
    call puts
    mov ax, word ptr [v_icount]
    call put_dec16
    mov dx, offset m_clock
    call puts
    mov ax, word ptr [v_clock]
    call put_dec16
    call newline
    mov dx, offset m_sep
    call puts

    ; current instruction
    mov dx, offset m_ir
    call puts
    cmp byte ptr [v_fetched], 0
    jne dr_ir
    mov dx, offset m_nofetch
    call puts
    jmp dr_ir_end
dr_ir:
    mov al, [v_ir0]
    call put_hex8
    mov dl, ' '
    call putc
    mov al, [v_ir1]
    call put_hex8
    mov dx, offset m_at
    call puts
    mov al, [v_ipc]
    call put_hex8
    mov dx, offset m_sp3
    call puts
    mov al, [v_ir0]
    mov ah, [v_ir1]
    call disasm
dr_ir_end:
    call newline

    ; stage bar
    mov dx, offset m_stage
    call puts
    mov al, 1
    mov dx, offset st_1
    call put_stage
    mov al, 2
    mov dx, offset st_2
    call put_stage
    mov al, 3
    mov dx, offset st_3
    call put_stage
    mov al, 4
    mov dx, offset st_4
    call put_stage
    mov al, 5
    mov dx, offset st_5
    call put_stage
    call newline

    ; RTL action and control signals
    mov dx, offset m_act
    call puts
    mov dx, word ptr [p_act]
    call puts
    call newline
    mov dx, offset m_sig
    call puts
    mov dx, word ptr [p_sig]
    call puts
    call newline
    mov dx, offset m_sep
    call puts

    ; processor registers and flags
    mov dx, offset l_pc
    mov al, [v_pc]
    call put_lv
    mov dx, offset l_ir
    mov al, [v_ir0]
    call put_lv
    mov al, [v_ir1]
    call put_hex8
    mov dx, offset l_ma
    mov al, [v_ma]
    call put_lv
    mov dx, offset l_md
    mov al, [v_md]
    call put_lv
    mov dx, offset l_flags
    call puts
    mov dl, [v_zf]
    add dl, '0'
    call putc
    mov dx, offset l_c
    call puts
    mov dl, [v_cf]
    add dl, '0'
    call putc
    call newline

    ; inter-stage registers
    mov dx, offset l_ra
    mov al, [v_ra]
    call put_lv
    mov dx, offset l_rb
    mov al, [v_rb]
    call put_lv
    mov dx, offset l_rz
    mov al, [v_rz]
    call put_lv
    mov dx, offset l_rm
    mov al, [v_rm]
    call put_lv
    mov dx, offset l_ry
    mov al, [v_ry]
    call put_lv
    mov dx, offset l_inter
    call puts
    call newline

    ; register file
    mov dx, offset l_r0
    mov al, [regs]
    call put_lv
    mov dx, offset l_r1
    mov al, [regs+1]
    call put_lv
    mov dx, offset l_r2
    mov al, [regs+2]
    call put_lv
    mov dx, offset l_r3
    mov al, [regs+3]
    call put_lv
    mov dx, offset l_file
    call puts
    call newline
    mov dx, offset m_sep
    call puts

    ; memory dump, 4 rows of 16 bytes
    mov dx, offset m_memhdr
    call puts
    xor bx, bx
dr_row:
    mov dx, offset m_sp2
    call puts
    mov al, bl
    call put_hex8
    mov dl, 'h'
    call putc
    mov dl, ':'
    call putc
    mov dl, ' '
    call putc
    mov cx, 16
dr_col:
    mov dl, ' '
    cmp byte ptr [v_fetched], 0
    je dr_c2
    cmp bl, [v_ipc]
    jne dr_c2
    mov dl, '>'
    jmp dr_c3
dr_c2:
    cmp bl, [v_lastw]
    jne dr_c3
    mov dl, '*'
dr_c3:
    call putc
    mov al, [mem+bx]
    call put_hex8
    inc bx
    loop dr_col
    call newline
    cmp bx, 64
    jb dr_row
    mov dx, offset m_legend
    call puts
    mov dx, offset m_sep
    call puts

    ; output port
    mov dx, offset m_out
    call puts
    mov cl, [v_outlen]
    xor ch, ch
    jcxz dr_nout
    xor bx, bx
dr_out:
    mov al, [outbuf+bx]
    call put_hex8
    mov dl, ' '
    call putc
    inc bx
    loop dr_out
    mov dx, offset m_lastdec
    call puts
    mov al, [outbuf+bx-1]
    xor ah, ah
    call put_dec16
    mov dx, offset m_dec
    call puts
    jmp dr_out_end
dr_nout:
    mov dx, offset m_none
    call puts
dr_out_end:
    call newline
    call newline

    ; help / status line
    mov dx, offset m_help
    mov al, [v_halt]
    cmp al, 1
    jne dr_h2
    mov dx, offset m_hlt1
dr_h2:
    cmp al, 2
    jne dr_h3
    mov dx, offset m_hlt2
dr_h3:
    cmp al, 3
    jne dr_h4
    mov dx, offset m_hlt3
dr_h4:
    call puts
    ret

; put_stage : AL = stage number, DX = name.  Current stage is shown [like this]
put_stage:
    push bx
    mov bl, ' '
    mov bh, ' '
    cmp al, [v_shown]
    jne ps_1
    mov bl, '['
    mov bh, ']'
ps_1:
    push dx
    mov dl, bl
    call putc
    pop dx
    call puts
    mov dl, bh
    call putc
    mov dl, ' '
    call putc
    pop bx
    ret

; put_lv : print label DX followed by AL in hex
put_lv:
    call puts
    call put_hex8
    ret

;=============================================================================
; disasm : print the instruction AL = byte 0, AH = byte 1 in assembly form
;=============================================================================
disasm:
    push ax
    push bx
    push cx
    push dx
    mov [d_b1], ah
    mov bl, al
    mov cl, 4
    shr bl, cl
    mov [d_op], bl
    mov bh, al
    and bh, 3
    mov [d_rs], bh
    shr al, 1
    shr al, 1
    and al, 3
    mov [d_rd], al
    mov al, ah
    and al, 3
    mov [d_rt], al
    ; mnemonic
    mov al, [d_op]
    cmp al, 0Ah
    jbe dm_1
    mov al, 0Bh
dm_1:
    mov bl, 7
    mul bl
    mov dx, offset mn_tbl
    add dx, ax
    call puts
    ; operands
    mov al, [d_op]
    cmp al, 0
    jne dm_r
    jmp dm_end
dm_r:
    cmp al, 4
    ja dm_5
    mov al, [d_rd]              ; Rd, Rs, Rt
    call put_reg
    call put_comma
    mov al, [d_rs]
    call put_reg
    call put_comma
    mov al, [d_rt]
    call put_reg
    jmp dm_end
dm_5:
    cmp al, 5
    jne dm_67
    mov al, [d_rd]              ; Rd, Rs, #imm
    call put_reg
    call put_comma
    mov al, [d_rs]
    call put_reg
    call put_comma
    mov dl, '#'
    call putc
    mov al, [d_b1]
    call put_simm
    jmp dm_end
dm_67:
    cmp al, 7
    ja dm_8
    mov al, [d_rd]              ; Rd, X(Rs)
    call put_reg
    call put_comma
    mov al, [d_b1]
    call put_hex8
    mov dl, 'h'
    call putc
    mov dl, '('
    call putc
    mov al, [d_rs]
    call put_reg
    mov dl, ')'
    call putc
    jmp dm_end
dm_8:
    cmp al, 8
    jne dm_9
    mov al, [d_rd]              ; Rd, Rs, X
    call put_reg
    call put_comma
    mov al, [d_rs]
    call put_reg
    call put_comma
    mov al, [d_b1]
    call put_hex8
    mov dl, 'h'
    call putc
    jmp dm_end
dm_9:
    cmp al, 9
    jne dm_a
    mov al, [d_b1]              ; X
    call put_hex8
    mov dl, 'h'
    call putc
    jmp dm_end
dm_a:
    cmp al, 0Ah
    jne dm_end
    mov al, [d_rs]              ; Rs
    call put_reg
dm_end:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; put_reg : AL = register number -> "Rn"
put_reg:
    push dx
    mov dl, 'R'
    call putc
    mov dl, al
    add dl, '0'
    call putc
    pop dx
    ret

put_comma:
    push dx
    mov dx, offset m_comma
    call puts
    pop dx
    ret

; put_simm : AL as a signed decimal number
put_simm:
    push ax
    test al, 80h
    jz psi_1
    push dx
    mov dl, '-'
    call putc
    pop dx
    neg al
psi_1:
    xor ah, ah
    call put_dec16
    pop ax
    ret

;=============================================================================
;                         SCREEN / KEYBOARD HELPERS
;=============================================================================
cls:                            ; clear the screen (80 x 25 text mode)
    push ax
    mov ax, 0003h
    int 10h
    pop ax
    ret

getkey:                         ; wait for a key -> AL = ASCII code
    mov ah, 0
    int 16h
    ret

puts:                           ; print '$'-terminated string at DS:DX
    push ax
    mov ah, 09h
    int 21h
    pop ax
    ret

putc:                           ; print the character in DL
    push ax
    mov ah, 02h
    int 21h
    pop ax
    ret

newline:
    push dx
    mov dx, offset m_crlf
    call puts
    pop dx
    ret

put_hex8:                       ; print AL as 2 hex digits
    push ax
    push cx
    mov ah, al
    mov cl, 4
    shr al, cl
    call put_nib
    mov al, ah
    and al, 0Fh
    call put_nib
    pop cx
    pop ax
    ret

put_nib:                        ; print AL (0..15) as one hex digit
    push ax
    push dx
    cmp al, 10
    jb pn_1
    add al, 7
pn_1:
    add al, '0'
    mov dl, al
    mov ah, 02h
    int 21h
    pop dx
    pop ax
    ret

put_dec16:                      ; print AX as an unsigned decimal number
    push ax
    push bx
    push cx
    push dx
    mov bx, 10
    xor cx, cx
pd_1:
    xor dx, dx
    div bx
    push dx
    inc cx
    or ax, ax
    jnz pd_1
pd_2:
    pop dx
    add dl, '0'
    mov ah, 02h
    int 21h
    loop pd_2
    pop dx
    pop cx
    pop bx
    pop ax
    ret

