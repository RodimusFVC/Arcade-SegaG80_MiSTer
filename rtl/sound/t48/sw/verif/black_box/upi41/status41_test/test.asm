	;; *******************************************************************
	;; Test UPI41 status bits.
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

	;; request status41 test
	mov	a, #002H
	out	dbb, a

	;; wait for IBF=1 and F1=1
step1:	jnibf	step1
	jf1	step1_goon
	jmp	step1
step1_goon:

	;; wait for IBF=1 and F1=0
step2:	jnibf	step2
	jf1	step2


	;; wait for IBF=1 and F1=1
step3:	jnibf	step3
	jf1	step3_goon
	jmp	step3
step3_goon:
	;; read IBF and complement F0
	in	a, dbb
	xrl	a, #~002H
	jnz	fail
	cpl	f0

	;; wait for IBF=1 and F1=0
step4:	jnibf	step4
	jf1	step4
	;; read IBF and complement F0
	in	a, dbb
	xrl	a, #~002H
	jnz	fail
	cpl	f0

	;; wait for IBF=1 and F1=1
step5:	jnibf	step5
	jf1	step5_goon
	jmp	step5
step5_goon:
	;; read IBF and complement F0
	in	a, dbb
	xrl	a, #002H
	jnz	fail
	cpl	f0
	;; load OBF
	mov	a, #099H
	out	dbb, a

	;; wait for IBF=1 and F1=0
step6:	jnibf	step6
	jf1	step6
	;; read IBF and complement F0
	in	a, dbb
	xrl	a, #002H
	jnz	fail
	cpl	f0
	;; complement F1
	cpl	f1
	;; load OBF
	mov	a, #066H
	out	dbb, a

	;; read next input as command
done:	jnibf	done
	jf1	done_goon
	jmp	done
done_goon:

	in	a, dbb
	xrl	a, #002H
	jz	pass


fail:	FAIL

pass:	PASS
