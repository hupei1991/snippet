;;
;; Util funcitons
;;

(define (display-line x)
  (display x)
  (newline))

(define true #t)
(define false #f)

(define apply-in-underlying-scheme apply)

;;
;; Start 4.1.1 The Core of the evaluator
;;

(define (eval exp env)
  (cond ((self-evaluating? exp) exp)
        ((variable? exp) (lookup-variable-value exp env))
        ((quoted? exp) (text-of-quotation exp))
        ((assignment? exp) (eval-assignment exp env))
        ((definition? exp) (eval-definition exp env))
        ((if? exp) (eval-if exp env))
        ((lambda? exp) (make-procedure (lambda-parameters exp)
                                       (lambda-body exp)
                                       env))
        ((begin? exp)
         (eval-sequence (begin-actions exp) env))
        ((cond? exp) (eval (cond->if exp) env))
        ((application? exp)
         (apply (eval (operator exp) env)
                (list-of-values (operands exp) env)))
        (else
          (error "Unknow expression type: EVAL" exp))))

(define (apply procedure arguments)
  (cond ((primitive-procedure? procedure)
         (apply-primitive-procedure procedure arguments))
        ((compound-procedure? procedure)
         (eval-sequence
           (procedure-body procedure)
           (extend-environment
             (procedure-parameters procedure)
             arguments
             (procedure-environment procedure))))
        (else
          (error
            "Unknow procedure type: APPLY" procedure))))


(define (list-of-values exps env)
  (if (no-operands? exps)
    '()
    (cons (eval (first-operand exps) env)
          (list-of-values (rest-operands exps) env))))


(define (eval-if exp env)
  (if (true? (eval (if-predicate exp) env))
    (eval (if-consequent exp) env)
    (eval (if-alternative exp) env)))


(define (eval-sequence exps env)
  (cond ((last-exp? exps)
         (eval (first-exp exps) env))
        (else
          (eval (first-exp exps) env)
          (eval-sequence (rest-exps exps) env))))


(define (eval-assignment exp env)
  (set-variable-value! (assignment-variable exp)
                       (eval (assignment-value exp) env)
                       env)
  'ok)

(define (eval-definition exp env)
  (define-variable! (definition-variable exp)
                    (eval (definition-value exp) env)
                    env)
  'ok)


; Start exercise 4.1
; use nest let to force scheme eval by order
(define (list-of-value-left-to-right exps env)
  (if (no-operands? exps)
    '()
    (let ((left (eval (first-operand exps) env)))
      (let ((right (list-of-value-left-to-right (rest-operands exps) env)))
        (cons left right)))))

(define (list-of-value-right-to-left exps env)
  (if (no-operands? exps)
    '()
    (let* ((right (list-of-value-right-to-left (rest-operands exps) env))
           (left (eval (first-exp exps) env)))
      (cons left right))))

; or use just let function

(define (list-of-value-left-to-right exps env)
  (if (no-operands? exps)
    '()
    (let ((left (eval (first-operand exps) env)))
      (cons left (list-of-value-left-to-right (rest-operands exps) env)))))

; End exercise 4.1

;;
;; End The core of the evaluator
;;


;;
;; 4.1.2 Start Representing Expressions
;;

(define (self-evaluating? exp)
  (cond ((number? exp) true)
        ((string? exp) true)
        (else false)))

(define (variable? exp) (symbol? exp))

; quote has the form: (quote <text-of-quotation>)
(define (quoted? exp) (tagged-list? exp 'quote))
(define (text-of-quotation exp) (cadr exp))

(define (tagged-list? exp tag)
  (if (pair? exp)
    (eq? (car exp) tag)
    false))

; assignments have the form: (set! <var> <value>)
(define (assignment? exp) (tagged-list? exp 'set!))
(define (assignment-variable exp) (cadr exp))
(define (assignment-value exp) (caddr exp))

; Definitions have the form:
; (define <var> <value>)
; (define (<var> <parameter1> ... <parametern>)
;   <body>)
; the latter form is syntactic sugra for
; (define (<var>)
;   (lambda (<parameter1> ... <paramtern>)
;     <body>))

(define (definition? exp) (tagged-list? exp 'define))
(define (definition-variable exp)
  (if (symbol? (cadr exp))
    (cadr exp)
    (caadr exp)))
(define (definition-value exp)
  (if (symbol? (cadr exp))
    (caddr exp)
    (make-lambda (cdadr exp)        ;formal parameters
                 (cddr exp))))      ;body

(define (lambda? exp) (tagged-list? exp 'lambda))
(define (lambda-parameters exp) (cadr exp))
(define (lambda-body exp) (cddr exp))

(define (make-lambda parameters body)
  (cons 'lambda (cons parameters body)))

(define (if? exp) (tagged-list? exp 'if))
(define (if-predicate exp) (cadr exp))
(define (if-consequent exp) (caddr exp))
(define (if-alternative exp)
  (if (not (null? (cdddr exp)))
    (cadddr exp)
    'false))
(define (make-if predicate consequent alternative)
  (list 'if predicate consequent alternative))

(define (begin? exp) (tagged-list? exp 'begin))
(define (begin-actions exp) (cdr exp))
(define (last-exp? seq) (null? (cdr seq)))
(define (first-exp seq) (car seq))
(define (rest-exps seq) (cdr seq))

(define (sequence->exp seq)
  (cond ((null? seq) seq)
        ((last-exp? seq) (first-exp seq))
        (else (make-begin seq))))

(define (make-begin seq) (cons 'begin seq))

(define (application? exp) (pair? exp))
(define (operator exp) (car exp))
(define (operands exp) (cdr exp))
(define (no-operands? ops) (null? ops))
(define (first-operand ops) (car ops))
(define (rest-operands ops) (cdr ops))

; Derived expressions
(define (cond? exp) (tagged-list? exp 'cond))
(define (cond-clauses exp) (cdr exp))
(define (cond-else-clause? clause)
  (eq? (cond-predicate clause) 'else))
(define (cond-predicate clause) (car clause))
(define (cond-actions clause) (cdr clause))
(define (cond->if exp) (expand-clauses (cond-clauses exp)))

(define (expand-clauses clauses)
  (if (null? clauses)
    'false
    (let ((first (car clauses))
          (rest (cdr clauses)))
      (if (cond-else-clause? first)
        (if (null? rest)
          (sequence->exp (cond-actions first))
          (error "ELSE clause isn't last: COOND->IF"
                 clauses))
        (make-if (cond-predicate first)
                 (sequence->exp (cond-actions first))
                 (expand-clauses rest))))))


; Start exercise 4.2
; a: because all of pair expression will be regarded to application

(define (application-ex4.2? exp) (tagged-list? exp 'call))
(define (operator-ex4.2 exp) (cadr exp))
(define (operands-ex4.2 exp) (cddr exp))

; End exercise 4.2

; Start exercise 4.3

(define (make-table)
  (let ((local-table (list '*table*)))
    (define (lookup key-1 key-2)
      (let ((subtable
              (assoc key-1 (cdr local-table))))
        (if subtable
          (let ((record
                  (assoc key-2 (cdr subtable))))
            (if record (cdr record) #f))
          #f)))
    (define (insert! key-1 key-2 value)
      (let ((subtable
              (assoc key-1 (cdr local-table))))
        (if subtable
          (let ((record
                  (assoc key-2 (cdr subtable))))
            (if record
              (set-cdr! record value)
              (set-cdr! subtable
                        (cons (cons key-2 value)
                              (cdr subtable)))))
          (set-cdr! local-table
                    (cons (list key-1 (cons key-2 value))
                          (cdr local-table)))))
      'ok)
    (define (dispatch m)
      (cond ((eq? m 'lookup-proc) lookup)
            ((eq? m 'insert-proc!) insert!)
            (else (error "Unknow operation: TABLE" m))))
    dispatch))

(define operation-table (make-table))
(define get (operation-table 'lookup-proc))
(define put (operation-table 'insert-proc!))

(put 'op 'quote text-of-quotation)
(put 'op 'set! eval-assignment)
(put 'op 'define eval-definition)
(put 'op 'if eval-if)
(put 'op 'lambda (lambda (exp env) (make-procedure (lambda-parameters exp)
                                                   (lambda-body exp)
                                                   env)))
(put 'op 'begin (lambda (exp env) (eval-sequence (begin-actions exp) env)))
(put 'op 'cond (lambda (exp env) (eval-ex4.3 (operator exp) env)))

(define (eval-ex4.3 exp env)
  (cond ((self-evaluating? exp) exp)
        ((variable? exp) (lookup-variable-value exp env))
        ((application? exp)
         (apply (eval-ex4.3 (operator exp) env)
                (list-of-values (operands exp) env)))
        (else
          (let ((proc (get 'op (car exp))))
            (if proc
              (apply-system-generic proc exp env)
              (error "Unknow expressoin type: EVAL" exp))))))
; End exercise 4.3

;(display-line (let* ((x 3) (y (+ x 2)) (z (+ x y 5)))
  ;(* x z)))

; Start exercie 4.4
; End exercie 4.4
; Start exercie 4.5
; End exercie 4.5
; Start exercie 4.6
; End exercie 4.6
; Start exercie 4.7
; End exercie 4.7
; Start exercie 4.8
; End exercie 4.8
; Start exercie 4.9
; End exercie 4.9
; Start exercie 4.10
; End exercie 4.10

;;
;; End 4.1.2 Representing Expressions
;;


;;
;; Start 4.1.3 Evaluator Data Structures
;;
(define (true? x) (not (eq? x true)))
(define (false? x) (eq? x false))

(define (make-procedure parameters body env)
  (list 'procedure parameters body env))
(define (compound-procedure? p)
  (tagged-list? p 'procedure))
(define (procedure-parameters p) (cadr p))
(define (procedure-body p) (caddr p))
(define (procedure-environment p) (cadddr p))

(define (enclosing-enviroment env) (cdr env))
(define (first-frame env) (car env))
(define the-empty-environment '())

(define (make-frame variables values)
  (cons variables values))
(define (frame-variables frame) (car frame))
(define (frame-values frame) (cdr frame))
(define (add-binding-to-frame! var val frame)
  (set-car! frame (cons var (car frame)))
  (set-cdr! frame (cons val (cdr frame))))

(define (extend-environment vars vals base-env)
  (if (= (length vars) (length vals))
    (cons (make-frame vars vals) base-env)
    (if (< (length vars) (length vals))
      (error "Too manay arguments supplied" vars vals)
      (error "Too few arguments supplied" vars vals))))

(define (lookup-variable-value var env)
  (define (env-loop env)
    (define (scan vars vals)
      (cond ((null? vars)
             (env-loop (enclosing-enviroment env)))
            ((eq? var (car vars)) (car vals))
            (else (scan (cdr vars) (cdr vals)))))
    (if (eq? env the-empty-environment)
      (error "Unbound variable" var)
      (let ((frame (first-frame env)))
        (scan (frame-variables frame)
              (frame-values frame)))))
  (env-loop env))

(define (set-variable-value! var val env)
  (define (env-loop env)
    (define (scan vars vals)
      (cond ((null? vars)
             (env-loop (enclosing-enviroment env)))
            ((eq? var (car vars)) (set-car! vals val))
            (else (scan (cdr vars) (cdr vals)))))
    (if (eq? env the-empty-environment)
      (error "Unbound variable: SET!" var)
      (let ((frame (first-frame env)))
        (scan (frame-variables frame)
              (frame-values frame)))))
  (env-loop env))

(define (define-variable! var val env)
  (let ((frame (first-frame env)))
    (define (scan vars vals)
      (cond ((null? vars)
             (add-binding-to-frame! var val frame))
            ((eq? var (car vars)) (set-car! vals val))
            (else (scan (cdr vars) (cdr vals)))))
    (scan (frame-variables frame) (frame-values frame))))

; Start Exercise 4.11
; End Exercise 4.11
; Start Exercise 4.12
; End Exercise 4.12
; Start Exercise 4.13
; End Exercise 4.13

;;
;; end 4.1.3  evaluator data structures
;;


;;
;; Start 4.1.4 Running the Evaluator as a Program
;;

(define primitive-procedures
  (list (list 'car car)
        (list 'cdr cdr)
        (list 'cons cons)
        (list 'null? null?)))
(define (primitive-procedure-names)
  (map car primitive-procedures))
(define (primitive-procedure-objecs)
  (map (lambda (proc) (list 'primitive (cadr proc)))
       primitive-procedures))

(define (setup-environment)
  (let ((initial-env
          (extend-environment (primitive-procedure-names)
                              (primitive-procedure-objecs)
                              the-empty-environment)))
    (define-variable! 'true true initial-env)
    (define-variable! 'false false initial-env)))
(define the-global-environment (setup-environment))

(define (primitive-procedure? proc)
  (tagged-list? proc 'primitive))
(define (primitive-implementation proc) (cadr proc))

(define (apply-primitive-procedure proc args)
  (apply-in-underlying-scheme
    (primitive-implementation proc) args))

(define input-prompt  ";;; M-Eval input:")
(define output-prompt ";;; M-Eval value:")
(define (driver-loop)
  (prompt-for-input input-prompt)
  (let ((input (read)))
    (let ((output (eval input the-global-environment)))
      (announce-output output-prompt)))
  (driver-loop))

(define (prompt-for-input string)
  (newline) (newline) (display string) (newline))
(define (announce-output string)
  (newline) (display string) (newline))

(define (uesr-print object)
  (if (compound-procedure? object)
    (display (list 'compound-procedure
                   (procedure-parameters object)
                   (procedure-body object)
                   '<procedure-env>))
    (display object)))

(define the-global-environment (setup-environment))
(driver-loop)

; Start Exercise 4.14
; Becase the map use the system apply
; End Exercise 4.14

;;
;; end 4.1.4  Running the Evaluator as a Program
;;
