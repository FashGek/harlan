(library
  (harlan middle remove-nested-kernels)
  (export remove-nested-kernels)
  (import
   (rnrs)
   (except (elegant-weapons helpers) ident?)
   (harlan helpers)
   (cKanren mk))

(define-match remove-nested-kernels
  ((module ,[Decl -> decl*] ...)
   `(module . ,decl*)))

(define-match Decl
  ((fn ,name ,args ,type ,[(Stmt #f) -> stmt])
   `(fn ,name ,args ,type ,stmt))
  ((typedef ,name ,t) `(typedef ,name ,t))
  ((extern . ,rest)
   `(extern . ,rest)))

(define (kernel-arg->binding i)
  (lambda (x t xs)
    `(,x ,t (vector-ref ,t ,xs (var int ,i)))))

(define (kernel->for t r dims x* t* xs* ts* d* e)
  (let ((kernelfor (gensym 'x))
        (i (gensym 'i))
        (expr (gensym 'expr)))
    (assert (= (length dims) 1))
    `(let ((,expr int ,(car dims)))
       (let ((,kernelfor (vec ,r ,t) (make-vector ,t ,r
                                                  (var int ,expr))))
         (begin
           (for (,i (int 0) (var int ,expr) (int 1))
                (let ,(map (kernel-arg->binding i) x* t* xs*)
                  ,((remove-global-id-stmt i)
                    ((set-kernel-return t r kernelfor i) e))))
           (var (vec ,r ,t) ,kernelfor))))))

(define-match (Stmt k)
  ((let ((,x ,t ,[(Expr k) -> e]) ...) ,[stmt])
   `(let ((,x ,t ,e) ...) ,stmt))
  ((let-region (,r ...) ,[body]) `(let-region (,r ...) ,body))
  ((begin ,[stmt*] ...) (make-begin stmt*))
  ((error ,x) `(error ,x))
  ((for ,b ,[stmt]) `(for ,b ,stmt))
  ((while ,t ,[stmt]) `(while ,t ,stmt))
  ((if ,test ,[conseq]) `(if ,test ,conseq))
  ((if ,test ,[conseq] ,[alt])
   `(if ,test ,conseq ,alt))
  ((set! ,[(Expr k) -> lhs] ,[(Expr k) -> rhs]) `(set! ,lhs ,rhs))
  ((do ,[(Expr k) -> e]) `(do ,e))
  ((print . ,e*) `(print . ,e*))
  ((assert ,e) `(assert ,e))
  ((return) `(return))
  ((return ,[(Expr k) -> e]) `(return ,e)))

(define-match (Expr k)
  ((let ((,x ,t ,[e]) ...) ,[expr])
   `(let ((,x ,t ,e) ...) ,expr))
  ((begin ,[(Stmt k) -> stmt*] ... ,[e])
   `(begin ,@stmt* ,e))
  ((kernel (vec ,r ,t) ,r (,[dims] ...)
           (((,x* ,t*) (,[xs*] ,ts*) ,d*) ...)
           ,[(Expr #t) -> e])
   (if k
       (kernel->for t r dims x* t* xs* ts* d* e)
       `(kernel (vec ,r ,t) ,r ,dims
                (((,x* ,t*) (,xs* ,ts*) ,d*) ...)
                ,e)))
  ((if ,[t] ,[c] ,[a])
   `(if ,t ,c ,a))
  ((call ,[fn] ,[args] ...)
   `(call ,fn . ,args))
  ((int->float ,[e]) `(int->float ,e))
  ((length ,[e]) `(length ,e))
  ((,t ,x) (guard (scalar-type? t)) `(,t ,x))
  ((var ,t ,x) `(var ,t ,x))
  ((c-expr ,t ,x) `(c-expr ,t ,x))
  ((vector-ref ,t ,[v] ,[i])
   `(vector-ref ,t ,v ,i))
  ((,op ,[lhs] ,[rhs])
   (guard (or (binop? op) (relop? op)))
   `(,op ,lhs ,rhs))
  ((empty-struct) '(empty-struct))
  ((field ,[e] ,x) `(field ,e ,x))
  ((unbox ,t ,r ,[e]) `(unbox ,t ,r ,e))
  ((box ,r ,t ,[e]) `(box ,r ,t ,e))
  ((make-vector ,t ,r ,[e]) `(make-vector ,t ,r ,e))
  ((vector ,t ,r ,[e*] ...) `(vector ,t ,r . ,e*)))

(define-match (set-kernel-return t r x i)
  ((begin ,stmt* ... ,[expr])
   `(begin ,@stmt* ,expr))
  ((let ,b ,[expr])
   `(let ,b ,expr))
  (,else
   `(set! (vector-ref ,t (var (vec ,r ,t) ,x) (var int ,i))
          ,else)))

(define-match (remove-global-id-stmt i)
  ((let ((,x ,t ,[(remove-global-id-expr i) -> e]) ...)
     ,[stmt])
   `(let ((,x ,t ,e) ...) ,stmt))
  ((begin ,[stmt*] ...)
   `(begin . ,stmt*))
  ((error ,x)
   `(error ,x))
  ((for (,x ,[(remove-global-id-expr i) -> start]
            ,[(remove-global-id-expr i) -> end]
            ,[(remove-global-id-expr i) -> step])
        ,[stmt])
   `(for (,x ,start ,end ,step) ,stmt))
  ((while ,[(remove-global-id-expr i) -> t] ,[stmt])
   `(while ,t ,stmt))
  ((if ,[(remove-global-id-expr i) -> t] ,[c])
   `(if ,t ,c))
  ((if ,[(remove-global-id-expr i) -> t] ,[c] ,[a])
   `(if ,t ,c ,a))
  ((set! ,[(remove-global-id-expr i) -> lhs]
         ,[(remove-global-id-expr i) -> rhs])
   `(set! ,lhs ,rhs))
  ((do ,[(remove-global-id-expr i) -> e])
   `(do ,e))
  ((print ,[(remove-global-id-expr i) -> e*])
   `(print . ,e*))
  ((assert ,[(remove-global-id-expr i) -> e])
   `(assert ,e))
  ((return) `(return))
  ((return ,[(remove-global-id-expr i) -> e])
   `(return ,e)))

(define-match (remove-global-id-expr i)
  ((,t ,x) (guard (scalar-type? t)) `(,t ,x))
  ((var ,t ,x)
   `(var ,t ,x))
  ((begin ,[(remove-global-id-stmt i) -> stmt*] ...
          ,[expr])
   `(begin ,@stmt* ,expr))
  ((let ((,x ,t ,[e]) ...) ,[expr])
   `(let ((,x ,t ,e) ...) ,expr))
  ((if ,[t] ,[c] ,[a])
   `(if ,t ,c ,a))
  ((make-vector ,t ,r ,[n])
   `(make-vector ,t ,r ,n))
  ((vector ,t ,[e] ...)
   `(vector ,t . ,e))
  ((call
    (c-expr ((int) -> int) get_global_id)
    ,n)
   `(var int ,i))
  ;; Don't go inside kernels, the get-global-id is out of scope.
  ((kernel ,t ,r (,[dims] ...)
           (((,x ,xt) (,[e] ,et) ,i^) ...)
           ,body)
   `(kernel ,t ,r (,dims ...)
            (((,x ,xt) (,e ,et) ,i^) ...)
            ,body))
  ((call ,[fn] ,[args] ...)
   `(call ,fn . ,args))
  ((int->float ,[t])
   `(int->float ,t))
  ((length ,[t])
   `(length ,t))
  ((c-expr ,t ,x)
   `(c-expr ,t ,x))
  ((vector-ref ,t ,[v] ,[i])
   `(vector-ref ,t ,v ,i))
  ((,op ,[lhs] ,[rhs])
   (guard (or (binop? op) (relop? op)))
   `(,op ,lhs ,rhs)))

;;end library
)
