; ============================================================
; Differential Mode Digital Thermometer — SCOMP Assembly
; ECE 2031 Project
;
; Sensor wiring (LM35 or equivalent, 10 mV/°C):
;   CH0 (ADC IN0) — sensor output (positive terminal)
;   CH1 (ADC IN1) — ground reference (negative terminal)
;
; ADC: LTC2308, 12-bit
;   Internal Vref = 4.096 V  →  1 LSB = 1 mV
;   Temperature formula: Temp (°C) = ADC_DATA / 10
;   Example: 25 °C → 250 mV → 250 counts → 250 / 10 = 25
;
; Register map (reg_map planning.xlsx):
;
;   Config register  (OUT 1 to write):
;     [1:0]  IO_MODE         01 = differential mode (used here)
;     [4:2]  IO_ADDRESS      000 = CH0 as positive input
;     [7:5]  IO_ADDRESS_NEG  001 = CH1 as negative input
;     [9:8]  TTL_CONFIG      not used (TTL mode not selected)
;
;   Config word for CH0(+) vs CH1(-) differential:
;     IO_MODE=01, IO_ADDRESS=000, IO_ADDRESS_NEG=001
;     binary: 00_100_001 = 0x21 (33 decimal)
;
;   Data register  (IN 2 to read):
;     [11:0] ADC_DATA        12-bit differential result, sign-extended
;            bits [15:12] = sign extension of bit 11
;
; I/O map:
;   OUT 1  — write Config register
;   IN  2  — read Data register  (ADC_DATA in bits [11:0])
;   OUT 6  — Alt7Seg hex-digit mode: [9:7]=display pos, [3:0]=digit
;   OUT 7  — Alt7Seg clear all six displays
;
; Display layout (HEX5 … HEX0, left to right):
;   HEX2 = 'C'  (Celsius label, hex digit 0xC)
;   HEX1 = tens digit of temperature
;   HEX0 = units digit of temperature
;
; Display encoding for OUT 6 (m_hex_digit mode):
;   position 0 (HEX0): io_data = 0x0000 | digit
;   position 1 (HEX1): io_data = 0x0080 | digit   (bits[9:7]="001")
;   position 2 (HEX2): io_data = 0x0100 | digit   (bits[9:7]="010")
;   'C' at HEX2: 0x0100 | 0x000C = 0x010C (268 decimal)
;
; Division by 10 is performed via repeated subtraction (no hardware
; multiply/divide on SCOMP).  For 0–99 °C this needs ≤ 10 + 9 = 19
; iterations total, well within the thermometer sampling budget.
;
; Calibration constants in ADC.vhd (TTL debug mode offsets) are
; NOT used here and are left untouched.
; ============================================================

ORG 0

; ===== Initialisation =====
INIT:
    LOADI   0
    OUT     7               ; clear all six 7-segment displays

; ===== Main sampling loop =====
MAIN:
    ; ---- Step 1: write Config register — differential CH0(+) vs CH1(-) ----
    ; IO_MODE=01, IO_ADDRESS=000, IO_ADDRESS_NEG=001 → 0x0021 = 33
    LOADI   33
    OUT     1               ; Config register → ADC peripheral

    ; ---- Step 2: wait for at least one complete ADC round-robin ----
    ; LTC2308 round-robin: 8 channels × ~70 system clocks ≈ 560 clocks.
    ; Each WAIT_LP iteration ≈ 4 SCOMP clocks.
    ; 300 iterations × 4 = 1200 clocks >> 560 — both channels freshly sampled.
    CALL    WAIT

    ; ---- Step 3: read Data register — ADC_DATA in bits [11:0] ----
    ; Differential result is sign-extended: bit 15 = sign of ADC_DATA[11]
    IN      2               ; AC = ADC_DATA (signed 16-bit, mV)
    STORE   ADC_RAW

    ; ---- Step 4: clamp negative readings to 0 °C ----
    JNEG    SHOW_ZERO

    ; ---- Step 5: first DIV10 → temperature in whole °C ----
    ; AC = ADC_RAW at this point (JNEG does not modify AC)
    CALL    DIV10           ; QUOT = ADC_RAW / 10 = degrees Celsius
    LOAD    QUOT
    STORE   TEMP_C          ; AC = TEMP_C after STORE (AC unchanged by STORE)

    ; ---- Step 6: second DIV10 → extract two display digits ----
    ; AC = TEMP_C here
    CALL    DIV10           ; QUOT = tens digit, REMD = units digit
    LOAD    QUOT
    STORE   TENS
    LOAD    REMD
    STORE   UNITS
    JUMP    SHOW_TEMP

; --- Show 00C when reading is negative (below 0 °C) ---
SHOW_ZERO:
    LOADI   0
    STORE   TENS
    STORE   UNITS           ; falls through to SHOW_TEMP

; ===== Output temperature on 7-segment displays =====
SHOW_TEMP:
    ; HEX0 = units digit (position 0: bits[9:7]=000, no offset needed)
    LOAD    UNITS
    OUT     6

    ; HEX1 = tens digit  (position 1: bits[9:7]=001 → add 0x0080 = 128)
    LOAD    TENS
    ADD     POS1            ; POS1 = 128 = 0x0080
    OUT     6

    ; HEX2 = 'C' label   (position 2, digit 0xC → 0x010C = 268)
    LOAD    C_LABEL         ; C_LABEL = 268 = 0x010C
    OUT     6

    JUMP    MAIN

; ============================================================
; WAIT — busy-wait for ADC round-robin to complete
; No arguments, no return value; clobbers WAIT_N.
; ============================================================
WAIT:
    LOAD    WAIT_INIT       ; 300
    STORE   WAIT_N
WAIT_LP:
    LOAD    WAIT_N
    SUB     ONE
    STORE   WAIT_N
    JPOS    WAIT_LP         ; loop while WAIT_N > 0
    RETURN

; ============================================================
; DIV10 — unsigned integer division by 10 (repeated subtraction)
;
; Input  : AC = numerator (non-negative, 0..4095)
; Output : QUOT  = AC_in / 10
;          REMD  = AC_in mod 10
; Clobbers: DIV_N, QUOT, REMD
;
; The caller must ensure AC ≥ 0 before calling.
; For the thermometer: AC ≤ 500 (50 °C max practical), so the loop
; runs at most 50 iterations on the first call and 9 on the second.
; ============================================================
DIV10:
    STORE   DIV_N           ; save the value to divide
    LOADI   0
    STORE   QUOT            ; quotient ← 0
DIV10_LP:
    LOAD    DIV_N
    SUB     TEN             ; compute DIV_N - 10
    JNEG    DIV10_END       ; if result < 0 then DIV_N < 10, done
    STORE   DIV_N           ; DIV_N ← DIV_N - 10
    LOAD    QUOT
    ADD     ONE
    STORE   QUOT            ; quotient++
    JUMP    DIV10_LP
DIV10_END:
    LOAD    DIV_N
    STORE   REMD            ; remainder = remaining DIV_N (< 10)
    RETURN

; ============================================================
; Read-only constants (stored in program/data memory)
; ============================================================
ONE:        DW 1
TEN:        DW 10
POS1:       DW 128          ; 0x0080: display-select field for HEX1 (position 1)
C_LABEL:    DW 268          ; 0x010C: 'C' glyph (digit 0xC) at display position 2
WAIT_INIT:  DW 300          ; iteration count for WAIT subroutine

; ============================================================
; Read-write variables
; ============================================================
ADC_RAW:    DW 0            ; raw signed ADC_DATA result (mV, sign-extended)
TEMP_C:     DW 0            ; temperature in whole degrees Celsius
TENS:       DW 0            ; tens digit  (0..9)
UNITS:      DW 0            ; units digit (0..9)
QUOT:       DW 0            ; DIV10 quotient
REMD:       DW 0            ; DIV10 remainder
DIV_N:      DW 0            ; DIV10 working copy of numerator
WAIT_N:     DW 0            ; WAIT loop counter
