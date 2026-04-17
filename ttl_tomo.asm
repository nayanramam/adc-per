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
;   SW9     — force invalid input, triggers 0xDEAD from hardware
;
; DISPLAY:
;   HEX_UP — config word
;   HEX_LO — ADC result (signed TTL difference in mV)
;   LEDs   — mirrors TTL_SEL (0-3)

ORG 0

; I/O Addresses (verified from Lab 8)
Switches:  EQU 000
LEDs:      EQU 001
Timer:     EQU 002
ADC:       EQU 003
HEX_UP:    EQU 004
HEX_LO:    EQU 005

MAIN:
    IN      Switches
    STORE   SW_RAW

    ; --- Check if SW9 is up (force invalid input) ---
    AND     MASK_SW9
    JZERO   NORMAL_OP       ; SW9 down — normal operation

    ; --- SW9 up: send invalid config (IO_MODE=11) to trigger DEAD ---
    LOAD    MODE_INVALID
    OUT     ADC
    CALL    WAIT_ADC
    IN      ADC             ; hardware returns 0xDEAD
    OUT     HEX_UP
    OUT     HEX_LO
    JUMP    MAIN            ; keep looping so SW9 can be lowered

NORMAL_OP:
    LOAD    SW_RAW
    AND     MASK_SW10
    STORE   TTL_SEL

    ; --- Jump to correct config word based on SW[1:0] ---
    JZERO   USE_IN_LO       ; SW=00 => Input  LOW  (0.8V)
    ADDI    -1
    JZERO   USE_OUT_LO      ; SW=01 => Output LOW  (0.4V)
    ADDI    -1
    JZERO   USE_IN_HI       ; SW=10 => Input  HIGH (2.0V)
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

    ; --- Send config to ADC ---
    LOAD    CONFIG_WORD
    OUT     ADC

    CALL    WAIT_ADC

    LOAD    CONFIG_WORD
    OUT     HEX_UP

    LOAD    TTL_SEL
    OUT     HEX_LO

    LOAD    TTL_SEL
    OUT     LEDs

    CALL    DELAY
    JUMP    MAIN


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
;   00 => &H0010  Input  LOW  (0.8V)
;   01 => &H1010  Output LOW  (0.4V)
;   10 => &H2010  Input  HIGH (2.0V)
;   11 => &H3010  Output HIGH (2.7V)
CFG_IN_LO:   DW  &H0010
CFG_OUT_LO:  DW  &H1010
CFG_IN_HI:   DW  &H2010
CFG_OUT_HI:  DW  &H3010

; Invalid config — IO_MODE=11 at [4:3] => triggers 0xDEAD from hardware
MODE_INVALID: DW &B0000000000011000

; Switch masks
MASK_SW9:    DW  &B0000001000000000   ; isolate SW9
MASK_SW10:   DW  &B0000000000000011   ; isolate SW[1:0]

; Delay tuning
DELAY_COUNT: DW  5000

; Scratch
SW_RAW:      DW  0
TTL_SEL:     DW  0
CONFIG_WORD: DW  0
DELAY_TEMP:  DW  0