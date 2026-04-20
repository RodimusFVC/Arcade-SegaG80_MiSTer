	;; *******************************************************************
	;; Test UPI41 read and write.
	;; *******************************************************************

	CPU	8041
	INCLUDE	"pass_fail.inc"

	ORG	0

	;; Start of test

	;; test IBF empty
	jnibf	ibfempty
	jmp	fail

ibfempty:
	;; test OBF empty
	jobf	fail

	;; signal test start
	anl	P1, #~004H

	;; request echo test
	mov	a, #001H
	out	dbb, a

	;; read input as data
inp1:	jnibf	inp1
	jf1	fail

	in	a, dbb

	;; invert and output
	cpl	a
	out	dbb, a

out1:	jobf	out1

	;; read next input as command
inp2:	jnibf	inp2
	jf1	inp2_2
	jmp	fail

inp2_2:	in	a, dbb
	xrl	a, #001H
	jz	pass


fail:	FAIL

pass:	PASS
