	;; *******************************************************************
	;; Test MCS2x P0.
	;; *******************************************************************

	CPU	8021
	INCLUDE	"pass_fail.inc"

	ORG	0

	;; Start of test
	mov	a, #055H
	outl	p0, a
	clr	a
	in	a, p0
	xrl	a, #055H
	jnz	fail

	mov	a, #0AAH
	outl	p0, a
	clr	a
	in	a, p0
	xrl	a, #0AAH
	jnz	fail

	jmp	pass

fail:	FAIL

pass:	PASS
