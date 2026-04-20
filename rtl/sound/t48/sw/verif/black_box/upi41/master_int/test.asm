	;; *******************************************************************
	;; Test UPI41A master interrupts.
	;; *******************************************************************

	CPU	8042
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

	;; request master interrupt test
	mov	a, #004H
	out	dbb, a

	;; read input as data
step1:	jnibf	step1
	jf1	fail

	in	a, dbb
	xrl	a, #~004H
	jnz	fail

	;; set up master interrupt flags
	en	flags
	orl	p2, #00110000B

	;; read input as command
step2:	jnibf	step2
	jf1	step2_goon
	jmp	fail
step2_goon:
	in	a, dbb
	xrl	a, #004H
	jnz	fail

	;; read turnover byte as data
step3:	jnibf	step3
	jf1	fail

	in	a, dbb
	xrl	a, #0AAH
	jnz	fail

	;; disable IBF interrupt
	anl	p2, #~00100000B

	;; send step4 indicator
	mov	a, #040H
	out	dbb, a
step4:	jobf	step4

	;; set step5 indicator
	mov	a, #050H
	out	dbb,a
step5:	jobf	step5

	;; read next input as command
done:	jnibf	done
	jf1	done_goon
	jmp	done
done_goon:

	in	a, dbb
	xrl	a, #004H
	jz	pass


fail:	FAIL

pass:	PASS
