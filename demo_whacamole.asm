; Whacamole demo
;
; Config word: &B0000000000000000
;   [1:0] = 00  -> single-ended mode
;   [4:2] = 000 -> CH0

    ORG     0

SWITCHES   EQU    0
TIMER      EQU    2
ADC        EQU    3
HEX_RIGHT  EQU    4
HEX_LEFT   EQU    5

; Initialize timer, display, adc config
INIT: 
    LOADI   0
    OUT     ADC
    OUT     HEX_RIGHT
    OUT     HEX_LEFT
; Wait for any switch to be high
LOOP1:
    IN      SWITCHES
    JNZ     MAIN
    JUMP    LOOP1
	OUT     TIMER
; Run timer until switches are all low again, using timer value as random number to match
MAIN:
    IN      SWITCHES
    JNZ     MAIN
    IN      TIMER
	SHIFT   6
	ADDI    7
	AND     MASK
    OUT     HEX_RIGHT
    STORE   MATCH_VALUE
    OUT     TIMER
; Check that ADC value is within += 50 of match value
LOOP2:
    IN      ADC
    SUB     MATCH_VALUE
    ADDI    -50
    JPOS    LOOP2
    ADDI    100
    JNEG    LOOP2
    JUMP    SUCCESS
; If successful, increment score, reset timer, and start over
SUCCESS:
    IN      TIMER
    ADD     TIME_TRACKER
    STORE   TIME_TRACKER
    SUB     END_TIME
    JPOS    GAME_OVER
    LOAD    SCORE
    ADDI    1
    OUT     HEX_LEFT
    STORE   SCORE
    LOADI   0
    OUT     HEX_RIGHT
    OUT     TIMER
    JUMP    LOOP1
; If time is up, display score and end game
GAME_OVER:
    LOAD    WIN
    OUT     HEX_RIGHT
    JUMP    GAME_OVER

; Variables
SCORE:   DW 0
MATCH_VALUE: DW 0
TIME_TRACKER: DW 0
END_TIME: DW 81 ; 8.1 seconds (KOBE)
WIN: DW &HBEEF

; Constants
MASK: DW &H0FFF