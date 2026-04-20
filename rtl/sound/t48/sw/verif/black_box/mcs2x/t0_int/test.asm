	;; *******************************************************************
	;; Test MCS-22 interrupt on T0.
	;; *******************************************************************

	CPU	8022
	INCLUDE	"pass_fail.inc"

	ORG	0
	jmp	main

	ORG	3
	;; check interrupt allowed
	mov	r6, a

	mov	a, r7
	xrl	a, #099H
	jnz	fail

	mov	a, r7
	cpl	a
	mov	r7, a

	;; deactivate t0
	mov	a, #0FFH
	outl	P1, a
	mov	a, r6
	reti


main:
	;; Start of test

	;; interrupt not allowed
	mov	r7, #000H
	mov	a, #0FEH
	outl	P1, a
	;; no interrupt should happen
	nop
	nop
	nop
	mov	a, #0FFH
	outl	P1, a

	;; interrupt allowed
	mov	r7, #099H
	en	i
	mov	a, #0FEH
	outl	P1, a
irq_goon:
	;; interrupt happens here

	mov	a, r7
	xrl	a, #066H
	jnz	fail

	;; check stack
	mov	r0, #008H
	mov	a, @r0
	xrl	a, #(irq_goon & 0FFH)
	jnz	fail

	inc	r0
	mov	a, @r0
	xrl	a, #(irq_goon>>8 & 0FFH)
	jnz	fail

	jmp	pass

fail:	FAIL

pass:	PASS
