	;; *******************************************************************
	;; Test JNI.
	;; *******************************************************************

	INCLUDE	"cpu.inc"
	INCLUDE	"pass_fail.inc"

	ORG	0

	;; Start of test
	jni	fail

	mov	r0, #000H
poll:	jni	pass
	djnz	r0, poll

fail:	FAIL

pass:	PASS
