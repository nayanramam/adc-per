; ============================================================
; Differential ADC Demo -- Simulated Temperature Sensor
; ============================================================
;
; Hardware: Two potentiometers connected to the ADC:
;   CH0 -- 10k potentiometer (acts as the "sensor" input)
;   CH2 -- 1k  potentiometer (acts as the "reference" input)
;
; The ADC peripheral continuously samples both channels.
; In differential mode the result is:  V_CH0 - V_CH2 (in ADC counts).
;
; The voltage difference is mapped to a simulated temperature:
;   T_celsius = (ADC_diff - OFFSET) / DIVISOR
;
; With OFFSET=0 and DIVISOR=41 the full 0-4095 count range maps to 0-99 C.
;   - Turn the CH0 (10k) pot UP   to raise the temperature.
;   - Turn the CH2 (1k)  pot UP   to lower the temperature.
;   - When both pots produce the same voltage the reading is 0 C.
;   - Negative differences are clamped to 0 C; max is clamped to 99 C.
;
; ADC config word for differential CH0(+) vs CH2(-):
;   config[1:0] = 01  (differential mode)
;   config[4:2] = 000 (CH0, positive channel)
;   config[7:5] = 010 (CH2, negative channel)
;   => config = 0b 0000 0 010 000 01 = 0x0041 = 65 decimal
;
; Display layout:
;   HEX5-HEX4  raw ADC low byte (hex) -- live calibration reference
;   HEX3       '0' (leading zero)
;   HEX2       temperature tens digit  (decimal)
;   HEX1       temperature units digit (decimal)
;   HEX0       'C' (Celsius indicator, 0xC on 7-segment shows as C)
;   Example: 25 C  -> HEX shows  [FA]  [0 2 5 C]
;                                  ^raw ADC low byte = 0xFA
;
; IO address map:
;   0x003  ADC    (write 16-bit config; read signed 16-bit differential)
;   0x004  HEX_UP (HEX5[7:4] | HEX4[3:0])
;   0x005  HEX_LO (HEX3[15:12] | HEX2[11:8] | HEX1[7:4] | HEX0[3:0])

    ORG    0

; ---------- IO address equates ----------
ADC     EQU    3
HEX_UP  EQU    4
HEX_LO  EQU    5

; ---------- Initialization ----------
; Write the differential config word once; the ADC peripheral latches
; it and the combinational output path uses it immediately.
    LOADI  65          ; 0x41 = differential mode, CH0(+), CH2(-)
    OUT    ADC

; ---------- Main measurement loop ----------
MAIN:   IN     ADC     ; read signed 16-bit differential result
        STORE  ADCRAW  ; save for the calibration display on HEX5-HEX4

        ; Apply voltage-offset to get a value proportional to degrees
        ; AC is still the ADC result after STORE (STORE does not change AC)
        SUB    OFFSET
        JNEG   CLAMPL  ; below 0 °C -- show 0

        ; Divide by DIVISOR using repeated subtraction
        ; Works for any DIVISOR; for DIVISOR=10 this loops at most ~100 times
        STORE  REMAIN
        LOADI  0
        STORE  CELSIUS

DIVLP:  LOAD   REMAIN
        SUB    DIVISOR
        JNEG   DIVDN   ; remainder < DIVISOR: quotient is complete
        STORE  REMAIN
        LOAD   CELSIUS
        ADDI   1
        STORE  CELSIUS
        JUMP   DIVLP

DIVDN:  ; Clamp to 99 °C (two-digit BCD display limit)
        LOAD   CELSIUS
        SUB    NINETYN
        JPOS   CLAMPH  ; > 99: cap at 99
        JUMP   SHOW    ; 0..99: pass through unchanged

CLAMPL: LOADI  0
        STORE  CELSIUS
        JUMP   SHOW

CLAMPH: LOAD   NINETYN
        STORE  CELSIUS
        ; fall through to SHOW

; ---------- BCD conversion and display ----------
; Convert CELSIUS (0-99) to two decimal digits and build display word.
SHOW:   LOADI  0
        STORE  TENS
        LOAD   CELSIUS
        STORE  REMAIN  ; reuse REMAIN as BCD countdown

TENLP:   LOAD   REMAIN
        SUB    TEN
        JNEG   TENDN   ; REMAIN < 10: TENS is done
        STORE  REMAIN  ; REMAIN -= 10
        LOAD   TENS
        ADDI   1
        STORE  TENS
        JUMP   TENLP

TENDN:  ; TENS  = tens digit (0-9)
        ; REMAIN = units digit (0-9)

        ; HEX5-HEX4: raw ADC low byte for calibration reference
        LOAD   ADCRAW
        AND    MASK_FF
        OUT    HEX_UP

        ; Build 16-bit display word: 0x0TUC
        ;   bits [15:12] = 0     → HEX3 shows '0'
        ;   bits [11:8]  = tens  → HEX2 shows tens decimal digit
        ;   bits [7:4]   = units → HEX1 shows units decimal digit
        ;   bits [3:0]   = 0xC  → HEX0 shows 'C' (Celsius)
        LOAD   TENS
        SHIFT  8         ; left shift 8 → tens into bits [11:8]
        STORE  DWORD

        LOAD   REMAIN    ; units digit
        SHIFT  4         ; left shift 4 → units into bits [7:4]
        OR     DWORD     ; merge with tens: 0x0TU0
        ADD    MASK_0C   ; add 0x000C → 0x0TUC
        OUT    HEX_LO

        JUMP   MAIN

; ============================================================
; CALIBRATION CONSTANTS
; ============================================================
; DIVISOR=41 maps the full differential range (0..4095) to 0..99 C.
; OFFSET=0 means equal pot voltages read as 0 C.
OFFSET:  DW     0     ; ADC counts at 0 C
DIVISOR: DW     41    ; ADC counts per degree Celsius

; ---------- Other constants ----------
MASK_FF: DW     255   ; 0x00FF -- mask to low byte
MASK_0C: DW     12    ; 0x000C -- 'C' character on HEX0 (7-segment hex C)
TEN:     DW     10    ; for BCD tens extraction
NINETYN: DW     99    ; upper display clamp

; ---------- Variables ----------
ADCRAW:  DW     0     ; raw signed ADC differential reading
CELSIUS: DW     0     ; computed temperature in whole degrees C
TENS:    DW     0     ; BCD tens digit
REMAIN:  DW     0     ; scratch: division remainder / BCD units
DWORD:   DW     0     ; scratch: partial display word
