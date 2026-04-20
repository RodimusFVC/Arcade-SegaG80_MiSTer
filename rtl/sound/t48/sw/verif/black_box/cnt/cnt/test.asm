	;; *******************************************************************
	;; Test Counter.
	;; *******************************************************************

	INCLUDE	"cpu.inc"
	INCLUDE	"pass_fail.inc"

	ORG	0

	;; Start of test
	mov	a, #0FEH
	mov	t, a

	strt	cnt
	jtf	fail

	;; apply falling edge on T1
	mov	a, #0FDH
	outl	P1, a
	nop
	jtf	fail
	mov	a, t
	cpl	a
	add	a, #0FFH
	cpl	a
	jnz	fail

	;; apply rising edge on T1
	mov	a, #0FFH
	outl	P1, a
	nop
	jtf	fail

	;; apply falling edge on T1
	mov	a, #0FDH
	outl	P1, a
	nop
	jtf	goon
	jmp	fail
goon:	jtf	fail
	mov	a, t
	jnz	fail

	;; apply rising edge on T1
	mov	a, #0FFH
	outl	P1, a
	nop
	jtf	fail

	;; apply falling edge on T1
	mov	a, #0FDH
	outl	P1, a
	nop
	jtf	fail
	mov	a, t
	dec	a
	jnz	fail

	;; check inactivity of counter
	stop	tcnt
	mov	a, #0FFH
	mov	t, a

	;; apply rising edge on T1
	mov	a, #0FFH
	outl	P1, a
	nop
	jtf	fail
	;; apply falling edge on T1
	mov	a, #0FDH
	outl	P1, a
	nop
	jtf	fail
	;; apply rising edge on T1
	mov	a, #0FFH
	outl	P1, a
	nop
	jtf	fail
	;; apply falling edge on T1
	mov	a, #0FDH
	outl	P1, a
	nop
	jtf	fail

	strt	cnt
	;; apply rising edge on T1
	mov	a, #0FFH
	outl	P1, a
	nop
	jtf	fail
	;; apply falling edge on T1
	mov	a, #0FDH
	outl	P1, a
	nop
	jtf	goon2
	jmp	fail

goon2:

pass:	PASS

fail:	FAIL
