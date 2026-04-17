; Register map:
;   [1:0]  IO_MODE       00=single, 01=diff, 10=ttl, 11=err
;   [4:2]  IO_ADDR_POS   positive channel (0-7)
;   [7:5]  IO_ADDR_NEG   negative channel (0-7)
;   [9:8]  TTL_CONFIG    sub-mode config
;
; IO address map (matched to game file):
;   ADC    EQU 3
;   HEX_UP EQU 4
;   HEX_LO EQU 5

ORG 0

; IO address constants
ADC     EQU    3
HEX_UP  EQU    4  ; lower 4 digits
HEX_LO  EQU    5  ; upper 4 digits

; Send config once before the loop (VHDL latches it)
; Single-ended, CH0, no TTL config needed
    LOADI   &B0000000000001000
    OUT     ADC

; LIVE VOLTAGE DISPLAY: CH0 continuous read
LIVE_DISPLAY:
    CALL    WAIT_SINGLE
    IN      ADC
    OUT     HEX_UP
    CALL    DELAY
    JUMP    LIVE_DISPLAY
; SUBROUTINES

WAIT_SINGLE:
    LOADI   200
WAIT_S_LP:
    ADDI    -1
    JPOS    WAIT_S_LP
    RETURN

; Short delay to prevent display flicker in live mode
DELAY:
    LOAD    DELAY_COUNT
    STORE   DELAY_TEMP
DELAY_LP:
    LOAD    DELAY_TEMP
    ADDI    -1
    STORE   DELAY_TEMP
    JPOS    DELAY_LP
    RETURN

; DATA & CONSTANTS
HOLD_COUNT:     DW 20000
DELAY_COUNT:    DW 10000
HOLD_TEMP:      DW &B0000000000000000
DELAY_TEMP:     DW &B0000000000000000
DEAD_CONST:     DW &B1101111010101101  ; 0xDEAD
FAIL_CONST:     DW &B1101111010101101  ; 0xDEAD - shown if error test fails
CD_TEMP:        DW &B0000000000000000

; Results
RESULT_SGL_CH0: DW &B0000000000000000
RESULT_SGL_CH1: DW &B0000000000000000
RESULT_SGL_CH7: DW &B0000000000000000
RESULT_DIFF:    DW &B0000000000000000
RESULT_TTL:     DW &B0000000000000000
RESULT_ERR:     DW &B0000000000000000