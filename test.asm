; ADC Peripheral Test Suite + Live Voltage Display
; Register map:
;   [1:0]  IO_MODE       00=single, 01=diff, 10=ttl, 11=err
;   [4:2]  IO_ADDR_POS   positive channel (0-7)
;   [7:5]  IO_ADDR_NEG   negative channel (0-7)
;   [9:8]  TTL_CONFIG    sub-mode config
;
; 7-seg: OUT 4 = right 4 hex digits, OUT 5 = left 2 hex digits
; ADC config write: OUT 1   ADC data read: IN 2

ORG 0

; ===== TEST 1: Single-ended, Channel 0 =====
; Expected: mV of voltage on CH0 (e.g. GND=0x0000, 3.3V=~0x0CE4)
TEST_SGL_CH0:
    LOADI   &B0000000000000000
    OUT     1
    CALL    WAIT_SINGLE
    IN      2
    STORE   RESULT_SGL_CH0
    CALL    CHECK_DEAD
    OUT     4
    CALL    HOLD

; ===== TEST 2: Single-ended, Channel 1 =====
; Expected: mV of voltage on CH1
TEST_SGL_CH1:
    LOADI   &B0000000000000100
    OUT     1
    CALL    WAIT_SINGLE
    IN      2
    STORE   RESULT_SGL_CH1
    CALL    CHECK_DEAD
    OUT     4
    CALL    HOLD

; ===== TEST 3: Single-ended, Channel 7 =====
; Expected: mV of voltage on CH7
TEST_SGL_CH7:
    LOADI   &B0000000000011100
    OUT     1
    CALL    WAIT_SINGLE
    IN      2
    STORE   RESULT_SGL_CH7
    CALL    CHECK_DEAD
    OUT     4
    CALL    HOLD

; ===== TEST 4: Differential, CH2(+) vs CH3(-) =====
; Expected: signed mV difference (CH2 - CH3), two's complement
TEST_DIFF_CH2_CH3:
    LOADI   &B0000000001101001
    OUT     1
    CALL    WAIT_DIFF
    IN      2
    STORE   RESULT_DIFF
    CALL    CHECK_DEAD
    OUT     4
    CALL    HOLD

; ===== TEST 5: TTL debug, CH0, input low threshold =====
; Expected: signed mV offset from 0.8V threshold
TEST_TTL_IN0:
    LOADI   &B0000000000000010
    OUT     1
    CALL    WAIT_SINGLE
    IN      2
    STORE   RESULT_TTL
    OUT     4
    CALL    HOLD

; ===== TEST 6: Error mode (expect 0xDEAD on display) =====
; IO_MODE=11 is invalid, peripheral should return 0xDEAD
TEST_ERR_MODE:
    LOADI   &B0000000000000011
    OUT     1
    CALL    WAIT_SINGLE
    IN      2
    STORE   RESULT_ERR
    OUT     4               ; should show "DEAD" on right digits
    CALL    HOLD

    ; Verify it was actually 0xDEAD
    LOAD    DEAD_CONST
    SUB     RESULT_ERR
    JZERO   LIVE_DISPLAY

ERR_MISMATCH:
    ; Show "FFFF" to indicate error mode test failed
    LOAD    FAIL_CONST
    OUT     4
    JUMP    ERR_MISMATCH

; ===== LIVE VOLTAGE DISPLAY: CH0 continuous read =====
; Reached only after all tests pass
; Display shows live hex mV value: GND=0000, 3.3V=0CE4, 4.096V=1000
LIVE_DISPLAY:
    LOADI   &B0000000000000000
    OUT     1
    CALL    WAIT_SINGLE
    IN      2
    OUT     4
    CALL    DELAY
    JUMP    LIVE_DISPLAY


; ===== SUBROUTINES =====

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


; ===== DATA & CONSTANTS =====
HOLD_COUNT:     DW 20000
DELAY_COUNT:    DW 10000
HOLD_TEMP:      DW &B0000000000000000
DELAY_TEMP:     DW &B0000000000000000
DEAD_CONST:     DW &B1101111010101101  ; 0xDEAD
FAIL_CONST:     DW &B1111111111111111  ; 0xFFFF - shown if error test fails
CD_TEMP:        DW &B0000000000000000

; Results
RESULT_SGL_CH0: DW &B0000000000000000
RESULT_SGL_CH1: DW &B0000000000000000
RESULT_SGL_CH7: DW &B0000000000000000
RESULT_DIFF:    DW &B0000000000000000
RESULT_TTL:     DW &B0000000000000000
RESULT_ERR:     DW &B0000000000000000