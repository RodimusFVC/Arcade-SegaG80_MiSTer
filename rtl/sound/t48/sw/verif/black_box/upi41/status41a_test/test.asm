	;; *******************************************************************
	;; Test UPI41A extra status bits.
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

	;; request status41a test
	mov	a, #003H
	out	dbb, a

	;; wait for IBF=1 and F1=1
step1:	jnibf	step1
	jf1	step1_goon
	jmp	fail
step1_goon:
	in	a, dbb
	xrl	a, #003H
	jnz	fail

	mov	a, #0AAH
	mov	sts, a
	jf1	step1_f1_ok
	jmp	fail
step1_f1_ok:

	mov	a, #001H
	out	dbb, a


	;; wait for IBF=1 and F1=0
step2:	jnibf	step2
	jf1	fail

	in	a, dbb
	xrl	a, #~003H
	jnz	fail

	mov	a, #055H
	mov	sts, a
	jf1	fail

	mov	a, #002H
	out	dbb, a


	;; wait for IBF=1 and F1=1
step3:	jnibf	step3
	jf1	step3_goon
	jmp	fail
step3_goon:
	in	a, dbb
	xrl	a, #003H
	jnz	fail

	mov	a, #00AH
	mov	sts, a
	jf1	step3_f1_ok
	jmp	fail
step3_f1_ok:

	mov	a, #003H
	out	dbb, a

	;; wait for IBF=1 and F1=0
step4:	jnibf	step4
	jf1	fail

	in	a, dbb
	xrl	a, #~003H
	jnz	fail

	mov	a, #005H
	mov	sts, a
	jf1	fail

	mov	a, #004H
	out	dbb, a

	;; read next input as command
done:	jnibf	done
	jf1	done_goon
	jmp	done
done_goon:

	in	a, dbb
	xrl	a, #003H
	jz	pass


fail:	FAIL

pass:	PASS
