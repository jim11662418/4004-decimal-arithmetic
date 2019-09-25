    PAGE 0                          ; suppress page headings in ASW listing file

;--------------------------------------------------------------------------------------------------
; Firmware for the Intel 4004 Single Board Computer.
; Requires the use of a terminal emulator set for 300 bps, no parity, 7 data bits, 1 stop bit.
; 110 bps would be more period-correct but takes forever!
;----------------------------------------------------------------------------------------------------

; Tell the assembler that this source is for the Intel 4004.
            cpu 4004

; Conditional jumps syntax for ASW:
; jcn t     jump if test = 0 - positive voltage or +5VDC
; jcn tn    jump if test = 1 - negative voltage or -10VDC
; jcn c     jump if cy = 1
; jcn cn    jump if cy = 0
; jcn z     jump if accumulator = 0
; jcn zn    jump if accumulator != 0

            include "bitfuncs.inc"  ; include bit functions so that FIN can be loaded from a label (upper 4 bits of address are loped off).
            include "reg4004.inc"   ; include 4004 register definitions

CR          equ 0DH
LF          equ 0AH
ESCAPE      equ 1BH

MARK        equ 0001B

; I/O port addresses
SERIALPORT  equ 00H     ; address of the serial port. the least significant bit of port 00 is used for serial output
LEDPORT     equ 40H     ; address of the port used to control the red LEDs. "1" turns the LEDs on

;--------------------------------------------------------------------------------------------------
; Power-on-reset Entry
;--------------------------------------------------------------------------------------------------
            org 0000H

reset:      nop

            ldm 0001B
            fim P0,SERIALPORT
            src P0
            wmp                     ; set RAM serial output port high to indicate MARK

            fim P6,079H             ; 250 milliseconds delay for serial port
            fim P7,06DH
dly:        isz R12,dly
            isz R13,dly
            isz R14,dly
            isz R15,dly

reset1      jms ledsoff            
            jun subdemo

;--------------------------------------------------------------------------------------------------            
; turn off all four LEDs            
;--------------------------------------------------------------------------------------------------
ledsoff:    fim P0,LEDPORT
            src P0
            ldm 0000B
            wmp                     ; write data to RAM LED output port, set all 4 outputs low to turn off all four LEDs
            bbl 0

;--------------------------------------------------------------------------------------------------
; send the character in P1 (R2,R3) to the serial port (the least significant bit of port 0)
; in addition to P1 (R2,R3) also uses P6 (R12,R13) and P7 (R14,R15)
; NOTE: destroys P1, if needed, make sure that the character in P1 is saved elsewhere!
; (1/(5068000 MHz/7))*8 clocks/cycle = 11.05 microseconds/cycle
; for 300 bps: 1000000 microseconds / 300 bits/second / 11.05 microseconds/cycle = 302 cycles/bit
;--------------------------------------------------------------------------------------------------
printchar:  fim P7,SERIALPORT
            src P7                  ; address of serial port for I/O writes
            ldm 0
            wmp                     ; write the least significant bit of the accumulator to the serial output port
            fim P7,0B7H             ; 286 cycles
printchar1: isz R14,printchar1
            isz R15,printchar1
            nop
            ld R2                   ; get the most significant nibble of the character from R2
            ral
            stc
            rar                     ; set the most significant bit of the character (the stop bit)
            xch R2                  ; save the most significant nibble of the character in R2
            ldm 8                   ; 8 bits (7 data bits and 1 stop bit) to send
            xch R12                 ; R12 is used as the bit counter

printchar2: ld R2                   ; get the most significant nibble of the character from R2
            rar                     ; shift the least significant bit into carry
            xch R2                  ; save the result in R2 for next time
            ld R3                   ; get the least significant nibble of the character from R3
            rar                     ; shift the least significant bit into carry
            xch R3                  ; save the result in R3 for next time
            tcc                     ; transfer the carry bit to the least significant bit of the accumulator
            wmp                     ; write the least significant bit of the accumulator to the serial output port
            fim P7,087H             ; 292 cycles
printchar3: isz R14,printchar3      
            isz R15,printchar3
            isz R12,printchar2      ; do it for all 8 bits in R2,R3
            bbl 0
            
;-------------------------------------------------------------------------------
; print the 16 digit number in memory. status character 0 serves as a leading zero flag (1 means skip leading zeros)
; the digits are stored in RAM from right to left i.e least significant digit is at 10H (or 20H), most significant is at 1FH (or 2FH)
; on entry P3 contains either 10H or 20H to point to the digits to be printed.
;-------------------------------------------------------------------------------
prndigits:  ldm 0
            xch R10                 ; R10 is the loop counter (0 gives 16 times thru the loop for all 16 digits)
            ldm 0FH
            xch R7                  ; make P3 0FH (or 1FH or 2FH, etc.)
            ldm 1
            src P3
            wr0                     ; set the leading zero flag at status character 0
prndigits1: src P3
            ld R7
            jcn zn,prndigits2       ; jump if this is not the last digit
            ldm 0
            wr0                     ; since this is the last digit, clear the leading zero flag
prndigits2: rd0                     ; get the leading zero flag from status character 0
            rar                     ; rotate the flag into carry
            rdm                     ; read the digit to be printed
            jcn zn,prndigits3       ; jump if this digit is not zero
            jcn c,prndigits4        ; this digit is zero, jump if the leading zero flag is set
prndigits3: xch R3                  ; this digit is not zero OR the leading zero flag is not set. put the digit as least significant nibble into R3
            ldm 3
            xch R2                  ; most significant nibble ("3" for ASCII characters 30H-39H)
            jms printchar           ; print the ASCII code for the digit
            src P3
            ldm 0
            wr0                     ; reset the leading zero flag at status character 0

prndigits4: ld  R7                  ; least significant nibble of the pointer to the digit
            dac                     ; next digit
            xch R7
            isz R10,prndigits1      ; loop 16 times (print all 16 digits)
            bbl 0                   ; finished with all 16 digits
            
  
;-----------------------------------------------------------------------------------------
; wait for a character from the serial input port (TEST input on the 4004 CPU).
; NOTE: the serial input line is inverted by hardware before it gets to the TEST input;
; i.e. TEST=0 when the serial line is high and TEST=1 when the serial line is low,
; therefore the sense of the bit needs to be inverted in software. 
; echo the received character to the serial output port (bit 0 of port 0).
; flash the LED on bit 0 of the 2nd 4002 about 3 times per second while waiting.
; returns the 7 bit received character in P1 (R2,R3).
; in addition to P1, also uses P6 (R12,R13) and P7 (R14,R15).
; (1/(5068000 MHz/7))*8 clocks/cycle = 11.05 microseconds/cycle
; for 300 bps: 1000000 microseconds / 300 bits/second / 11.05 microseconds/cycle = 302 cycles/bit
;-----------------------------------------------------------------------------------------  
getchar:    ldm 8
            xch R12                 ; R12 holds the number of bits to receive (7 data bits and 1 stop bit); 
            fim P7,LEDPORT
            src P7
            ldm 0
            wmp                     ; turn off all LEDs
getchar2:   jcn tn,getchar4         ; jump if TEST=1 (the start bit has been detected)
            fim P1,0ADH
getchar3:   isz R2,getchar3
            jcn tn,getchar4         ; jump if TEST=1 (the start bit has been detected)
            isz R3,getchar3
            jcn tn,getchar4         ; jump if TEST=1 (the start bit has been detected)
            isz R14,getchar2
            jcn tn,getchar4         ; jump if TEST=1 (the start bit has been detected)
            isz R15,getchar2
            jcn tn,getchar4         ; jump if TEST=1 (the start bit has been detected)
            rar                     ; least significant bit into carry
            cmc                     ; complement it
            ral                     ; back into least significant bit
            wmp                     ; toggle the LED conneted to bit zero of RAM chip 1
            jun getchar2            ; go back and do it again until the start bit is detected

; the start bit has been detected...            
getchar4:   fim P7,0EBH             ; 144 cycles delay
getchar5:   isz R14,getchar5
            isz R15,getchar5        
            fim P7,SERIALPORT
            src P7                  ; define the serial port for I/O writes
            ldm 0                   ; start bit is low
            wmp                     ; echo the start bit to SERIALPORT
            fim P1,0BBH             ; 150 cycles delay
getchar6:   isz R2,getchar6
            isz R3,getchar6
            nop

; loop here until all seven bits plus stop bit have been received (302 cycles/bit)...
getchar7:   fim P7,0DBH             ; 146 cycles delay
getchar8:   isz R14,getchar8
            isz R15,getchar8        
            ldm 1                   ; "0" at the TEST input will be inverted to "1"
            jcn tn,getchar8a        ; jump if TEST input is 1
            jun getchar8b           ; skip the next two instructions since the TEST input is 0
getchar8a:  nop                     
            ldm 0                   ; "1" at the TEST input is inverted to "0"
getchar8b:  wmp                     ; echo the inverted bit back to the serial output port
            rar                     ; rotate the received bit into carry
            ld R2                   ; get the high nibble of the received character from R2
            rar                     ; rotate received bit from carry into most significant bit of R2, least significant bit of R2 into carry
            xch R2                  ; save the high nibble
            ld R3                   ; get the low nibble of the character from R3
            rar                     ; rotate the least significant bit of R2 into the most significant bit of R3
            xch R3                  ; extend register pair to make 8 bits
            fim P7,00CH             ; 138 cycles delay
getchar9:   isz R14,getchar9
            isz R15,getchar9        
            nop
            nop
            nop
            isz R12,getchar7        ; loop back until all 8 bits are read

; 7 data bits and 1 stop bit have been received, clear the the most significant bit of the most significant nibble (the stop bit)
            ld R2                   ; get the most significant nibble from R2
            ral
            clc
            rar                     ; shift the cleared carry bit back into the most significant bit of the most significant nibble
            xch R2                  ; save it back into R2
            bbl 0                   ; return to caller
  
;-----------------------------------------------------------------------------------------
;position the cursor to the start of the next line
;-----------------------------------------------------------------------------------------
newline:    fim P1,CR
            jms printchar
            fim P1,LF
            jun printchar
            
;-------------------------------------------------------------------------------
; clear ram subroutine from page 80 of the "MCS-4 Micro Computer Set Users Manual" Feb.73.
; P2 points to the memory register to be zeroed
;-------------------------------------------------------------------------------
clrram:     ldm 0
            xch R1                  ; R1 is the loop counter (0 means 16 times)
clear:      ldm 0
            src P2
            wrm                     ; write zero into RAM
            inc R5                  ; next character
            isz R1,clear            ; 16 times (zero all 16 nibbles)
            wr0                     ; clear all status characters
            wr1
            wr2
            wr3
            bbl 0
            
;-------------------------------------------------------------------------------
; get a multi-digit integer from the serial port
; upon entry, P2 points to the destination in RAM for the number 
; and R13 specifies the maximum number of digits to get
; adapted from code in the "MCS-4 Micro Computer Set Users Manual, Feb. 73".
;-------------------------------------------------------------------------------
getnumber:  jms getchar             ; return with a character from the serial port in P1 (most significant nibble in R2, least significant nibble in R3)
            ld R2                   ; get the most significant nibble of the character
            jcn zn,getnumber3       ; jump if it's not zero
            ldm 03H                 ; get the least significant nibble of the character
            sub R3                  ; compare the least significant nibble to 03H by subtraction
            jcn zn,getnumber2       ; jump if it's not control C (03H)
            jun reset1              ; control C cancels
getnumber2: ldm 0DH
            sub R3                  ; compare the least significant nibble to 0DH by subtraction
            clc
            jcn zn,getnumber3       ; jump its not carriage return (0DH)
            bbl 0                   ; return to caller with fewer than 16 digits if carriage return is entered

; move digits in RAM 1EH-10H to the next higher address 1FH-11H (or from 2EH-20H to 2FH-21H)
; the digit at 1EH is moved to 1FH, the digit at 1DH is moved to 1EH, the digit at 1CH is moved to 1DH, and so on
; moving the digits makes room for the new digit from the serial port which is contained in P1 to be stored at 10H (or 20H)
; P3 (R6,R7) is used as a pointer to the source. P4 (R8,R9) is used as a pointer to the destination.
getnumber3: ld R4                   ; get the most significant digit of the destination address from P2
            xch R6                  ; make it the most significant digit of the source address in P3
            ld R6   
            xch R8                  ; make it the most significant digit of the destiation address in P4
            ldm 0EH
            xch R7                  ; make the least significant digit of source address in P3 0EH
            ldm 0FH
            xch R9                  ; make the least significant digit of destination address in P4 0FH
            ldm 1
            xch R1                  ; loop counter (1 means 15 times thru the loop)
getnumber4: src P3                  ; source address
            rdm                     ; read digit from source
            src P4                  ; destination address
            wrm                     ; write digit to destination
            ld  R9
            dac                     ; decrement destination address
            xch R9
            clc
            ld  R7
            dac                     ; decrement source address
            xch R7
            clc
            isz R1,getnumber4       ; do all digits

            ld  R3                  ; R3 holds least significant nibble of the character received from the serial port
            src P2                  ; P2 now points to the destiation for the character
            wrm                     ; save the least significant nibble of the new digit in RAM
            isz R13,getnumber       ; go back for the next digit (16 times thru the loop for 16 digits)
            bbl 0


            org 0100H
            
;-------------------------------------------------------------------------------
; Sixteen digit decimal subtraction demo.
; The 16 digit subtrahend stored in RAM at 20H-2FH (least significant digit at 20H,
; most significant digit at 2FH) is subtracted from the 16 digit minuend stored
; in RAM at 10H-1FH (least significant digit at 10H, most significant digit at 1FH).
; The 16 digit difference replaces the minuend at 10H-1FH (least significant digit 
; at 10H, most significant digit at 1FH)
;--------------------------------------------------------------------------------
subdemo:    jms instruct
subdemo1:   jms newline             ; position carriage to beginning of next line
            jms newline
            fim P2,10H              
            jms clrram              ; clear the first register
            jms firstnum            ; prompt for the first number
            ldm 0                   ; up to 16 digits
            xch R13                 ; R13 is the digit counter
            fim P2,10H            
            jms getnumber           ; get the first number
            jms newline             ; cursor to column 1 on the next line
            fim P2,20H
            jms clrram              ; clear the second register
            jms secondnum           ; prompt for the second number
            ldm 0                   ; up to 16 digits
            xch R13                 ; R13 is the digit counter
            fim P2,20H            
            jms getnumber           ; get the second number
            jms newline             ; cursor to column 1 on the next line
            jms diff                ; print "Difference:"
            fim P0,10H              ; P1 points to the first 16 digit number
            fim P1,20H              ; P0 points to the second 16 digit number to be subtracted from the first
            jms SBRT                ; subtract, the difference goes into the first register
            src P0
            rd0                     ; sign flag at status character 0
            jcn z,subdemo2          ; zero means the result is positive
            
; the difference is negative, convert from ten's complement            
            fim P2,20H              
            jms clrram              ; clear 20H-2FH
            fim P0,20H
            fim P1,10H
            jms SBRT                ; subtract the difference from zero to convert from ten's complement
            fim P3,20H              ; P3 points to the result
            fim P1,'-'              ; minus sign
            jun subdemo3
            
subdemo2:   fim P3,1FH              ; P3 points to the first digit of the difference at RAM address 1FH
            fim P1,' '              ; no minus sign, space instead
subdemo3:   jms printchar
            jms prndigits           ; print the 16 digits of the sum
            jun subdemo1            ; go back for another pair of numbers

;-------------------------------------------------------------------------------
; Multi-digit subtraction routine taken from:
; "A Microcomputer Solution to Maneuvering Board Problems" by Kenneth Harper Kerns, June 1973
; Naval Postgraduate School Monterey, California. 

; The RAM register subtrahend pointed to by P1 are subtracted from the RAM register minuend pointed to 
; by P0. Upon exit, P0 points to the difference. Status character 0 of difference RAM register
; is set to 1 on underflow (the difference is negative).
;-------------------------------------------------------------------------------
SBRT        ldm 10
            xch R15
            clb
SUBT        src P0
            rdm
            src P1
            sbm
            jcn c,OOK
            add R15
            clc
OOK         cmc
            src P0
            wrm
            inc R3
            isz R1,SUBT
            rd0
            xch R15
            src P1
            rd0
            add R15
            src P0
            wr0
            bbl 0            
            
;-----------------------------------------------------------------------------------------
; this function is used by all the text string printing functions. if the character in P1 is zero indicating
; the end of the string, returns with accumualtor = 0. otherwise prints the character and increments
; P0 to point to the next character in the string then returns with accumulator = 1.
;-----------------------------------------------------------------------------------------
txtout:     ld R2                   ; load the most significant nibble into the accumulator
            jcn nz,txtout1          ; jump if not zero (not end of string)
            ld  R3                  ; load the least significant nibble into the accumulator
            jcn nz,txtout1          ; jump if not zero (not end of string)
            bbl 0                   ; end of text found, branch back with accumulator = 0

txtout1:    jms printchar           ; print the character in P1
            inc R1                  ; increment least significant nibble of pointer
            ld R1                   ; get the least significant nibble of the pointer into the accumulator
            jcn zn,txtout2          ; jump if zero (no overflow from the increment)
            inc R0                  ; else, increment most significant nibble of the pointer
txtout2:    bbl 1                   ; not end of text, branch back with accumulator = 1

            org 0300H

;-----------------------------------------------------------------------------------------
; print the instructions and prompts for the demo
;-----------------------------------------------------------------------------------------
firstnum:   fim P0,lo(txt2)
            jun prnloop

secondnum:  fim P0,lo(txt3)
            jun prnloop

diff:       fim P0,lo(txt4)
            jun prnloop
            
underflow:  fim P0,lo(txt5)
            jun prnloop
            

instruct:   fim P0,lo(txt1)
prnloop:    fin P1                  ; get the character pointed to by P0 into P1 (most significant nibble into R2, least significant nibble into R3)
            jms txtout              ; print the character, increment the pointer to the next character
            jcn zn,prnloop          ; go back for the next character
            bbl 0

txt1:       data CR,LF,LF
            data "Integer subtraction demo:",CR,LF,LF
            data "Enter two integers from 1 to 16 digits. If fewer than 16 digits,",CR,LF
            data "press 'Enter'. The second integer is subtracted from the first.",0
            
txt2:       data "First integer:  ",0
txt3:       data "Second integer: ",0
txt4:       data "Difference:    ",0
txt5:       data "Underflow!",0

            
