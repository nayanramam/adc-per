; [1:0] = IO Mode
; [4:2] = Channel Address Pos
; [7:5] = Channel Address Neg
; [9:8] = TTL Configuration
; Config word: &B XXXXXX XX 010 000 01

ORG     0

ADC     EQU       3
HEX_RIGHT  EQU    4

MAIN:
    LOADI   &B0000000001000001
    OUT     ADC
    IN      ADC
    OUT     HEX_RIGHT
    JUMP    MAIN