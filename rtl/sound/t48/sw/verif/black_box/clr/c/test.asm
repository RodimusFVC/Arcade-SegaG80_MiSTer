	;; *******************************************************************
	;; Test CLR C.
	;; *******************************************************************

	INCLUDE	"cpu.inc"
	INCLUDE	"pass_fail.inc"

	ORG	0

	;; Start of test
	clr	c	; C bit is not affected by reset

	jc	fail
	cpl	c
	jnc	fail
	clr	c
	jc	fail
	clr	c
	jc	fail

	mov	a, #0FFH
	add	a, #001H
	jnc	fail
	clr	c
	jc	fail

pass:	PASS

fail:	FAIL
