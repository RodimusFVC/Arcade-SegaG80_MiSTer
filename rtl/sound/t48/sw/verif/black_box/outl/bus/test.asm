	;; *******************************************************************
	;; Test OUTL BUS, A
	;; *******************************************************************

	INCLUDE	"cpu.inc"
	INCLUDE	"pass_fail.inc"

	ORG	0

	;; Start of test
	mov	a, #055H
	outl	bus, a
	cpl	a
	outl	bus, a

pass:	PASS

fail:	FAIL
