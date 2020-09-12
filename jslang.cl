(defun tokdef (test)
  (if (and (= (length test) 3)
           (eql (first test) '==)
           (eql (second test) '_))
     (let* ((val (third test))
            (valen (length val)))
        `(fun nil (src)
            (if (== (src.slice 0 ,valen) ,val)
                ((return ,valen))
                ((return 0)))))
     `(fun nil ("src")
         (for (i=0 (< i src.length) i++)
              (let _ src[i])
              (if (not ,test) ((return i))))
            (return src.length))))

(defun lexer (toks &key name)
  `(fun ,name ("src")
        (let tok-defs (list ,@(loop for tok in toks
                                    collect (tokdef (second tok)))))
        (let acc [])
        (while (> src.length 0)
           (let found 0)
           (foreach (tok tok-defs)
              (let len (tok-defs[tok] src))
              (if (> len 0)
                ((acc.push (list tok (src.slice 0 len)))
                 (= src (src.slice len))
                 (= found 1)
                 (break))))
           (if (== found 0) ((throw (+ ,(txt 'unknown-element)
                                        (src.slice 0 10))))))
        (return acc)))

(defun opstack (toks)
    `(list ,@(loop for tok in toks
                   for i from 0
                   collect `(list ,i ,(treesubs (third tok) toks)))))

(defun interpreter (name symtab &key builtins tok-printer)
  `(fun ,name ()
      (let vm {})
      (defn print-toks 
          ,@(if tok-printer (treesubs tok-printer symtab)
               `((toks) (return (call ((toks.map (fun nil (x) (return x[1])))
                               join) " ")))))

      (= vm.print-toks print-toks)
  
      ,@(if builtins `((let builtins {})
                       ,@(loop for f in builtins
                               collect `(defn (builtins ,(first f)) ,@(rest f)))))
  
      (= vm.lex ,(lexer symtab))
      (= vm.opstack ,(opstack symtab))
      (= vm.eval (fun nil (code vars)
                    (if (undef? vars)
                      ((= vars {})))
  
                    (let toks (vm.lex code))
                    (= vars (hashcat builtins vars))
                    (= (@[] vars "!opstack") vm.opstack)
  
                    (return (vm.opstack[0][1] toks vm.opstack vars))))
      (return vm)))
    
(defun js-range (x a b)
    `(and (>= ,x ,a) (<= ,x ,b)))

(defun js-in-set? (x &rest options)
    `(or ,@(loop for o in options
                 collect `(== ,x ,o))))

(defun treesubs (tree toks)
  (loop for x in tree
        collect (let ((n (position x (mapcar #'first toks) :test #'equalp)))
                  (if n n
                    (if (listp+ x) (treesubs x toks) x)))))

(defun langskip ()
  `(fun nil (toks opstack vars)
      (return (opstack[1][1] toks (opstack.slice 1) vars))))

(defun langignore ()
  `(fun nil (toks opstack vars)
      (return (opstack[1][1] (toks.filter (fun nil (x)
                                            (return (!= x[0] opstack[0][0]))))
                             (opstack.slice 1)
                             vars))))

(defun langliteral ()
  `(fun nil (toks opstack vars)
     (if (> toks.length 1)
        ((throw (+ ,(txt 'too-many-args)
                   (print-toks toks)))))
     (return toks[0][1])))

(defun langeval ()
  `(fun nil (toks opstack vars)
     (if (not (== toks[0][0] opstack[0][0]))
       ((return (opstack[1][1] toks (opstack.slice 1) vars))))
     (if (!= toks.length 1)
       ((throw (+ ,(txt 'too-many-args)
                  (print-toks toks)))))
     (let stack (@[] vars "!opstack"))
     (return (stack[0][1] toks[0][1] stack vars))))

(defun langnum ()
  `(fun nil (toks opstack vars)
     (if (== toks[0][0] opstack[0][0])
       ((if (!= toks.length 1)
           ((throw (+ ,(txt 'too-many-args)
                      (print-toks toks)))))
        (return (parse-int toks[0][1]))))
     (return (opstack[1][1] toks (opstack.slice 1) vars))))

(defun langvar ()
  `(fun nil (toks opstack vars)
      (if (!= toks.length 1)
         ((throw (+ ,(txt 'too-many-args)
                    (call ((toks.map (fun nil (x) (return x[1])))
                           join))))))
      (if (== toks[0][0] opstack[0][0])
        ((if (undef? vars[toks[0][1]])
            ((throw (+ ,(txt 'var-undefined) toks[0][1]))))
         (return vars[toks[0][1]]))
        ((return (opstack[1][1] toks (opstack.slice 1) vars))))))

(defun langlist ()
  `(fun nil (toks opstack vars)
      (let pass (fun nil (toks)
                   (if (> toks.length 0)
                     ((return (opstack[1][1] toks (opstack.slice 1) vars))))))
      (let acc [])
      (let nexte [])
      (foreach (i toks)
	(if (== toks[i][0] opstack[0][0])
	  ((acc.push nexte)
	   (= nexte []))
	  ((nexte.push toks[i]))))
      (if (> acc.length 0)
        ((acc.push nexte)
         (return (acc.map pass))))

      (return (opstack[1][1] toks (opstack.slice 1) vars))))

(defun langcall ()
  `(fun nil (toks opstack vars)
     (let self (fun nil (tok)
                  (if (array? tok)
                    ((return (opstack[0][1] (list tok) opstack vars))))))
     (if (== toks[0][0] opstack[0][0])
        ((let varval vars[toks[0][1]])
         (if (undef? varval)
            ((throw (+ ,(txt 'var-undefined) 
                       toks[0][1]))))
         (if (== toks.length 1)
            ((return varval)))
	 (if (function? varval)
            ((try
                ((return (varval.apply varval (((toks.slice 1)
                                           map) self))))
                ((throw (+ ,(txt 'err-in-call)
                           (print-toks toks)
                           ,(txt 'err-in-call2)
                           exception))))))
	 (if (array? varval)
	   ((try
	      ((return (((toks.slice 1) reduce) 
			    (fun nil (a v)
			       (return (@[] a (- (self v) 1))))
			    varval)))
	      (throw (+ ,(txt 'wrong-arr-argv) (print-toks toks)))))
	    ((throw (+ ,(txt 'wrong-expr)
		       (print-toks toks)))))))

        (return (opstack[1][1] toks (opstack.slice 1) vars))))

(defun langgenop (action &key else reverse)
  (let ((locals `((let before (toks.slice 0 i))
                  (let after (toks.slice (+ i 1))))))

     `(fun nil (toks opstack vars)
         (let opclass opstack[0][0])
         (let pass (fun nil (toks)
                     (if (> toks.length 0)
                       ((return (opstack[1][1] toks (opstack.slice 1) vars))))))
         (let self (fun nil (toks)
                     (if (> toks.length 0)
                       ((return (opstack[0][1] toks opstack vars))))))
   
         ,(if reverse
              `(for ((=. i (- toks.length 1)) (>= i 0) (--. i))
                   (if (== opclass toks[i][0])
                      (,@locals
                       ,@action)))
              `(foreach (istr toks)
                  (if (== opclass toks[istr][0])
                     ((let i (parse-int istr))
                      ,@locals
                      ,@action))))
   
         ,@else
   
         (return (opstack[1][1] toks (opstack.slice 1) vars)))))

(defun langop (action &key optional-before optional-after)
    (langgenop   `((= before (self before))
               (= after (pass after))

               ,@(if (not optional-before)
                    `((if (undef? before)
                        ((throw (+ ,(txt 'val-expected-bfr)
                                   toks[i][1] ,(txt 've-in) 
                                   (print-toks toks)))))))
               ,@(if (not optional-after)
                    `((if (undef? after)
                        ((throw (+ ,(txt 'val-expected-aftr)
                                   toks[i][1] "' w: "
                                   (print-toks toks)))))))
               ,@action)
            :reverse T))

(defun langbrack (opener &optional (action '((return (self (merge (pass bracket)))))))
  (langgenop 
    `((let split-on-last
           (fun nil (toks cls)
              (for ((=. i (- toks.length 1)) i>=0 (--. i))
                 (if (== toks[i][0] cls)
                    ((return (list (toks.slice 0 i)
                                   (toks.slice (+ i 1)))))))))
      (let bracket (split-on-last before ,opener))
      (let merge (fun nil (value type)
                    (if (undef? type)
                        ((= type literal)))
                    (return (before.concat
                                (list (list type value))
                                after))))
      (if (not (undef? bracket))
         ((= before bracket[0])
          (= bracket bracket[1])
          ,@action)
         ((throw (+ ,(txt 'missing-brack-opn)
                    (print-toks (toks.slice 0 (+ i 1))))))))
     :else `((toks.map (fun nil (x)
                         (if (== x[0] ,opener)
                             ((throw (+ ,(txt 'missing-brack-cls)
                                         (print-toks
                                            (toks.slice (+ i 0))))))))))))
