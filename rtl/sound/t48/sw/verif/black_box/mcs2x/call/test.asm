	;; *******************************************************************
	;; Test MCS2x CALL with simple program.
	;; *******************************************************************

	CPU	8021
	INCLUDE	"pass_fail.inc"

	ORG	0

	;; Start of test
	mov	r0, #008H
	call	recursive

call1:

ok_1:
	;; check stack contents
	mov	r0, #008H
	mov	a, @r0
	xrl	a, #(call1-1) & 0FFH
	jnz	fail

	inc	r0
	mov	a, @r0
	xrl	a, #((call1-1) >> 8) & 0FFH
	jnz	fail

	inc	r0
	mov	a, @r0
	xrl	a, #(rec_end-1) & 0FFH
	jnz	fail

	inc	r0
	mov	a, @r0
	xrl	a, #((rec_end-1) >> 8) & 0FFH
	jnz	fail


pass:	PASS

fail:	FAIL



	ORG	0156H
recursive:
	djnz	r0, rec_goon
	ret
rec_goon:
	call	recursive
rec_end:
	ret
