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
HEX_UP  EQU    4
HEX_LO  EQU    5


; TEST : TTL debug, CH0, input low threshold 
; Expected: signed mV offset from 0.8V threshold
TEST_TTL_IN0:
    LOADI   &B0000001100000111
    OUT     ADC
    CALL    WAIT_SINGLE
    IN      ADC
    STORE   RESULT_TTL
    CALL    CHECK_DEAD 
    OUT     HEX_UP
    CALL    HOLD
    JUMP    TEST_TTL_IN0

ERR_MISMATCH:
    ; Show "DEAD" on lower digits to indicate error mode test failed
    LOAD    FAIL_CONST
    OUT     HEX_UP
    JUMP    ERR_MISMATCH

; SUBROUTINES 

WAIT_SINGLE:
    LOADI   200
WAIT_S_LP:
    ADDI    -1
    JPOS    WAIT_S_LP
    RETURN

WAIT_DIFF:
    LOADI   400
WAIT_D_LP:
    ADDI    -1
    JPOS    WAIT_D_LP
    RETURN

; Hold display ~2 seconds so you can read each test result
HOLD:
    LOAD    HOLD_COUNT
    STORE   HOLD_TEMP
HOLD_LP:
    LOAD    HOLD_TEMP
    ADDI    -1
    STORE   HOLD_TEMP
    JPOS    HOLD_LP
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

CHECK_DEAD:
    STORE   CD_TEMP
    SUB     DEAD_CONST
    JZERO   ERR_MISMATCH
    LOAD    CD_TEMP
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