; =====================================================================
; Program : Snake Game in ASCII Art using Assembly Language
; Course  : CS125L - Architecture and Organization Laboratory
; Section : CIS303                 Group: Group 10
; Members : Andrew De Jesus, Hannali Olayvar,
;           Marcus Sandoval, Brian Velasco
; Teacher : Dahlia De Mesa
;
; Target  : 8086, 16-bit DOS, MASM/TASM-style syntax (also emu8086).
; All game logic is assembly. No external libraries or include files.
; Inputs  : player initial, difficulty, WASD, and R/E after a round.
; Idea    : snake[0] is the head; snake[length-1] is the tail.
;           Each word stores a board cell number, not a screen address.
; =====================================================================

.MODEL SMALL
.STACK 100H

.DATA
    BOARD_COLS  EQU 30
    BOARD_ROWS  EQU 12
    MAX_CELLS   EQU BOARD_COLS * BOARD_ROWS
    TOP_WALL    EQU 6
    LEFT_WALL   EQU 23
    BOT_WALL    EQU 19              ; TOP_WALL + BOARD_ROWS + 1
    RIGHT_WALL  EQU 54              ; LEFT_WALL + BOARD_COLS + 1
    ; Literal border values avoid emu8086 4.08's nested-EQU MOV bug.
    START_CELL  EQU (BOARD_ROWS / 2) * BOARD_COLS + (BOARD_COLS / 2)

    ; Directions go clockwise. XOR 2 gives the opposite direction.
    UP_DIR      EQU 0
    RIGHT_DIR   EQU 1
    DOWN_DIR    EQU 2
    LEFT_DIR    EQU 3
    RUNNING     EQU 0
    HIT_WALL    EQU 1
    HIT_BODY    EQU 2
    WON_GAME    EQU 3
    ENDED_ROUND EQU 4

    titleText   DB 'ASCII SNAKE | Group 10 | CIS303','$'
    goalText    DB 'Eat @ to grow. Avoid # and your own body.','$'
    introText   DB 'O = head   o = body   @ = food   # = wall','$'
    initialText DB 'Player initial (A-Z): $'
    levelText   DB 'Difficulty (1 = Easy, 2 = Normal, 3 = Fast): $'
    badInitial  DB 'Please enter one letter from A to Z.','$'
    badLevel    DB 'Please enter 1, 2, or 3.','$'
    blankLine   DB '                                                                        $'
    playerText  DB 'Player: $'
    speedText   DB 'Speed: $'
    scoreText   DB 'Score: $'
    easyText    DB 'Easy','$'
    normalText  DB 'Normal','$'
    fastText    DB 'Fast','$'
    controls    DB 'W/A/S/D: move | X or Esc: end round','$'
    wallText    DB 'Wall collision. Final score: $'
    bodyText    DB 'Body collision. Final score: $'
    winText     DB 'You filled the board! Final score: $'
    endedText   DB 'Round ended. Final score: $'
    choiceText  DB 'R: restart with the same settings | E: exit','$'
    badChoice   DB 'Please press R to restart or E to exit.','$'

    player      DB ?
    levelName   DW OFFSET easyText
    stepTicks   DW 6                 ; BIOS timer: about 18.2 ticks/second
    lastTick    DW 0
    randomSeed  DW 0
    snake       DW MAX_CELLS DUP(0)  ; capacity equals the entire board
    snakeLength DW 3
    score       DW 0
    foodCell    DW 0
    nextCell    DW 0
    direction   DB RIGHT_DIR
    nextDir     DB RIGHT_DIR
    turnLocked  DB 0                 ; at most one accepted turn per step
    growing     DB 0
    gameState   DB RUNNING

.CODE
MAIN PROC
    MOV AX, @DATA
    MOV DS, AX
    CALL CLEAR_SCREEN

    MOV DH, 1
    MOV DL, 2
    CALL SET_CURSOR
    LEA DX, titleText
    CALL PRINT_TEXT
    MOV DH, 3
    MOV DL, 2
    CALL SET_CURSOR
    LEA DX, goalText
    CALL PRINT_TEXT
    MOV DH, 4
    MOV DL, 2
    CALL SET_CURSOR
    LEA DX, introText
    CALL PRINT_TEXT

    ; Two separate settings are validated before the game starts.
GET_INITIAL:
    MOV DH, 8
    MOV DL, 2
    CALL SET_CURSOR
    LEA DX, initialText
    CALL PRINT_TEXT
    CALL READ_KEY
    CMP AL, 'A'
    JB INITIAL_ERROR
    CMP AL, 'Z'
    JA INITIAL_ERROR
    MOV player, AL
    MOV DL, AL
    CALL PRINT_CHAR
    CALL CLEAR_MESSAGE
    JMP GET_LEVEL
INITIAL_ERROR:
    LEA DX, badInitial
    CALL SETUP_ERROR
    JMP GET_INITIAL

GET_LEVEL:
    MOV DH, 10
    MOV DL, 2
    CALL SET_CURSOR
    LEA DX, levelText
    CALL PRINT_TEXT
    CALL READ_KEY
    CMP AL, '1'
    JB LEVEL_ERROR
    CMP AL, '3'
    JA LEVEL_ERROR
    MOV DL, AL
    CALL PRINT_CHAR
    CMP AL, '1'
    JE SETTINGS_DONE               ; default: 6 ticks, about 3 moves/sec
    MOV stepTicks, 4
    MOV levelName, OFFSET normalText
    CMP AL, '2'
    JE SETTINGS_DONE               ; about 4.6 moves/sec
    MOV stepTicks, 2
    MOV levelName, OFFSET fastText ; about 9.1 moves/sec
    JMP SETTINGS_DONE
LEVEL_ERROR:
    LEA DX, badLevel
    CALL SETUP_ERROR
    JMP GET_LEVEL

SETTINGS_DONE:
    MOV AH, 00H
    INT 1AH                        ; BIOS: CX:DX = ticks since midnight
    MOV randomSeed, DX             ; seed once; do not reseed each apple

NEW_ROUND:
    CALL CLEAR_SCREEN
    CALL FLUSH_KEYS
    CALL INIT_GAME
    CALL DRAW_SCREEN
    CALL SPAWN_FOOD
    MOV AH, 00H
    INT 1AH
    MOV lastTick, DX

GAME_LOOP:
    CALL POLL_INPUT                ; checks one key, without blocking
    CMP gameState, RUNNING
    JNE ROUND_OVER
    MOV AH, 00H
    INT 1AH
    MOV AX, DX
    SUB AX, lastTick               ; unsigned subtraction handles tick wrap
    CMP AX, stepTicks
    JB GAME_LOOP                   ; input is still checked while waiting
    MOV lastTick, DX                ; no burst of catch-up moves
    CALL MOVE_SNAKE
    CMP gameState, RUNNING
    JE GAME_LOOP

ROUND_OVER:
    CALL SHOW_RESULT
    CALL FLUSH_KEYS
WAIT_CHOICE:
    CALL READ_KEY
    CMP AL, 'R'
    JE RESTART_ROUND
    CMP AL, 'E'
    JE EXIT_PROGRAM
    MOV DH, 24
    MOV DL, 2
    CALL SET_CURSOR
    LEA DX, badChoice
    CALL PRINT_TEXT
    JMP WAIT_CHOICE
RESTART_ROUND:
    JMP NEW_ROUND

EXIT_PROGRAM:
    MOV AH, 01H
    MOV CX, 0607H
    INT 10H                        ; BIOS: restore visible cursor
    MOV DH, 24
    MOV DL, 0
    CALL SET_CURSOR
    MOV AX, 4C00H
    INT 21H                        ; DOS: terminate, return code 0
MAIN ENDP

; Reset the state. Old array entries past snakeLength are never read.
INIT_GAME PROC
    MOV snakeLength, 3
    MOV score, 0
    MOV snake[0], START_CELL
    MOV snake[2], START_CELL - 1
    MOV snake[4], START_CELL - 2
    MOV direction, RIGHT_DIR
    MOV nextDir, RIGHT_DIR
    MOV turnLocked, 0
    MOV gameState, RUNNING
    RET
INIT_GAME ENDP

; One key per call. Invalid/repeated/reverse keys do not stop the timer.
; The first valid turn is saved until the next movement step.
POLL_INPUT PROC
    MOV AH, 01H
    INT 16H                        ; BIOS: ZF=1 if no key is waiting
    JNZ KEY_AVAILABLE
    RET
KEY_AVAILABLE:
    CALL READ_KEY
    CMP AL, 27                     ; Escape
    JE END_REQUESTED
    CMP AL, 'X'
    JE END_REQUESTED
    CMP turnLocked, 0
    JNE INPUT_DONE
    CMP AL, 'W'
    JE INPUT_UP
    CMP AL, 'D'
    JE INPUT_RIGHT
    CMP AL, 'S'
    JE INPUT_DOWN
    CMP AL, 'A'
    JNE INPUT_DONE
    MOV AL, LEFT_DIR
    JMP CHECK_TURN
INPUT_UP:
    MOV AL, UP_DIR
    JMP CHECK_TURN
INPUT_RIGHT:
    MOV AL, RIGHT_DIR
    JMP CHECK_TURN
INPUT_DOWN:
    MOV AL, DOWN_DIR
CHECK_TURN:
    CMP AL, direction
    JE INPUT_DONE
    MOV AH, direction
    XOR AH, 2                      ; opposite of the current direction
    CMP AL, AH
    JE INPUT_DONE                  ; never allow an immediate U-turn
    MOV nextDir, AL
    MOV turnLocked, 1
INPUT_DONE:
    RET
END_REQUESTED:
    MOV gameState, ENDED_ROUND
    RET
POLL_INPUT ENDP

; Compute next cell, check collisions, erase tail if needed, shift body.
; This deliberately uses an ordinary array instead of a circular buffer.
MOVE_SNAKE PROC
    MOV AL, nextDir
    MOV direction, AL
    MOV turnLocked, 0
    MOV growing, 0
    MOV AX, snake[0]
    MOV DI, AX
    XOR DX, DX
    MOV BX, BOARD_COLS
    DIV BX                         ; AX = head row, DX = head column
    CMP direction, UP_DIR
    JE MOVE_UP
    CMP direction, DOWN_DIR
    JE MOVE_DOWN
    CMP direction, LEFT_DIR
    JE MOVE_LEFT
    CMP DX, BOARD_COLS - 1
    JE WALL_COLLISION
    INC DI
    JMP NEXT_READY
MOVE_UP:
    CMP AX, 0
    JE WALL_COLLISION
    SUB DI, BOARD_COLS
    JMP NEXT_READY
MOVE_DOWN:
    CMP AX, BOARD_ROWS - 1
    JE WALL_COLLISION
    ADD DI, BOARD_COLS
    JMP NEXT_READY
MOVE_LEFT:
    CMP DX, 0
    JE WALL_COLLISION
    DEC DI
    JMP NEXT_READY
WALL_COLLISION:
    MOV gameState, HIT_WALL
    RET

NEXT_READY:
    MOV nextCell, DI
    MOV CX, snakeLength
    CMP DI, foodCell
    JE WILL_GROW
    DEC CX                         ; tail is safe: it leaves on this step
    JMP CHECK_BODY
WILL_GROW:
    MOV growing, 1                 ; include tail when growth keeps it
CHECK_BODY:
    XOR SI, SI
BODY_SCAN:
    CMP DI, snake[SI]
    JE BODY_COLLISION
    ADD SI, 2                      ; each array entry is a word
    LOOP BODY_SCAN
    JMP UPDATE_BODY
BODY_COLLISION:
    MOV gameState, HIT_BODY
    RET

UPDATE_BODY:
    CMP growing, 1
    JE EXTEND_BODY
    MOV SI, snakeLength
    DEC SI
    SHL SI, 1
    MOV AX, snake[SI]
    MOV CL, ' '
    MOV BL, 07H
    CALL DRAW_CELL                 ; erase the old tail before drawing head
    JMP SHIFT_BODY
EXTEND_BODY:
    INC snakeLength                ; cannot exceed MAX_CELLS: win below
    INC score
SHIFT_BODY:
    MOV AX, snake[0]
    MOV CL, 'o'
    MOV BL, 0AH
    CALL DRAW_CELL                 ; previous head is now a body segment
    MOV CX, snakeLength
    DEC CX
    MOV SI, CX
    SHL SI, 1
SHIFT_ONE:
    MOV AX, snake[SI-2]
    MOV snake[SI], AX
    SUB SI, 2
    LOOP SHIFT_ONE                 ; copy backward so entries survive
    MOV AX, nextCell
    MOV snake[0], AX
    MOV CL, 'O'
    MOV BL, 0AH
    CALL DRAW_CELL
    CMP growing, 1
    JNE MOVE_DONE
    CALL SHOW_SCORE
    CMP snakeLength, MAX_CELLS
    JE BOARD_FILLED
    CALL SPAWN_FOOD
MOVE_DONE:
    RET
BOARD_FILLED:
    MOV gameState, WON_GAME
    RET
MOVE_SNAKE ENDP

; Start at a pseudo-random board cell, then advance until a free cell.
; Every cell is reachable. Since length < capacity, this always finishes.
; LCG: seed = (seed * 25173 + 13849) modulo 65536.
SPAWN_FOOD PROC
    MOV AX, randomSeed
    MOV BX, 25173
    MUL BX                         ; keep low word for 16-bit wraparound
    ADD AX, 13849
    MOV randomSeed, AX
    XOR DX, DX
    MOV BX, MAX_CELLS
    DIV BX
    MOV DI, DX                     ; random starting cell, 0..359
TRY_CELL:
    XOR SI, SI
    MOV CX, snakeLength
FOOD_SCAN:
    CMP DI, snake[SI]
    JE OCCUPIED_CELL
    ADD SI, 2
    LOOP FOOD_SCAN
    MOV foodCell, DI
    MOV AX, DI
    MOV CL, '@'
    MOV BL, 0CH
    CALL DRAW_CELL
    RET
OCCUPIED_CELL:
    INC DI
    CMP DI, MAX_CELLS
    JB TRY_CELL
    XOR DI, DI
    JMP TRY_CELL
SPAWN_FOOD ENDP

; --------------------------- Screen output ---------------------------
DRAW_SCREEN PROC
    MOV DH, 0
    MOV DL, 2
    CALL SET_CURSOR
    LEA DX, titleText
    CALL PRINT_TEXT
    MOV DH, 1
    MOV DL, 2
    CALL SET_CURSOR
    LEA DX, goalText
    CALL PRINT_TEXT
    MOV DH, 3
    MOV DL, 2
    CALL SET_CURSOR
    LEA DX, playerText
    CALL PRINT_TEXT
    MOV DL, player
    CALL PRINT_CHAR
    MOV DH, 3
    MOV DL, 22
    CALL SET_CURSOR
    LEA DX, speedText
    CALL PRINT_TEXT
    MOV DX, levelName
    CALL PRINT_TEXT
    CALL SHOW_SCORE
    MOV DH, 21
    MOV DL, 2
    CALL SET_CURSOR
    LEA DX, controls
    CALL PRINT_TEXT

    MOV DL, LEFT_WALL
    MOV CX, BOARD_COLS + 2
    MOV AL, '#'
    MOV BL, 0FH
DRAW_HORIZONTAL:
    MOV DH, TOP_WALL
    CALL DRAW_AT
    MOV DH, BOT_WALL
    CALL DRAW_AT
    INC DL
    LOOP DRAW_HORIZONTAL
    MOV DH, TOP_WALL + 1
    MOV CX, BOARD_ROWS
DRAW_VERTICAL:
    MOV DL, LEFT_WALL
    CALL DRAW_AT
    MOV DL, RIGHT_WALL
    CALL DRAW_AT
    INC DH
    LOOP DRAW_VERTICAL

    MOV CX, 3
    XOR SI, SI
DRAW_START_BODY:
    PUSH CX
    MOV AX, snake[SI]
    MOV CL, 'o'
    MOV BL, 0AH
    CALL DRAW_CELL
    POP CX
    ADD SI, 2
    LOOP DRAW_START_BODY
    MOV AX, snake[0]
    MOV CL, 'O'
    CALL DRAW_CELL
    RET
DRAW_SCREEN ENDP

SHOW_SCORE PROC
    MOV DH, 3
    MOV DL, 52
    CALL SET_CURSOR
    LEA DX, scoreText
    CALL PRINT_TEXT
    MOV AX, score
    CALL PRINT_NUMBER
    RET
SHOW_SCORE ENDP

SHOW_RESULT PROC
    MOV DH, 22
    MOV DL, 2
    CALL SET_CURSOR
    LEA DX, endedText
    CMP gameState, HIT_WALL
    JNE RESULT_BODY
    LEA DX, wallText
    JMP RESULT_READY
RESULT_BODY:
    CMP gameState, HIT_BODY
    JNE RESULT_WIN
    LEA DX, bodyText
    JMP RESULT_READY
RESULT_WIN:
    CMP gameState, WON_GAME
    JNE RESULT_READY
    LEA DX, winText
RESULT_READY:
    CALL PRINT_TEXT
    MOV AX, score
    CALL PRINT_NUMBER
    MOV DH, 23
    MOV DL, 2
    CALL SET_CURSOR
    LEA DX, choiceText
    CALL PRINT_TEXT
    RET
SHOW_RESULT ENDP

; AX = board cell, CL = ASCII character, BL = color.
; Preserves all registers. DIV converts a cell to row/column.
DRAW_CELL PROC
    PUSH AX
    PUSH DX
    PUSH SI
    XOR DX, DX
    MOV SI, BOARD_COLS
    DIV SI
    ADD DL, LEFT_WALL + 1
    MOV DH, AL
    ADD DH, TOP_WALL + 1
    MOV AL, CL
    CALL DRAW_AT
    POP SI
    POP DX
    POP AX
    RET
DRAW_CELL ENDP

; AL = ASCII, BL = color, DH/DL = screen row/column. Preserves registers.
DRAW_AT PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    CALL SET_CURSOR
    MOV AH, 09H
    MOV BH, 0
    MOV CX, 1
    INT 10H                        ; BIOS: write character + color
    POP DX
    POP CX
    POP BX
    POP AX
    RET
DRAW_AT ENDP

; DH/DL = screen row/column. Preserves registers.
SET_CURSOR PROC
    PUSH AX
    PUSH BX
    MOV AH, 02H
    MOV BH, 0
    INT 10H                        ; BIOS: position cursor on page 0
    POP BX
    POP AX
    RET
SET_CURSOR ENDP

; DS:DX = dollar-terminated string. Preserves registers.
PRINT_TEXT PROC
    PUSH AX
    MOV AH, 09H
    INT 21H                        ; DOS: print string
    POP AX
    RET
PRINT_TEXT ENDP

; DL = character. Preserves registers, including AL (used by settings).
PRINT_CHAR PROC
    PUSH AX
    MOV AH, 02H
    INT 21H                        ; DOS: print character
    POP AX
    RET
PRINT_CHAR ENDP

; AX = unsigned number. Repeated division gives digits in reverse order;
; PUSH/POP reverses them again for display. Also prints zero correctly.
PRINT_NUMBER PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    XOR CX, CX
    MOV BX, 10
DIV_DIGIT:
    XOR DX, DX
    DIV BX
    PUSH DX
    INC CX
    CMP AX, 0
    JNE DIV_DIGIT
WRITE_DIGIT:
    POP DX
    ADD DL, '0'
    CALL PRINT_CHAR
    LOOP WRITE_DIGIT
    POP DX
    POP CX
    POP BX
    POP AX
    RET
PRINT_NUMBER ENDP

; -------------------------- Input and setup --------------------------
; Returns AL = key, converting only a..z to A..Z. Other registers except
; AX are unchanged. Extended keys return AL=0 and are safely ignored.
READ_KEY PROC
    MOV AH, 00H
    INT 16H                        ; BIOS: wait for and consume one key
    CMP AL, 'a'
    JB KEY_READY
    CMP AL, 'z'
    JA KEY_READY
    SUB AL, 20H
KEY_READY:
    RET
READ_KEY ENDP

FLUSH_KEYS PROC
    MOV AH, 01H
    INT 16H
    JZ FLUSH_DONE
    MOV AH, 00H
    INT 16H
    JMP FLUSH_KEYS
FLUSH_DONE:
    RET
FLUSH_KEYS ENDP

CLEAR_SCREEN PROC
    MOV AX, 0003H
    INT 10H                        ; BIOS: clear 80x25 color text screen
    MOV AH, 01H
    MOV CX, 2607H
    INT 10H                        ; BIOS: hide hardware cursor
    RET
CLEAR_SCREEN ENDP

CLEAR_MESSAGE PROC
    MOV DH, 12
    MOV DL, 2
    CALL SET_CURSOR
    LEA DX, blankLine
    CALL PRINT_TEXT
    RET
CLEAR_MESSAGE ENDP

; DS:DX = validation message. Clear the previous message, then replace it.
SETUP_ERROR PROC
    PUSH DX
    CALL CLEAR_MESSAGE
    MOV DH, 12
    MOV DL, 2
    CALL SET_CURSOR
    POP DX
    CALL PRINT_TEXT
    RET
SETUP_ERROR ENDP

END MAIN
