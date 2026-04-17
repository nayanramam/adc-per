ORG 0

Switches:  EQU 000
LEDs:      EQU 001
Timer:     EQU 002
ADC:       EQU 003
HEX_RIGHT: EQU 004
HEX_LEFT:  EQU 005

MAIN:
    IN      Switches
    STORE   SW_RAW
    AND     MASK_SW9
    JZERO   NORMAL_OP
    ; SW9 up — send invalid config, hardware returns 0xDEAD
    LOAD    MODE_INVALID
    OUT     ADC
    CALL    WAIT_ADC    ; added this because demo showed 7E6 which probably just read the stale value
    IN      ADC         ; OUT then immediately IN could've caused ADC to not show DEAD
    OUT     HEX_RIGHT
    JUMP    MAIN

NORMAL_OP:
    LOAD    SW_RAW
    AND     MASK_SW10
    STORE   TTL_SEL
    JZERO   USE_IN_LO
    ADDI    -1
    JZERO   USE_OUT_LO
    ADDI    -1
    JZERO   USE_IN_HI
    JUMP    USE_OUT_HI

USE_IN_LO:
    LOAD    CFG_IN_LO
    JUMP    SEND_CONFIG
USE_OUT_LO:
    LOAD    CFG_OUT_LO
    JUMP    SEND_CONFIG
USE_IN_HI:
    LOAD    CFG_IN_HI
    JUMP    SEND_CONFIG
USE_OUT_HI:
    LOAD    CFG_OUT_HI

SEND_CONFIG:
    STORE   CONFIG_WORD
    LOAD    CONFIG_WORD
    OUT     ADC
    CALL    WAIT_ADC        
    IN      ADC             
    OUT     HEX_RIGHT       ; signed mV difference from threshold
    LOAD    TTL_SEL
    OUT     HEX_LEFT        ; TTL_SEL (0/1/2/3)
    OUT     LEDs
    JUMP    MAIN

CFG_IN_LO:   DW  &H0010
CFG_OUT_LO:  DW  &H1010
CFG_IN_HI:   DW  &H2010
CFG_OUT_HI:  DW  &H3010
MODE_INVALID: DW &B0000000000011000
MASK_SW9:    DW  &B0000001000000000   ; isolate SW9
MASK_SW10:   DW  &B0000000000000011   ; isolate SW[1:0]
SW_RAW:      DW  0
TTL_SEL:     DW  0
CONFIG_WORD: DW  0