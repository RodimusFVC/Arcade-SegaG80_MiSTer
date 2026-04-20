	;; *******************************************************************
	;; Test IN A, Pp.
	;; *******************************************************************

	INCLUDE	"cpu.inc"
	INCLUDE	"pass_fail.inc"

	ORG	0

	;; Start of test
	mov	a, #055H
	outl	p1, a
	mov	a, #0AAH
	outl	p2, a

	clr	a
	in	a, p1
	xrl	a, #055H
	jnz	fail

	in	a, p2
	xrl	a, #0AAH
	jnz	fail

	mov	a, #0AAH
	outl	p1, a
	clr	a
	mov	a, #055H
	outl	p2, a

	clr	a
	in	a, p1
	xrl	a, #0AAH
	jnz	fail

	;in	a, p2
	;xrl	a, #055H
	;jnz	fail

pass:	PASS

fail:	FAIL
