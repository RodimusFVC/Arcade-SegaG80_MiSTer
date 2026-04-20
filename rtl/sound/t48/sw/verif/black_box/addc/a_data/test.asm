	;; *******************************************************************
	;; Test ADDC A, data.
	;; *******************************************************************

	INCLUDE	"cpu.inc"
	INCLUDE	"pass_fail.inc"

	ORG	0

	;; Start of test
	clr	c	; C bit is not affected by reset
	mov	a, #000H

	addc	a, #055H
	jc	fail
	addc	a, #0ABH
	jnz	fail
	jnc	fail

	addc	a, #000H
	jc	fail
	addc	a, #0FFH
	jnz	fail
	jnc	fail

pass:	PASS

fail:	FAIL
