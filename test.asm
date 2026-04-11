; Register map (reg_map planning.xlsx):
;   [1:0]  IO_MODE       00=single, 01=diff, 10=ttl, 11=err
;   [4:2]  IO_ADDR_POS   positive channel (0-7)
;   [7:5]  IO_ADDR_NEG   negative channel (0-7)
;   [9:8]  TTL_CONFIG    sub-mode config

ORG 0

; ===== TEST 1: Single-ended, Channel 0 =====
TEST_SGL_CH0:
    LOADI   0x0000
    OUT     1
    CALL    WAIT_SINGLE
    IN      2
    STORE   RESULT_SGL_CH0
    CALL    CHECK_DEAD

; ===== TEST 2: Single-ended, Channel 1 =====
TEST_SGL_CH1:
    LOADI   0x0004
    OUT     1
    CALL    WAIT_SINGLE
    IN      2
    STORE   RESULT_SGL_CH1
    CALL    CHECK_DEAD

; ===== TEST 3: Single-ended, Channel 7 =====
TEST_SGL_CH7:
    LOADI   0x001C
    OUT     1
    CALL    WAIT_SINGLE
    IN      2
    STORE   RESULT_SGL_CH7
    CALL    CHECK_DEAD

; ===== TEST 4: Differential, CH2(+) vs CH3(-) =====
TEST_DIFF_CH2_CH3:
    LOADI   0x0069
    OUT     1
    CALL    WAIT_DIFF
    IN      2
    STORE   RESULT_DIFF
    CALL    CHECK_DEAD

; ===== TEST 5: TTL debug, input_0 =====
TEST_TTL_IN0:
    LOADI   0x0002
    OUT     1
    CALL    WAIT_SINGLE
    IN      2
    STORE   RESULT_TTL

; ===== TEST 6: Error mode (expect 0xDEAD) =====
TEST_ERR_MODE:
    LOADI   0x0003
    OUT     1
    CALL    WAIT_SINGLE
    IN      2
    STORE   RESULT_ERR
    
    ; FIX: Must LOAD from memory; LOADI 0xDEAD is too large for SCOMP
    LOAD    DEAD_CONST      
    SUB     RESULT_ERR      
    JZERO   DONE            

ERR_MISMATCH:
    JUMP    ERR_MISMATCH    

DONE:
    JUMP    DONE            

; Subroutines

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

CHECK_DEAD:
    STORE   CD_TEMP         
    SUB     DEAD_CONST      
    JZERO   ERR_MISMATCH    
    LOAD    CD_TEMP         
    RETURN


; Data & Constants
DEAD_CONST:     DW 0xDEAD   
CD_TEMP:        DW 0        

; Results
RESULT_SGL_CH0: DW 0
RESULT_SGL_CH1: DW 0
RESULT_SGL_CH7: DW 0
RESULT_DIFF:    DW 0
RESULT_TTL:     DW 0
RESULT_ERR:     DW 0