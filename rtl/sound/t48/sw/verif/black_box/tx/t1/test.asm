	;; *******************************************************************
	;; Test J(N)T1 addr.
	;; *******************************************************************

	INCLUDE	"cpu.inc"
	INCLUDE	"pass_fail.inc"

	ORG	0

	;; Start of test
	jnt1	fail
	mov	a, #0FDH
	outl	P1, a
	jt1	fail
	mov	a, #0FFH
	outl	P1, a
	jt1	pass

fail:	FAIL

pass:	PASS
