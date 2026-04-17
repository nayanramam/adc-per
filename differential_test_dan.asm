; Differential mode bare-bones loop
; CH0(+) vs CH1(-), result shown on HEX_UP
;
; Config word: &B0000000001000001
;   [1:0] = 01  -> differential mode
;   [4:2] = 000 -> CH0 positive
;   [7:5] = 001 -> CH1 negative

    ORG     0

ADC     EQU       3
HEX_RIGHT  EQU    4

MAIN:
    LOADI   &B0000000001000001
    OUT     ADC
    IN      ADC
    OUT     HEX_RIGHT
    JUMP    MAIN