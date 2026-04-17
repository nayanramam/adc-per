; CONFIG WORD LAYOUT (written to ADC EQU 3):
;   [2:0]   IO_ADDR       = 000 (CH0, fixed for this demo)
;   [4:3]   IO_MODE       = 10  (TTL debug mode)
;   [8:5]   IO_ADDR_NEG   = 0000 (unused in TTL mode)
;   [13:12] TTL_CONFIG    selected by SW[1:0]:
;             00 = Input  LOW  (0.8V)  => CFG_IN_LO
;             01 = Output LOW  (0.4V)  => CFG_OUT_LO
;             10 = Input  HIGH (2.0V)  => CFG_IN_HI
;             11 = Output HIGH (2.7V)  => CFG_OUT_HI
;
; SWITCHES:
;   SW[1:0] — TTL threshold select (4 options)
;
; DISPLAY:
;   HEX_UP — signed TTL difference result (two's complement mV)
;   HEX_LO — active TTL_CONFIG code (0/1/2/3) for reference
; =============================================================

ORG 0

; I/O Addresses 
Switches:  EQU 000
LEDs:      EQU 001
Timer:     EQU 002
ADC:       EQU 003
HEX_UP:    EQU 004
HEX_LO:    EQU 005

MAIN:
    IN      Switches
    AND     MASK_SW10       ; isolate bits [1:0]
    STORE   TTL_SEL

    ; --- Jump to correct config word based on SW[1:0] ---
    JZERO   USE_IN_LO       ; SW=00 => Input LOW  (0.8V)
    ADDI    -1
    JZERO   USE_OUT_LO      ; SW=01 => Output LOW (0.4V)
    ADDI    -1
    JZERO   USE_IN_HI       ; SW=10 => Input HIGH (2.0V)
    JUMP    USE_OUT_HI      ; SW=11 => Output HIGH (2.7V)

USE_IN_LO:
    LOAD    CFG_IN_LO
    JUMP    SEND_CONFIG
USE_OUT_LO:
    LOAD    CFG_OUT_LO
    JUMP    SEND_CONFIG
USE_IN_HI:
    LOAD    CFG_IN_HI
    JUMP    SEND_CONFIG
USE_OUT_HI:
    LOAD    CFG_OUT_HI

SEND_CONFIG:
    STORE   CONFIG_WORD

    ; --- Validate config before sending ---
    LOAD    CONFIG_WORD
    CALL    CHECK_CONFIG    ; freezes with DEAD on both displays if invalid
    OUT     ADC

    ; --- Wait for ADC to settle (>20 cycles) ---
    CALL    WAIT_ADC

    ; --- Read and display result ---
    IN      ADC
    OUT     HEX_UP

    ; --- Show TTL_CONFIG code (0-3) on HEX_LO and LEDs ---
    LOAD    TTL_SEL
    OUT     HEX_LO
    OUT     LEDs

    CALL    DELAY
    JUMP    MAIN

; CHECK_CONFIG — validate config word before OUT ADC
; Call with config word in AC. Returns if valid, freezes if not.
CHECK_CONFIG:
    STORE   CC_TEMP

    ; Check IO_MODE bits [4:3] == 11 (invalid = 0b00011000)
    AND     MASK_MODE
    SUB     MODE_ERR
    JZERO   CONFIG_BAD

    LOAD    CC_TEMP
    RETURN

CONFIG_BAD:
    LOAD    DEAD_CONST
    OUT     HEX_UP          ; lower 4 digits show DEAD
    OUT     HEX_LO          ; upper 4 digits show DEAD
    JUMP    CONFIG_BAD      ; freeze until hard reset


; WAIT_ADC — wait >20 cycles for ADC to settle
WAIT_ADC:
    LOADI   30
WAIT_LP:
    ADDI    -1
    JPOS    WAIT_LP
    RETURN

; DELAY — display hold delay
DELAY:
    LOAD    DELAY_COUNT
    STORE   DELAY_TEMP
DELAY_LP:
    LOAD    DELAY_TEMP
    ADDI    -1
    STORE   DELAY_TEMP
    JPOS    DELAY_LP
    RETURN

; CONSTANTS & DATA
; Pre-built config words — IO_MODE=10 at [4:3], CH0 at [2:0]
; TTL_CONFIG at [13:12]:
;   00 => 0b0000000000010000 = &H0010  Input  LOW  (0.8V)
;   01 => 0b0001000000010000 = &H1010  Output LOW  (0.4V)
;   10 => 0b0010000000010000 = &H2010  Input  HIGH (2.0V)
;   11 => 0b0011000000010000 = &H3010  Output HIGH (2.7V)

CFG_IN_LO:  DW  &H0010
CFG_OUT_LO: DW  &H1010
CFG_IN_HI:  DW  &H2010
CFG_OUT_HI: DW  &H3010

; Mask for IO_MODE field [4:3]
MASK_MODE:  DW  &B0000000000011000
; Invalid mode = 11 at bits [4:3] => 0b00011000
MODE_ERR:   DW  &B0000000000011000

; Switch mask
MASK_SW10:  DW  &B0000000000000011   ; isolate SW[1:0]

; Error sentinel
DEAD_CONST: DW  &HDEAD

; Delay tuning
DELAY_COUNT: DW 5000

; Scratch
TTL_SEL:    DW  0
CONFIG_WORD: DW 0
CC_TEMP:    DW  0
DELAY_TEMP: DW  0