; Timing (CLK_DIV=1, 50MHz clock):
; I/O Map:
;   OUT 1 -> ADC config register
;   IN  2 -> ADC data read
; Config word format:
;   [1:0]  = mode    (00=single, 01=diff, 10=ttl, 11=err)
;   [4:2]  = pos channel select
;   [7:5]  = neg channel select (diff mode)
;   [9:8]  = ttl sub-config

ORG 0

; TEST 1: Single-ended, Channel 0
; config = 0x0000 -> mode=single, ch0
; Expected: 0x0XXX (upper nibble always 0)

TEST_SGL_CH0:
    LOADI   0x0000
    OUT     1
    CALL    WAIT_SINGLE
    IN      2
    STORE   RESULT_SGL_CH0
    CALL    CHECK_DEAD      


; TEST 2: Single-ended, Channel 1
; config = 0x0004 -> [4:2]=001, [1:0]=00

TEST_SGL_CH1:
    LOADI   0x0004
    OUT     1
    CALL    WAIT_SINGLE
    IN      2
    STORE   RESULT_SGL_CH1
    CALL    CHECK_DEAD


; TEST 3: Single-ended, Channel 7 (max channel)
; config = 0x001C -> [4:2]=111, [1:0]=00

TEST_SGL_CH7:
    LOADI   0x001C
    OUT     1
    CALL    WAIT_SINGLE
    IN      2
    STORE   RESULT_SGL_CH7
    CALL    CHECK_DEAD


; TEST 4: Differential, CH2(+) vs CH3(-)
; config = 0x006 9-> [7:5]=011(ch3-), [4:2]=010(ch2+), [1:0]=01
; Binary: 0000 0 011 010 01 = 0x0069

TEST_DIFF_CH2_CH3:
    LOADI   0x0069
    OUT     1
    CALL    WAIT_DIFF       
    IN      2
    STORE   RESULT_DIFF
    CALL    CHECK_DEAD


; TEST 5: TTL debug, input_0 (800mV threshold)
; config = 0x0002 -> [1:0]=10(ttl), [9:8]=00(ttl_input_0)

TEST_TTL_IN0:
    LOADI   0x0002
    OUT     1
    CALL    WAIT_SINGLE
    IN      2
    STORE   RESULT_TTL


; TEST 6: Error mode - bad mode bits
; config = 0x0003 -> [1:0]=11 (err)
; Expected: 0xDEAD

TEST_ERR_MODE:
    LOADI   0x0003
    OUT     1
    CALL    WAIT_SINGLE
    IN      2
    STORE   RESULT_ERR
    ; Expect 0xDEAD here
    LOADI   0xDEAD
    SUB     RESULT_ERR
    JZERO   DONE            

ERR_MISMATCH:
    JUMP    ERR_MISMATCH    

DONE:
    JUMP    DONE

; Result storage
RESULT_SGL_CH0:    DW 0x0000
RESULT_SGL_CH1:    DW 0x0000
RESULT_SGL_CH7:    DW 0x0000
RESULT_DIFF:       DW 0x0000
RESULT_TTL:        DW 0x0000
RESULT_ERR:        DW 0x0000