; ============================================================
; Single-Ended ADC Demo -- Potentiometer Matching Game
; ============================================================
;
; Hardware: Connect a potentiometer wiper to ADC channel 0.
;           The pot's two ends connect to the ADC reference
;           voltage (4.096V) and GND.
;
; Game rules:
;   A two-digit hex TARGET is shown on HEX3-HEX2.
;   Turn the potentiometer until YOUR VALUE on HEX1-HEX0
;   is within +/-8 of the target to score a point.
;   After each match you must move away before the next
;   match counts.  You have 30 seconds -- go!
;   Final score is shown on HEX5-HEX4 when time expires.
;
; Display layout (left to right on DE1-SoC):
;   HEX5  HEX4  |  HEX3  HEX2  |  HEX1  HEX0
;    SCORE (hex) |  TARGET (hex) |  YOUR VALUE (hex)
;
; IO address map:
;   0x002  TIMER   -- 10 Hz clock; write any value to reset
;   0x003  ADC     -- write config word; read 12-bit result
;   0x004  HEX_UP  -- HEX5[7:4] HEX4[3:0]   (score)
;   0x005  HEX_LO  -- HEX3[15:12] HEX2[11:8] HEX1[7:4] HEX0[3:0]
;
; ADC config word for single-ended channel 0:
;   bits [4:2] = 000  (channel 0)
;   bits [1:0] = 00   (single-ended mode)
;   => config = 0x0000
;
; SHIFT instruction operand encoding (SCOMP, sign-magnitude %s5):
;   Positive operand = left shift,  negative = right shift.
;   SHIFT  8 = left  shift by 8
;   SHIFT -4 = right shift by 4

    ORG    0

; ---------- IO address constants ----------
TIMER   EQU    2
ADC     EQU    3
HEX_UP  EQU    4
HEX_LO  EQU    5

; ---------- Initialization ----------
    LOADI  0
    STORE  SCORE
    STORE  MATCHED
    OUT    TIMER          ; reset timer to 0

    ; Seed the first target from the timer (likely 0 at start,
    ; giving a clear "turn the pot to minimum" first challenge)
    IN     TIMER
    AND    MASK_FF
    STORE  TARGET

; ---------- Main game loop ----------
MAIN:   IN     TIMER
        SUB    TLIMIT
        JPOS   OVER       ; time's up when timer > 300

        ; Send ADC config: channel 0, single-ended (0x0000)
        LOADI  0
        OUT    ADC

        ; Read 12-bit ADC result, scale to 8 bits (right-shift 4)
        IN     ADC
        SHIFT  -4
        STORE  ADCVAL

        ; Refresh display
        CALL   SHOW

        ; ---- Match detection: |ADCVAL - TARGET| <= THRESH ----
        LOAD   ADCVAL
        SUB    TARGET
        JNEG   BELOW      ; ADCVAL < TARGET

        ; ADCVAL >= TARGET: check ADCVAL - TARGET <= THRESH
        SUB    THRESH
        JPOS   MISS
        JUMP   HIT

BELOW:  ; ADCVAL < TARGET: check TARGET - ADCVAL <= THRESH
        LOAD   TARGET
        SUB    ADCVAL
        SUB    THRESH
        JPOS   MISS

HIT:    ; Within tolerance -- was already matched last cycle?
        LOAD   MATCHED
        JPOS   MAIN       ; hold-off: must release before next point

        ; Register the new match
        LOADI  1
        STORE  MATCHED
        LOAD   SCORE
        ADDI   1
        STORE  SCORE

        ; Pick a new target from the running timer
        IN     TIMER
        AND    MASK_FF
        STORE  TARGET

        JUMP   MAIN

MISS:   LOADI  0          ; outside tolerance: clear hold-off flag
        STORE  MATCHED
        JUMP   MAIN

; ---------- Game over: freeze on final score ----------
OVER:   CALL   SHOW
        JUMP   OVER

; ---------- Display subroutine ----------
; Writes score to HEX5-HEX4 and packs
; target (high byte) | ADC value (low byte) into HEX3-HEX0.
SHOW:   LOAD   SCORE
        OUT    HEX_UP

        LOAD   TARGET
        SHIFT  8          ; move target into upper byte
        OR     ADCVAL     ; merge: [TARGET | ADCVAL]
        OUT    HEX_LO
        RETURN

; ---------- Constants ----------
MASK_FF: DW    255        ; 0x00FF -- mask for lower 8 bits
THRESH:  DW    8          ; match tolerance: +/-8 out of 256
TLIMIT:  DW    300        ; 30 seconds x 10 Hz = 300 ticks

; ---------- Variables ----------
SCORE:   DW    0
TARGET:  DW    0
ADCVAL:  DW    0
MATCHED: DW    0          ; 1 = currently inside match zone
