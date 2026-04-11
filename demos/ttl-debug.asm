; ============================================================
; TTL Debug Demo -- Logic Level Classifier
; ============================================================
;
; Hardware: Connect the signal under test to ADC channel 0.
;           (Change CFG_VIL / CFG_VIH below to use another channel.)
;
; Operation:
;   Each loop reads the channel TWICE using two TTL input thresholds:
;     Read 1 -- V_IL threshold (800 mV):  result = V - 800
;     Read 2 -- V_IH threshold (2000 mV): result = V - 2000
;
;   Classification (standard TTL input levels):
;     LOW       V < 800 mV            (valid logic 0)
;     UNDEF     800 mV <= V <= 2000 mV (forbidden / indeterminate zone)
;     HIGH      V > 2000 mV           (valid logic 1)
;
;   The signed result from the ADC already IS the mV difference from
;   each threshold (1 LSB = 1 mV for the LTC2308 at 4.096 V reference).
;
; ADC config word for TTL debug mode:
;   config[1:0] = 10       (ttl_debug mode)
;   config[4:2] = channel  (000=CH0, 001=CH1, ...)
;   config[7:5] = 000      (unused in ttl_debug)
;   config[9:8] = select   (00=V_IL 800mV  01=V_OL 400mV
;                            10=V_IH 2000mV 11=V_OH 2700mV)
;
;   CH0 + V_IL (800 mV):  0b 00_000_000_10 =   2
;   CH0 + V_IH (2000 mV): 0b 10_000_000_10 = 514
;   To use CH1 instead:   add 4 to each (4 = 1 << 2 for config[4:2])
;
; Display layout:
;   LEDs        LOW: bottom 5 lit | UNDEF: all 10 lit | HIGH: top 5 lit
;   HEX5        state code: 0=LOW  1=UNDEF  2=HIGH
;   HEX4        0 (spacer)
;   HEX3-HEX0   mV distance from the NEAREST threshold (always positive):
;                 LOW   -> 800  - V   (margin BELOW V_IL, i.e. how clean the 0 is)
;                 UNDEF -> V    - 800 (distance PAST V_IL into forbidden zone)
;                 HIGH  -> V    - 2000 (margin ABOVE V_IH, i.e. how clean the 1 is)
;
;   Examples (hex display, 1 LSB = 1 mV):
;     300 mV clean LOW:    LEDs[4:0] on, HEX = "0  01F4"  (500 mV below V_IL)
;     1200 mV forbidden:   all LEDs on,  HEX = "1  01F4"  (400 mV past V_IL)
;     3300 mV clean HIGH:  LEDs[9:5] on, HEX = "2  0514"  (1300 mV above V_IH)
;
; IO address map:
;   0x001  DIG_OUT (LED bar indicator)
;   0x003  ADC     (write config word; read signed 16-bit result)
;   0x004  HEX_UP  (HEX5 in bits[7:4], HEX4 in bits[3:0])
;   0x005  HEX_LO  (HEX3 in bits[15:12] ... HEX0 in bits[3:0])

    ORG    0

; ---------- IO addresses ----------
LEDS    EQU    1
ADC     EQU    3
HEX_UP  EQU    4
HEX_LO  EQU    5

; ---------- ADC config words ----------
; Default: CH0.  To use CH1 change both values to 10 and 522 (add 4 each).
CFG_VIL EQU    2      ; ttl_debug, CH0, V_IL threshold (800 mV)
CFG_VIH EQU    514    ; ttl_debug, CH0, V_IH threshold (2000 mV)

; ============================================================
; Main measurement loop
; ============================================================
MAIN
        ; --- Read 1: measure V - V_IL (800 mV) ---
        LOADI  CFG_VIL
        OUT    ADC
        IN     ADC
        STORE  DIL          ; DIL = V - 800  (negative if V < V_IL)

        ; --- Read 2: measure V - V_IH (2000 mV) ---
        LOADI  CFG_VIH
        OUT    ADC
        IN     ADC
        STORE  DIH          ; DIH = V - 2000 (positive if V > V_IH)

        ; --- Classify signal ---
        LOAD   DIL
        JNEG   IS_LOW       ; V < 800 mV -> valid LOW

        LOAD   DIH
        JPOS   IS_HIGH      ; V > 2000 mV -> valid HIGH

        ; ----- UNDEFINED: 800 mV <= V <= 2000 mV -----
        ; Show how far past V_IL the signal has drifted into the forbidden zone.
        LOADI  1023         ; 0b1111111111: all 10 LEDs on (danger indicator)
        OUT    LEDS
        LOADI  16           ; HEX5 = '1' (undef), HEX4 = '0'
        OUT    HEX_UP
        LOAD   DIL          ; DIL = V - 800 >= 0 here; shows depth into forbidden zone
        OUT    HEX_LO
        JUMP   MAIN

IS_LOW  ; ----- LOW: V < 800 mV -----
        ; Show margin below V_IL: how much room to spare before the forbidden zone.
        LOADI  31           ; 0b0000011111: bottom 5 LEDs (valid low)
        OUT    LEDS
        LOADI  0            ; HEX5 = '0' (low), HEX4 = '0'
        OUT    HEX_UP
        LOADI  0
        SUB    DIL          ; 0 - (V - 800) = 800 - V  (positive margin)
        OUT    HEX_LO
        JUMP   MAIN

IS_HIGH ; ----- HIGH: V > 2000 mV -----
        ; Show margin above V_IH: how much room to spare above the threshold.
        LOADI  992          ; 0b1111100000: top 5 LEDs (valid high)
        OUT    LEDS
        LOADI  32           ; HEX5 = '2' (high), HEX4 = '0'
        OUT    HEX_UP
        LOAD   DIH          ; DIH = V - 2000 > 0; margin above V_IH
        OUT    HEX_LO
        JUMP   MAIN

; ---------- Variables ----------
DIL     DW     0            ; V - 800  (signed)
DIH     DW     0            ; V - 2000 (signed)
