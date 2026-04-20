	;; *******************************************************************
	;; Test UPI41 read and write with IBF interrupt.
	;; *******************************************************************

	CPU	8041
	INCLUDE	"pass_fail.inc"

	ORG	0
	jmp	main

	;; ISR
	ORG	3

	mov	r6, a

	in	a, dbb
	mov	r7, a

	mov	a, r6

	retr

	;; Start of test
main:

	;; test IBF empty
	jnibf	ibfempty
	jmp	fail

ibfempty:
	;; test OBF empty
	jobf	fail

	;; set up ISR
	clr	a
	mov	r7, a
	en	i

	;; signal test start
	anl	P1, #~004H

	;; request echo test
	mov	a, #001H
	out	dbb, a

waitisr:
	mov	a, r7
	jz	waitisr

	;; disable interrupt again
	dis	i

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
