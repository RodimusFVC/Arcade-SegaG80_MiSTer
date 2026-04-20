	;; *******************************************************************
	;; Test JNC instruction.
	;; *******************************************************************

	INCLUDE	"cpu.inc"
	INCLUDE	"pass_fail.inc"

	ORG	0

	;; Start of test
	clr	c	; C bit is not affected by reset

	jnc	ok_1
	jmp	fail

ok_1:	mov	a, #0FFH
	add	a, #001H
	jnc	fail

pass:	PASS

fail:	FAIL
