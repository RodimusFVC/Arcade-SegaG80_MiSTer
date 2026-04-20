	;; *******************************************************************
	;; Test CPL C.
	;; *******************************************************************

	INCLUDE	"cpu.inc"
	INCLUDE	"pass_fail.inc"

	ORG	0

	;; Start of test
	clr	c	; C bit is not affected by reset

	jc	fail

	cpl	c
	jnc	fail

	mov	a, #0FEH
	add	a, #001H
	jc	fail
	cpl	c
	jnc	fail

	add	a, #001H
	jnc	fail
	cpl	c
	jc	fail

pass:	PASS

fail:	FAIL
