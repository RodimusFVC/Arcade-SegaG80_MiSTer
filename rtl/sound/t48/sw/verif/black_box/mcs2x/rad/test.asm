	;; *******************************************************************
	;; Test MCS-22 RAD.
	;; *******************************************************************

	CPU	8022
	INCLUDE	"pass_fail.inc"

	ORG	0

	;; Start of test
	sel	an0
	nop
	nop
	nop
	rad
	xrl	a, #069H
	jnz	fail

	sel	an1
	nop
	nop
	nop
	rad
	xrl	a, #096H
	jnz	fail

	jmp	pass

fail:	FAIL

pass:	PASS
