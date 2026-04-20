	;; *******************************************************************
	;; Test J(N)T0 addr.
	;; *******************************************************************

	INCLUDE	"cpu.inc"
	INCLUDE	"pass_fail.inc"

	ORG	0

	;; Start of test
	jnt0	fail
	mov	a, #0FEH
	outl	P1, a
	jt0	fail
	mov	a, #0FFH
	outl	P1, a
	jt0	pass

fail:	FAIL

pass:	PASS
