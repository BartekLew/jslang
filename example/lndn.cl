(defun errstack-point (toksym code)
   `(try
        ,code
        ((throw (+ exception ,(txt 'err-in) (print-toks ,toksym))))))

(defun lndn-vm (initial) 
  (let ((toks `((space ,(js-in-set? '_ " " "\\t" "\\n") ,(langignore))
                (block-opn (== _ "{") ,(langskip))
                (block-cls (== _ "}") ,(langbrack 'block-opn
                                         `((return (self (merge bracket code-block))))))
                (stop (== _ ";") ,(langgenop `(,(errstack-point 'before '((pass before)))
                                               (return (self after)))))
                (eql (== _ "=") ,(langgenop 
                                       `((if (or (!= before.length 1)
                                                 (!= before[0][0] word))
                                             ((throw (+ ,(txt 'name-expected) 
                                                        (print-toks before)))))
                                         (if (not (undef? vars[before[0][1]]))
                                             ((throw (+  ,(txt 'var-override)
                                                         (print-toks toks)))))
                                         (let ans (pass after))
                                         (= (@[] vars before[0][1]) ans)
                                         (return ans))))
                (lambda (== _ "->") ,(langgenop
                                       `((let al-opstack
                                            (list (@[] opstack (- brack-cls lambda))
                                                  (list literal
                                                     (fun nil (toks opstack vars)
                                                       (return toks)))))

                                         (= before (al-opstack[0][1] before al-opstack vars))

                                         (let conditions (before.filter (fun nil (x)
                                                                           (return (== x[0] literal)))))

                                         (= before (before.map (fun nil (x)
                                                                  (if (== x[0] literal)
                                                                    ((return x[1][0][1])))
                                                                  (if (!= x[0] word)
                                                                    ((throw (+ ,(txt 'wrong-par)
                                                                               x[1]))))
                                                                  (return x[1]))))

                                         (return (fun nil ()
                                                    (let args {})
                                                    (foreach (i before)
                                                       (= args[before[i]] arguments[i]))

                                                    (foreach (i conditions)
                                                       (if (not (opstack[1][1] conditions[i][1]
                                                                               (opstack.slice 1)
                                                                               (hashcat vars args)))
                                                           ((throw (+ ,(txt 'invalid-arg)
                                                                      (print-toks conditions[i][1]))))))

                                                    (return (opstack[1][1] after (opstack.slice 1)
                                                                           (hashcat vars args))))))))
                (brack-opn (== _ "(") ,(langskip))
                (brack-cls (== _ ")") ,(langbrack 'brack-opn
                                         `(,@(call-frame 'bracket
                                                '((let ans (pass bracket))))
                                           ;each additional parenthesis pair
                                           ;creates list, so that we can
                                           ;denote list of list like ((1,1)) 
                                           (if (and (== bracket.length 1)
                                                    (== bracket[0][0] literal))
                                              ((= ans (list ans))))
                                           (return (self (merge ans))))))
                (cons (== _ ",") ,(langlist))
                ,@(loop for op in '((& and) (\| or))
                        collect `(,(read-from-string (format nil "operator~A" (second op)))
                                   (== _ ,(format nil "~A" (first op)))
                                  ,(langop `((if (or (not (bool? before))
                                                     (not (bool? after)))
                                                ((return false)))
                                             (return (,(second op) before after))))))
                (test (== _ ":") ,(langop `((return (after.apply toks (list before))))))
                ,@(loop for op in '(<= >= < >)
                        collect `(,(read-from-string (format nil "operator~A" op))
                                   (== _ ,(format nil "~A" op))
                                  ,(langop `((if (or (not (number? before))
                                                     (not (number? after)))
                                                ((return false)))
                                             (return (,op before after))))))
		        (plus (== _ "+") ,(langop `((let atyp (array? before))
                                          (let btyp (array? after))
                                          (if (and atyp btyp)
                                              ((return (before.concat after))))
                                          (if (not (or atyp btyp))
                                              ((return (+ before after))))
                                          (throw (+ ,(txt 'type-conflict)
                                                    (print-toks toks))))))
                (o1 (== _ "-") ,(langop `((if (undef? before)
                                          ((return (- after)))
                                          ((return (- before after)))))
                                  :optional-before T))
                (o2 ,(js-in-set? '_ "*" "/")
                      ,(langop `((return (eval (+ before toks[i][1] after))))))
                (o3 (== _ "^")
                      ,(langop `((return (^ before after)))))
                (word (!= (_.to-upper-case) (_.to-lower-case)) ,(langcall))
                (number ,(js-range '_ "0" "9") ,(langnum))
                (code-block (undef? _) ,(langeval))
                (literal (undef? _) ,(langliteral)))))

    (defun putox (tree)
      (treesubs tree toks))
    
    (list
       (js '(fun ser (tree)
                (if (not (array? tree))
                   ((return tree))
                   ((let nodes (tree.map ser))
                    (return (+ "(" (nodes.join ",") ")")))))
           '(fun mapshape (fn shape)
               (if (and (array? shape)
                        (== shape.length 2)
                        (number? shape[0]))
                   ((return (fn shape)))
                   ((return (shape.map (fun nil (x) (return (mapshape fn x))))))))

           '(fun trace (x)
               (console.log (json x))
               (return x))

           '(fun reduceshape (fn shape initial)
              (if (undef? initial)
                 ((= initial 0)))
              (return (shape.reduce (fun nil (acc ln)
                                       (return (ln.reduce fn acc)))
                                    initial)))
           '(fun splitarr (test arr)
               (let ans [])
               (let last [])
               (foreach (i arr)
                  (if (test arr[i])
                     ((ans.push last)
                      (= last []))
                     ((last.push arr[i]))))
               (ans.push last)
               (return ans))

           (interpreter 'lndn toks
                 :tok-printer '((arr &optional idx all)
                     ; idx & all just in case it was called in map()
                     (let lastp 0)
                     (return
                        (call ((arr.map (fun nil (x)
                                           (if (== x[0] literal)
                                               ((return (ser x[1]))))

                                           (if (== x[0] code-block)
                                               ((return (+ " {"
                                                           (print-toks x[1])
                                                           " }"))))
     
                                           (if (or (and (> lastp cons) (> x[0] cons))
                                                   (and (> lastp cons) (== x[0] brack-opn))
                                                   (and (== lastp brack-cls) (> x[0] cons)))
                                               ((= lastp x[0])
                                                (return (+ " " x[1])))
                                               ((= lastp x[0])
                                                (return x[1])))))
                              join) "")))
                 :builtins `((,(txt 'fun-move) ((list form) (int-list offset 2))
                                 (if (and (== form.length 2)
                                          (not (array? form[0]))
                                          (not (array? form[1])))
                                    ((return (list (+ form[0] offset[0])
                                                   (+ form[1] offset[1])))))
                                 (return (form.map
                                               (fun nil (x)
                                                  (return ((builtins ,(txt 'fun-move)) x offset))))))

                             (,(txt 'fun-rotate) ((list form) (number angle-deg) 
                                      &optional (int-list base 2))
                                  (let angle (div (* (_pi) angle-deg) 180))
                                  (if (and (== form.length 2) (number? form[0]))
                                    ((if (undef? base)
                                        ((throw ,(txt 'rot-param3))))
                                     (if (not (and (number? form[0])
                                                   (number? form[1])))
                                        ((throw (+ ,(txt 'wrong-rot-arg)
                                                   (print-toks form)))))
                                  (let x (- form[0] base[0]))
                                  (let y (- form[1] base[1]))
                                  (return (list (+ (- (* x (cos angle))
                                                      (* y (sin angle)))
                                                   base[0])
                                                (+ (* x (sin angle))
                                                   (* y (cos angle))
                                                   base[1])))))
                               (if (undef? base)
                                 ((= base (reduceshape
                                               (fun nil (a v)
                                                  (return (list (+ a[0] v[0])
                                                                (+ a[1] v[1]))))
                                               form
                                               (list 0 0)))
                                  (let total (form.reduce (fun nil (a v)
                                                            (return (+ a v.length)))
                                                          0))
                                  (= base[0] (div base[0] total))
                                  (= base[1] (div base[1] total))))
                               (return (mapshape
                                            (fun nil (p)
                                               (let x (- p[0] base[0]))
                                               (let y (- p[1] base[1]))
                                               (return (list (+ (- (* x (cos angle))
                                                                   (* y (sin angle)))
                                                                base[0])
                                                             (+ (* x (sin angle))
                                                                (* y (cos angle))
                                                                base[1]))))
                                            form)))
                             (,(txt 'fun-list) (&rest args)
                                (return args))
                             (,(txt 'fun-number) (x)
                                (if (not (number? x))
                                    ((throw (+ ,(txt 'invalid-arg)
                                               ,(txt 'fun-number) " " x))))
                                (return true)) 
                             (,(txt 'fun-bool) (x)
                                (if (not (bool? x))
                                    ((throw (+ ,(txt 'invalid-arg)
                                               ,(txt 'fun-bool) " " x))))
                                (return true)) 
                             (,(txt 'fun-len) ((list lst))
                                (return lst.length))
                             (,(txt 'fun-count) ((function fn) (list lst))
                                (let ans 0)
                                (foreach (i lst)
                                    (if (fn lst[i])
                                      ((++ ans))))
                                (return ans))
                             (,(txt 'fun-map) ((function fn) (list lst))
                                (return (lst.map fn)))
                             (,(txt 'fun-eq) (a b)
                                (return (== a b)))
                             (,(txt 'fun-trace) (val)
                                (let stack (@[] this.vars "!callstack"))
                                (let name (@[] stack (- stack.length 1)))
                                (if (undef? (@[] this.vars "!trace" name))
                                   ((= (@[] this.vars "!trace" name) [])))
                                (((@[] this.vars "!trace" name) push) val)
                                (return val))
                             (,(txt 'fun-insert) ((list lst) (number i) x)
                                (return (((lst.slice 0 i) concat)
                                             (((list x) concat) (lst.slice i)))))
                             (,(txt 'fun-subseq) ((list lst) start &optional end)
                                (if (not end) ((= end lst.length)))
                                (return (lst.slice (- start 1) end)))
                             (,(txt 'fun-pairs) ((list lst))
                                (let acc [])
                                (for(i=0 (< i (- lst.length 1)) i++)
                                   (acc.push (list lst[i] lst[i+1])))
                                (return acc))
                             (,(txt 'fun-repeat) (initial (function f) (number count))
                                (let ans initial)
                                (for (i=0 i<count i++)
                                   (= ans (f ans)))
                                (return ans))
                             (,(txt 'fun-join) ((list x))
                                (let acc [])
                                (foreach (i x)
                                  (= acc (acc.concat x[i])))
                                (return acc))
                             (,(txt 'fun-seq) ((number n))
                                (let ans [])
                                (for (i=0 (< i n) i++)
                                   (ans.push i))
                                (return ans)))))

        (multiple-value-bind (base id)
           (draw-box :on-load   `((let writing-lock 0)
                                  (= x.lndn (lndn))
                                  (let reload-act (fun nil ()
                                          (++ writing-lock)
                                          (set-timeout
                                              (fun nil ()
                                                  (if (> (--. writing-lock) 1)
                                                     ((return 0)))
                                                  (try
                                                     ((let start-time (now))
                                                      (let vars {}) 
                                                      (let ans (x.lndn.eval x.src.value vars))
                                                      (if (undef? ans)
                                                        ((throw "...?")))
                                                      (try
                                                        ((ans.map (fun nil (stroke)
                                                                    (stroke.map (fun nil (pt)
                                                                              (if (not (and (== pt.length 2)
                                                                                            (number? pt[0])
                                                                                            (number? pt[1])))
                                                                                 ((throw "Bad point"))))))))
                                                        ((throw (+ ,(txt 'value-returned) (ser ans)))))
                                                                   
                                                      (= x.log ans)
                                                      (x.refresh)

                                                      (let traces (((keys (@[] vars "!trace")) map)
                                                                    (fun nil (x)
                                                                        (return (+ x ":\\n\\n"
                                                                                   (((@[] vars
                                                                                              "!trace"
                                                                                              x)
                                                                                     (map (fun nil (x)
                                                                                            (return
                                                                                                (json x))))
                                                                                     join) ", "))))))

                                                      (= x.status.inner-text
                                                           (+ "OK (" (- (now) start-time) "ms)\\n"
                                                                  (traces.join "\\n\\n"))))

                                                     ((= x.status.inner-text exception))))
                                                1000)))
        
                                  (let refresh-act (fun nil ()
                                                      (let ctx (x.get-context "2d"))
        
                                                      (= ctx.fill-style "#ffffff")
                                                      (ctx.fill-rect 0 0 x.width x.height)
                                
                                                      (for (i=0 (< i x.log.length) i++)
                                                         (for (j=0 (< j (- x.log[i].length 1)) j++)
                                                             (draw-line x 5 
                                                                (x.log[i][j][0] x.log[i][j][1])
                                                                (x.log[i][j+1][0] x.log[i][j+1][1]))))))
                                                       
                                  (set-timeout (fun nil ()
                                                (= x.log [])
                                                (= x.src (by-id (+ x.id "_source")))
                                                (= x.src.onpaste reload-act)
                                                (= x.src.onkeydown reload-act)
                                                (= x.src.scroll-top x.src.scroll-height)
                                                (= x.refresh refresh-act)
                                                (reload-act)
                                                (= x.status (by-id (+ x.id "_status"))))
                                              10))
                     :on-change (putox
                                `((x.log.push x.cpath)
                                  (try
                                      ((let code (x.lndn.lex x.src.value))
                                       (= code (code.filter (fun nil (x)
                                                              (return (!= x[0] space)))))
                                       (= code (splitarr (fun nil (x)
                                                              (return (== x[0] stop)))
                                                          code))
                                       (let found 0)
                                       (foreach (i code)
                                          (if (and (== code[i][0][0] word)
                                                   (== code[i][0][1] "MANUAL")
                                                   (== code[i][1][0] eql))
                                            ((= found 1)
                                             (= code[i] (code[i].concat 
                                                            (x.lndn.lex (+ "+" (ser [x.cpath]))))))))
                                       (if (not (== found 1))
                                          ((code.unshift (x.lndn.lex (+ "MANUAL="
                                                                 (ser [x.cpath]))))
                                           (= (@[] code (- code.length 1))
                                                (((@[] code (- code.length 1))
                                                     concat) (x.lndn.lex "+MANUAL")))))
        
                                       (console.log code)
                                       (= code (code.map x.lndn.print-toks))
                                       (= x.src.value (code.join ";\\n")))
                                      ((throw (+ ,(txt 'unable-ovrd-code)
                                                 exception)))))))
           (div "width:100%; text-align: center;"
              base
              (list 
                (!+ 'tag := "div" :& `("id" ,(format nil "~A_status" id)
                                     "style" "font-size:0.8em") :< (txt 'no-js))
        
                (!+ 'tag := "textarea" :& `("style" "width:100%; height: 15em;
                                                     margin-bottom:1em"
                                            "id" ,(format nil "~A_source" id))
                    :< initial)))))))
