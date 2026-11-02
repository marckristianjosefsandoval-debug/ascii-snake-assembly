.MODEL SMALL
.STACK 100H

.DATA
    MSG0 DB 'Welcome! Program by: Group 10', 13, 10, '$'

    MSG1 DB 'CHARACTER MOVEMENT PROGRAM (SNAKE EDITION)', 13, 10
         DB '------------------------------------------', 13, 10, '$'

    MSG2 DB 'Use W, A, S, D to move (*). Eat (@) to grow!', 13, 10
         DB 'Press X to restart or exit the program.', 13, 10, '$'

    MSG_CNT DB 'Score: $'
    MSG_RST DB 'GAME OVER! Press R to Restart or E to Exit: $'

    ; Compact border boundaries (41 cols wide x 14 rows tall)
    TOP_WALL    EQU 6
    BOT_WALL    EQU 19
    LEFT_WALL   EQU 10
    RIGHT_WALL  EQU 50
    BOX_WIDTH   EQU 41          ; RIGHT_WALL - LEFT_WALL + 1
    INNER_ROWS  EQU 12          ; BOT_WALL - TOP_WALL - 1 (Rows 7..18)
    INNER_COLS  EQU 39          ; RIGHT_WALL - LEFT_WALL - 1 (Cols 11..49)

    ; Tune speed here: 1 = fastest, increase (e.g., 15 or 30) to slow down
    FRAME_DELAY EQU 5

    ; Circular buffer of 256 video-memory word offsets (512 bytes: 0..510)
    BUF_LIMIT   EQU 512
    SNAKE_BUF   DW 256 DUP(0)
    HEAD_IDX    DW 4            ; Byte index in SNAKE_BUF (0, 2, 4...510)
    TAIL_IDX    DW 0
    CUR_DIR     DB 'D'          ; 1-byte direction ('W'=Up, 'S'=Down, 'A'=Left, 'D'=Right)

    SCORE       DW 0
    RAND_SEED   DW 3749H

.CODE
MAIN PROC
    MOV AX, @DATA
    MOV DS, AX

    ; Point ES directly to color text video memory (0B800h)
    MOV AX, 0B800H
    MOV ES, AX

    ; Seed random number generator once from BIOS timer
    MOV AH, 00H
    INT 1AH
    MOV RAND_SEED, DX

START_GAME:
    ; Reset video mode (80x25 text mode)
    MOV AX, 0003H
    INT 10H

    ; Hide blinking hardware cursor
    MOV AH, 01H
    MOV CX, 2607H
    INT 10H

    ; Flush any leftover keys in BIOS buffer from previous run
FLUSH_KEYS:
    MOV AH, 01H
    INT 16H
    JZ KEYS_CLEAR
    MOV AH, 00H
    INT 16H
    JMP FLUSH_KEYS
KEYS_CLEAR:

    ; Challenge 3: Display author header, title, and WASD instructions
    MOV AH, 09H
    LEA DX, MSG0
    INT 21H

    MOV AH, 09H
    LEA DX, MSG1
    INT 21H

    MOV AH, 09H
    LEA DX, MSG2
    INT 21H

    ; Initialize snake at Row 12, Cols 28, 29, 30 heading Right ('D')
    ; Video offset = (12 * 160) + (Col * 2) = 1920 + (Col * 2)
    MOV TAIL_IDX, 0
    MOV HEAD_IDX, 4
    MOV CUR_DIR, 'D'
    MOV SCORE, 0

    MOV SNAKE_BUF[0], 1976      ; Row 12, Col 28
    MOV SNAKE_BUF[2], 1978      ; Row 12, Col 29
    MOV SNAKE_BUF[4], 1980      ; Row 12, Col 30

    ; Draw border AND explicitly wipe all interior 0B800h cells with ' '
    CALL DRAW_BORDER
    CALL SHOW_COUNT

    ; Draw initial 3 snake segments directly to video memory (0A2AH = green '*')
    MOV WORD PTR ES:[1976], 0A2AH
    MOV WORD PTR ES:[1978], 0A2AH
    MOV WORD PTR ES:[1980], 0A2AH

    CALL SPAWN_APPLE

GAME_LOOP:
    ; Small tunable delay loop
    MOV CX, FRAME_DELAY
DELAY_TICK:
    LOOP DELAY_TICK

READ_INPUT:
    ; Non-blocking keyboard check
    MOV AH, 01H
    INT 16H
    JZ MOVE_STEP                ; No key waiting -> move immediately

    ; Read key from buffer
    MOV AH, 00H
    INT 16H

    ; Convert lowercase to uppercase
    CMP AL, 'a'
    JB CHECK_KEYS
    CMP AL, 'z'
    JA CHECK_KEYS
    SUB AL, 20H

; Challenge 2: WASD & X Input Checks (1 turn allowed per step)
CHECK_KEYS:
    CMP AL, 'X'
    JNE CHK_W
    JMP ASK_RESTART

CHK_W:
    CMP AL, 'W'
    JNE CHK_S
    CMP CUR_DIR, 'W'
    JE READ_INPUT               ; Discard repeated key if held down
    CMP CUR_DIR, 'S'
    JE READ_INPUT               ; Block 180-degree self-reversal
    MOV CUR_DIR, 'W'
    JMP MOVE_STEP

CHK_S:
    CMP AL, 'S'
    JNE CHK_A
    CMP CUR_DIR, 'S'
    JE READ_INPUT
    CMP CUR_DIR, 'W'
    JE READ_INPUT
    MOV CUR_DIR, 'S'
    JMP MOVE_STEP

CHK_A:
    CMP AL, 'A'
    JNE CHK_D
    CMP CUR_DIR, 'A'
    JE READ_INPUT
    CMP CUR_DIR, 'D'
    JE READ_INPUT
    MOV CUR_DIR, 'A'
    JMP MOVE_STEP

CHK_D:
    CMP AL, 'D'
    JNE READ_INPUT
    CMP CUR_DIR, 'D'
    JE READ_INPUT
    CMP CUR_DIR, 'A'
    JE READ_INPUT
    MOV CUR_DIR, 'D'

MOVE_STEP:
    ; Load current head video offset into DI
    MOV SI, HEAD_IDX
    MOV DI, SNAKE_BUF[SI]

    ; Compute next head offset using 16-bit register math
    MOV AX, 00A0H               ; 160 bytes per row
    CMP CUR_DIR, 'W'
    JE STEP_UP
    CMP CUR_DIR, 'S'
    JE STEP_DOWN
    CMP CUR_DIR, 'A'
    JE STEP_LEFT
    ADD DI, 2                   ; 'D' = Right (+2 bytes)
    JMP CHECK_CELL

STEP_UP:
    SUB DI, AX                  ; 'W' = Up (-160 bytes)
    JMP CHECK_CELL
STEP_DOWN:
    ADD DI, AX                  ; 'S' = Down (+160 bytes)
    JMP CHECK_CELL
STEP_LEFT:
    SUB DI, 2                   ; 'A' = Left (-2 bytes)

CHECK_CELL:
    ; Read character currently on screen at ES:[DI]
    MOV AL, ES:[DI]

    ; 1. Check wall ('#') collision
    CMP AL, '#'
    JE ASK_RESTART

    ; 2. Check if head landed on an apple ('@')
    CMP AL, '@'
    JNE NORMAL_MOVE

    ; --- Apple Eaten: Save new head first, then update score & spawn apple ---
    MOV AX, HEAD_IDX
    ADD AX, 2
    CMP AX, BUF_LIMIT
    JB SAVE_HEAD_APPLE
    XOR AX, AX
SAVE_HEAD_APPLE:
    MOV HEAD_IDX, AX
    MOV SI, AX
    MOV SNAKE_BUF[SI], DI
    MOV WORD PTR ES:[DI], 0A2AH ; Draw new green '*' head

    INC SCORE
    CALL SHOW_COUNT
    CALL SPAWN_APPLE
    JMP GAME_LOOP

NORMAL_MOVE:
    ; 3. Check self-collision ('*'), ignoring the tail tip about to vacate
    MOV SI, TAIL_IDX
    MOV BX, SNAKE_BUF[SI]       ; BX = current tail tip screen offset
    CMP AL, '*'
    JNE ERASE_TAIL
    CMP DI, BX                  ; Stepping onto vacating tail tip is safe
    JNE ASK_RESTART             ; Hit body segment -> Game Over

ERASE_TAIL:
    ; --- Normal Move: Erase old tail, advance tail & head ---
    MOV WORD PTR ES:[BX], 0720H ; Overwrite old tail with blank space ' '

    MOV AX, TAIL_IDX
    ADD AX, 2
    CMP AX, BUF_LIMIT
    JB SAVE_TAIL
    XOR AX, AX
SAVE_TAIL:
    MOV TAIL_IDX, AX

    MOV AX, HEAD_IDX
    ADD AX, 2
    CMP AX, BUF_LIMIT
    JB SAVE_HEAD
    XOR AX, AX
SAVE_HEAD:
    MOV HEAD_IDX, AX
    MOV SI, AX
    MOV SNAKE_BUF[SI], DI
    MOV WORD PTR ES:[DI], 0A2AH ; Draw new green '*' head
    JMP GAME_LOOP

; Challenge 5: Restart or Exit Prompt
ASK_RESTART:
    MOV AH, 02H
    MOV BH, 00H
    MOV DH, 21
    MOV DL, 0
    INT 10H

    MOV AH, 09H
    LEA DX, MSG_RST
    INT 21H

WAIT_CHOICE:
    MOV AH, 00H
    INT 16H

    CMP AL, 'R'
    JE DO_RESTART
    CMP AL, 'r'
    JE DO_RESTART

    CMP AL, 'E'
    JE EXIT_PROG
    CMP AL, 'e'
    JE EXIT_PROG

    JMP WAIT_CHOICE

DO_RESTART:
    JMP START_GAME

EXIT_PROG:
    ; Restore standard text cursor
    MOV AH, 01H
    MOV CX, 0607H
    INT 10H

    MOV AH, 4CH
    INT 21H
MAIN ENDP

; ---------------------------------------------------------
; Draws border and wipes all 39x12 interior cells in 0B800h
; ---------------------------------------------------------
DRAW_BORDER PROC
    CLD
    ; Top & Bottom Walls (Row 6 and Row 19, Cols 10..50)
    MOV DI, (TOP_WALL * 160) + (LEFT_WALL * 2)
    MOV BX, (BOT_WALL * 160) + (LEFT_WALL * 2)
    MOV CX, BOX_WIDTH
HORIZ_WALLS:
    MOV WORD PTR ES:[DI], 0F23H ; 0FH = Bright White, 23H = '#'
    MOV WORD PTR ES:[BX], 0F23H
    ADD DI, 2
    ADD BX, 2
    LOOP HORIZ_WALLS

    ; Left Wall, Clear Interior (Cols 11..49), and Right Wall for Rows 7..18
    MOV BX, ((TOP_WALL + 1) * 160) + (LEFT_WALL * 2)
    MOV DX, INNER_ROWS
VERT_WALLS:
    MOV DI, BX
    MOV AX, 0F23H               ; Bright White '#'
    STOSW                       ; Draw Left Wall at Col 10
    MOV AX, 0720H               ; Blank space ' ' (wipes old '*' and '@')
    MOV CX, INNER_COLS          ; 39 interior columns
    REP STOSW                   ; Clear entire interior row in 0B800h RAM
    MOV AX, 0F23H               ; Bright White '#'
    STOSW                       ; Draw Right Wall at Col 50

    MOV AX, 00A0H               ; +160 bytes (advance to next row)
    ADD BX, AX
    DEC DX
    JNZ VERT_WALLS
    RET
DRAW_BORDER ENDP

; ---------------------------------------------------------
; Spawns an apple (@) at a random empty coordinate inside walls
; ---------------------------------------------------------
SPAWN_APPLE PROC
TRY_NEW_POS:
    MOV AH, 00H
    INT 1AH
    MOV AX, RAND_SEED
    ADD AX, DX
    MOV BX, 25173
    MUL BX
    ADD AX, 13849
    MOV RAND_SEED, AX

    ; Random Row inside box: 7..18 (INNER_ROWS = 12)
    XOR DX, DX
    MOV BX, INNER_ROWS
    DIV BX
    ADD DL, TOP_WALL + 1
    MOV AL, DL
    MOV BL, 160
    MUL BL                      ; AX = Row * 160
    MOV DI, AX

    ; Random Col inside box: 11..49 (INNER_COLS = 39)
    MOV AX, RAND_SEED
    ROR AX, 1
    XOR DX, DX
    MOV BX, INNER_COLS
    DIV BX
    ADD DX, LEFT_WALL + 1
    SHL DX, 1                   ; DX = Col * 2
    ADD DI, DX                  ; DI = (Row * 160) + (Col * 2)

    ; Re-roll only if spot is occupied by snake '*' or wall '#'
    MOV AL, ES:[DI]
    CMP AL, '*'
    JE TRY_NEW_POS
    CMP AL, '#'
    JE TRY_NEW_POS

    ; Draw bright red '@' (0C40H) directly to video memory
    MOV WORD PTR ES:[DI], 0C40H
    RET
SPAWN_APPLE ENDP

; Challenge 4: Display Score at Row 5, Col 0
SHOW_COUNT PROC
    PUSH DI
    MOV AH, 02H
    MOV BH, 00H
    MOV DH, 5
    MOV DL, 0
    INT 10H

    MOV AH, 09H
    LEA DX, MSG_CNT
    INT 21H

    MOV AX, SCORE
    CALL PRINT_NUM
    POP DI
    RET
SHOW_COUNT ENDP

PRINT_NUM PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX

    MOV CX, 0
    MOV BX, 10

DIV_LOOP:
    MOV DX, 0
    DIV BX
    PUSH DX
    INC CX
    CMP AX, 0
    JNE DIV_LOOP

PRINT_LOOP:
    POP DX
    ADD DL, '0'
    MOV AH, 02H
    INT 21H
    LOOP PRINT_LOOP

    POP DX
    POP CX
    POP BX
    POP AX
    RET
PRINT_NUM ENDP

END MAIN