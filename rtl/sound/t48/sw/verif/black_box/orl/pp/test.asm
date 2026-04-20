	;; *******************************************************************
	;; Test ORL Pp, data.
	;; *******************************************************************

	INCLUDE	"cpu.inc"
	INCLUDE	"pass_fail.inc"

	ORG	0

	;; Start of test
	mov	a, #000H
	outl	p1, a
	outl	p2, a

	cpl	a
	in	a, p1
	jnz	fail

	cpl	a
	in	a, p2
	jnz	fail

	orl	P1, #0AAH
	jnz	fail
	orl	P2, #055H
	jnz	fail

	in	a, p1
	add	a, #056H
	jnz	fail

	in	a, p2
	add	a, #0ABH
	jnz	fail

pass:	PASS

fail:	FAIL
