; Register map:
;   [1:0]  IO_MODE       00=single, 01=diff, 10=ttl, 11=err
;   [4:2]  IO_ADDR_POS   positive channel (0-7)
;   [7:5]  IO_ADDR_NEG   negative channel (0-7)
;   [9:8]  TTL_CONFIG    sub-mode config
;
; IO address map:
;   ADC    EQU 3
;   HEX_UP EQU 4
;   HEX_LO EQU 5
;
; TEST: Differential, CH0(+) vs CH1(-)
; Config word:
;   [1:0] = 01  -> differential mode
;   [4:2] = 000 -> CH0 positive channel
;   [7:5] = 001 -> CH1 negative channel
;   => 0b0000000000100001 = 33 decimal

ORG 0

; IO address constants
ADC     EQU    3
HEX_UP  EQU    4
HEX_LO  EQU    5

; TEST: Differential, CH0(+) vs CH1(-)
; Expected: signed mV difference (CH0 - CH1), twos complement
TEST_DIFF_CH0_CH1:
    LOADI   &B0000000000100001  ; differential mode, CH0(+), CH1(-)
    OUT     ADC
    CALL    WAIT_DIFF
    IN      ADC
    STORE   RESULT_DIFF
    CALL    CHECK_DEAD
    OUT     HEX_UP
    CALL    HOLD
    JUMP    TEST_DIFF_CH0_CH1

ERR_MISMATCH:
    ; Show "FFFF" on upper digits to indicate error mode test failed
    LOAD    FAIL_CONST
    OUT     HEX_UP
    JUMP    ERR_MISMATCH

; SUBROUTINES

WAIT_DIFF:
    LOADI   400

; Hold display ~2 seconds so you can read each test result
HOLD:
    LOAD    HOLD_COUNT
    STORE   HOLD_TEMP

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
FAIL_CONST:     DW &B1111111111111111  ; 0xFFFF - shown if error test fails
CD_TEMP:        DW &B0000000000000000

; Results
RESULT_DIFF:    DW &B0000000000000000
