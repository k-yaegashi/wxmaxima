(in-package "MAXIMA")

;; Modified for use with wxMaxima
;;   Andrej Vodopivec
;; This is not MathML anymore

;; MathML-printing
;; Created by David Drysdale (DMD), December 2002/January 2003
;;
;; closely based on the original TeX conversion code in mactex.lisp, 
;; for which the following credits apply:
;;   (c) copyright 1987, Richard J. Fateman
;;   small corrections and additions: Andrey Grozin, 2001
;;   additional additions: Judah Milgram (JM), September 2001
;;   additional corrections: Barton Willis (BLW), October 2001

;; Usage: wxxml(d8,"/tmp/foo.xml"); wxxml(d10,"/tmp/foo.xml"); ..
;; to append lines d8 and d10 to the wxxml file.  If given only
;; one argument the result goes to standard output.

;; Method:

;; Producing wxxml from a macsyma internal expression is done by
;; a reversal of the parsing process.  Fundamentally, a
;; traversal of the expression tree is produced by the program,
;; with appropriate substitutions and recognition of the
;; infix / prefix / postfix / matchfix relations on symbols. Various
;; changes are made to this so that MathML will like the results.

;;(macsyma-module wxxml)

#+franz
($bothcases t) ;; allow alpha and Alpha to be different
(declare-top
 (special lop rop ccol $gcprint texport $labels $inchar maxima-main-dir)
 (*expr wxxml-lbp wxxml-rbp))

(defvar *symbol-to-string* nil)

(if (equal *autoconf-version* "5.9.1")
    (setf *symbol-to-string* 'symbol-name)
  (setf *symbol-to-string* 'print-invert-case))

(defun wxxml-symbol-to-string (sym)
  (apply *symbol-to-string* (list sym)))

(defun wxxml (x l r lop rop)
  ;; x is the expression of interest; l is the list of strings to its
  ;; left, r to its right. lop and rop are the operators on the left
  ;; and right of x in the tree, and will determine if parens must
  ;; be inserted
  (setq x (nformat x))
  (cond ((atom x) (wxxml-atom x l r))
        ((or (<= (wxxml-lbp (caar x)) (wxxml-rbp lop)) 
             (> (wxxml-lbp rop) (wxxml-rbp (caar x))))
         (wxxml-paren x l r))
        ;; special check needed because macsyma notates arrays peculiarly
        ((memq 'array (cdar x)) (wxxml-array x l r))
        ;; dispatch for object-oriented wxxml-ifiying
        ((get (caar x) 'wxxml) (funcall (get (caar x) 'wxxml) x l r))
        (t (wxxml-function x l r nil))))

(defun string-substitute (newstring oldchar x &aux matchpos)
  (setq matchpos (position oldchar x))
  (if (null matchpos) x
    (concatenate 'string 
                 (subseq x 0 matchpos)
                 newstring
                 (string-substitute newstring oldchar 
                                    (subseq x (1+ matchpos))))))

;;; First we have the functions which are called directly by wxxml and its
;;; descendents

(defun wxxml-atom (x l r) 
  (append l
          (list (cond ((numberp x) (wxxmlnumformat x))
                      ((mstringp x)
                       (let* 
                           ((tmp-x (string-left-trim '(#\&)
                                                     (wxxml-symbol-to-string x)))
                            (tmp-x (string-substitute "&amp;" #\& tmp-x))
                            (tmp-x (string-substitute "&lt;" #\< tmp-x))
                            (tmp-x (string-substitute "&gt;" #\> tmp-x)))
                         tmp-x))
                      ((and (symbolp x) (get x 'wxxmlword)))
                      (t (wxxml-stripdollar x))))
	  r))

(defun wxxmlnumformat (atom)
  (let (r firstpart exponent)
    (cond ((integerp atom)
           (strcat "<mn>" (format nil "~d" atom) "</mn> "))
	  (t
	   (setq r (exploden atom))
	   (setq exponent (member 'e r :test #'string-equal))
	   (cond ((null exponent)
                  ;; it is not. go with it as given
                  (strcat "<mn>" (format nil "~s" atom) "</mn> "))
		 (t
		  (setq firstpart
			(nreverse (cdr (member 'e (reverse r) 
                                               :test #'string-equal))))
		  (strcat 
                   "<mrow><mn>"
                   (apply #'strcat firstpart)
                   "</mn><mh>*</mh> <msup><mn>10</mn><mn>"
                   (apply #'strcat (cdr exponent))
                   "</mn></msup> </mrow> ")
                  ))))))

(defun wxxml-stripdollar (sym)
  (or (symbolp sym)
      (return-from wxxml-stripdollar sym))
  (let* ((pname (wxxml-symbol-to-string sym))
         (pname (if (memq (elt pname 0) '(#\$ #\&)) (subseq pname 1) pname))
         (pname (string-substitute "&amp;" #\& pname))
         (pname (string-substitute "&gt;" #\> pname))
         (pname (string-substitute "&lt;" #\< pname)))
    (strcat "<mn>" pname "</mn> ")))

(defun wxxml-paren (x l r)
  (wxxml x (append l '("<mparen>")) (cons "</mparen> " r) 'mparen 'mparen))

(defun wxxml-array (x l r)
  (let ((f))
    (if (eq 'mqapply (caar x))
	(setq f (cadr x)
	      x (cdr x)
	      l (wxxml f (append l (list "<msub><mrow>")) nil
                       'mparen 'mparen))
      (setq f (caar x)
	    l (wxxml (wxxmlword f) (append l '("<msub><mrow>"))
                     nil lop 'mfunction)))
    (setq r (nconc (wxxml-list (cdr x) (list "</mrow><mrow> ")
                               (list "</mrow></msub> ") "<mn>,</mn>") r))
    (nconc l r)))

;; set up a list , separated by symbols (, * ...)  and then tack on the
;; ending item (e.g. "]" or perhaps ")"
(defun wxxml-list (x l r sym)
  (if (null x) r
    (do ((nl))
        ((null (cdr x))
         (setq nl (nconc nl (wxxml (car x)  l r 'mparen 'mparen)))
         nl)
        (setq nl (nconc nl (wxxml (car x)  l (list sym) 'mparen 'mparen))
              x (cdr x)
              l nil))))

;; we could patch this so sin x rather than sin(x), but instead we made
;; sin a prefix operator
(defun wxxml-function (x l r op) op
  (setq l (wxxml (wxxmlword (caar x)) (append l '("<mfun>"))
                 nil 'mparen 'mparen)
        r (wxxml (cons '(mprogn) (cdr x)) nil (append '("</mfun> ") r)
                 'mparen 'mparen))
  (nconc l r))

;;; Now we have functions which are called via property lists

(defun wxxml-prefix (x l r)
  (wxxml (cadr x) (append l (wxxmlsym (caar x))) r (caar x) rop))

(defun wxxml-infix (x l r)
  ;; check for 2 args
  (if (or (null (cddr x)) (cdddr x)) (wna-err (caar x)))
  (setq l (wxxml (cadr x) l nil lop (caar x)))
  (wxxml (caddr x) (append l (wxxmlsym (caar x))) r (caar x) rop))

(defun wxxml-postfix (x l r)
  (wxxml (cadr x) l (append (wxxmlsym (caar x)) r) lop (caar x)))

(defun wxxml-nary (x l r)
  (let* ((op (caar x))
         (sym (wxxmlsym op))
         (y (cdr x))
         (ext-lop lop)
         (ext-rop rop))
    (cond ((null y) (wxxml-function x l r t)) ; this should not happen
          ((null (cdr y)) (wxxml-function x l r t)) ; this should not happen, too
          (t (do ((nl) (lop ext-lop op)
                  (rop op (if (null (cdr y)) ext-rop op)))
                 ((null (cdr y))
                  (setq nl (nconc nl (wxxml (car y) l r lop rop))) nl)
	         (setq nl (nconc nl (wxxml (car y)  l (list sym)   lop rop))
		       y (cdr y)
		       l nil))))))

(defun wxxml-nofix (x l r) (wxxml (caar x) l r (caar x) rop))

(defun wxxml-matchfix (x l r)
  (setq l (append l (car (wxxmlsym (caar x))))
	;; car of wxxmlsym of a matchfix operator is the lead op
	r (append (cdr (wxxmlsym (caar x))) r)
	;; cdr is the trailing op
	x (wxxml-list (cdr x) nil r "<mn>,</mn>")) 
  (append l x))

(defun wxxmlsym (x)
  (or (get x 'wxxmlsym)
      (get x 'strsym)
      (get x 'dissym)
      (stripdollar x)))

(defun wxxmlword (x)
  (or (get x 'wxxmlword) 
      (stripdollar x)))

(defprop bigfloat wxxml-bigfloat wxxml)

;;(defun mathml-bigfloat (x l r) (declare (ignore l r)) (fpformat x))
(defun wxxml-bigfloat (x l r)
  (setq l (append l (fpformat x)))
  (nconc l r))

(defprop mprog  "<mn>block</mn> " wxxmlword) 
(defprop %erf   "<mn>erf</mn> "   wxxmlword)
(defprop $erf   "<mn>erf</mn> "   wxxmlword)
(defprop $true  "<mn>true</mn> "  wxxmlword)
(defprop $false "<mn>false</mn> " wxxmlword)

(defprop mprogn wxxml-matchfix wxxml)
(defprop mprogn (("<mparen>") "</mparen> ") wxxmlsym)

(defprop mlist wxxml-matchfix wxxml)
(defprop mlist (("<mn>[</mn>")"<mn>]</mn> ") wxxmlsym)

(defprop $set wxxml-matchfix wxxml)
(defprop $set (("<mn>{</mn>")"<mn>}</mn> ") wxxmlsym)

;;($matchfix '${ '$})
;;(defun ${ (&rest a)
;; `(($set) ,@a))

(defprop mabs wxxml-matchfix wxxml)
(defprop mabs (("<mabs>")"</mabs> ") wxxmlsym) 

(defprop mqapply wxxml-mqapply wxxml)
 
(defun wxxml-mqapply (x l r)
  (setq l (wxxml (cadr x) (append l '("<mfun>"))
                 (list "<mparen>" ) lop 'mfunction)
	r (wxxml-list (cddr x) nil (cons "</mparen></mfun> " r) "<mn>,</mn>"))
  (append l r))


(defprop $zeta "<g>zeta</g> " wxxmlword)
(defprop %zeta "<g>zeta</g> " wxxmlword)

;;
;; Greek characters
;;
(defprop $%alpha "<g>%alpha</g>" wxxmlword)
(defprop $%beta "<g>%beta</g>" wxxmlword)
(defprop $%gamma "<g>%gamma</g>" wxxmlword)
(defprop $%delta "<g>%delta</g>" wxxmlword)
(defprop $%epsilon "<g>%epsilon</g>" wxxmlword)
(defprop $%zeta "<g>%zeta</g>" wxxmlword)
(defprop $%eta "<g>%eta</g>" wxxmlword)
(defprop $%theta "<g>%theta</g>" wxxmlword)
(defprop $%iota "<g>%iota</g>" wxxmlword)
(defprop $%kappa "<g>%kappa</g>" wxxmlword)
(defprop $%lambda "<g>%lambda</g>" wxxmlword)
(defprop $%mu "<g>%mu</g>" wxxmlword)
(defprop $%nu "<g>%nu</g>" wxxmlword)
(defprop $%xi "<g>%xi</g>" wxxmlword)
(defprop $%omicron "<g>%omicron</g>" wxxmlword)
(defprop $%pi "<ms>%pi</ms> " wxxmlword)
(defprop $%rho "<g>%rho</g>" wxxmlword)
(defprop $%sigma "<g>%sigma</g>" wxxmlword)
(defprop $%tau "<g>%tau</g>" wxxmlword)
(defprop $%upsilon "<g>%upsilon</g>" wxxmlword)
(defprop $%phi "<g>%phi</g>" wxxmlword)
(defprop $%chi "<g>%chi</g>" wxxmlword)
(defprop $%psi "<g>%psi</g>" wxxmlword)
(defprop $%omega "<g>%omega</g>" wxxmlword)
(defprop |$%Alpha| "<g>%Alpha</g>" wxxmlword)
(defprop |$%Beta| "<g>%Beta</g>" wxxmlword)
(defprop |$%Gamma| "<g>%Gamma</g>" wxxmlword)
(defprop |$%Delta| "<g>%Delta</g>" wxxmlword)
(defprop |$%Epsilon| "<g>%Epsilon</g>" wxxmlword)
(defprop |$%Zeta| "<g>%Zeta</g>" wxxmlword)
(defprop |$%Eta| "<g>%Eta</g>" wxxmlword)
(defprop |$%Theta| "<g>%Theta</g>" wxxmlword)
(defprop |$%Iota| "<g>%Iota</g>" wxxmlword)
(defprop |$%Kappa| "<g>%Kappa</g>" wxxmlword)
(defprop |$%Lambda| "<g>%Lambda</g>" wxxmlword)
(defprop |$%Mu| "<g>%Mu</g>" wxxmlword)
(defprop |$%Nu| "<g>%Nu</g>" wxxmlword)
(defprop |$%Xi| "<g>%Xi</g>" wxxmlword)
(defprop |$%Omicron| "<g>%Omicron</g>" wxxmlword)
(defprop |$%Rho| "<g>%Rho</g>" wxxmlword)
(defprop |$%Sigma| "<g>%Sigma</g>" wxxmlword)
(defprop |$%Tau| "<g>%Tau</g>" wxxmlword)
(defprop |$%Upsilon| "<g>%Upsilon</g>" wxxmlword)
(defprop |$%Phi| "<g>%Phi</g>" wxxmlword)
(defprop |$%Chi| "<g>%Chi</g>" wxxmlword)
(defprop |$%Psi| "<g>%Psi</g>" wxxmlword)
(defprop |$%Omega| "<g>%Omega</g>" wxxmlword)
(defprop |$%Pi| "<g>%Pi</g>" wxxmlword)

(defprop $%i "<ms>%i </ms> " wxxmlword)
(defprop $%e "<ms>%e </ms> " wxxmlword)
(defprop $inf "<ms>inf </ms> " wxxmlword)
(defprop $minf "<ms>minf </ms> " wxxmlword)

(defprop mreturn "return" wxxmlword)

(defprop mquote wxxml-prefix wxxml)
(defprop mquote ("<mn>'</mn>") wxxmlsym)
(defprop mquote 201. wxxml-rbp)

(defprop msetq wxxml-infix wxxml)
(defprop msetq ("<mn>:</mn>") wxxmlsym)
(defprop msetq 180. wxxml-rbp)
(defprop msetq 20. wxxml-rbp)

(defprop mset wxxml-infix wxxml)
(defprop mset ("<mn>::</mn>") wxxmlsym)
(defprop mset 180. wxxml-lbp)
(defprop mset 20. wxxml-rbp)

(defprop mdefine wxxml-infix wxxml)
(defprop mdefine ("<mn>:=</mn>") wxxmlsym)
(defprop mdefine 180. wxxml-lbp)
(defprop mdefine 20. wxxml-rbp)

(defprop mdefmacro wxxml-infix wxxml)
(defprop mdefmacro ("<mn>::=</mn>") wxxmlsym)
(defprop mdefmacro 180. wxxml-lbp)
(defprop mdefmacro 20. wxxml-rbp)

(defprop marrow wxxml-infix wxxml)
(defprop marrow ("<mn>-></mn>") wxxmlsym)
(defprop marrow 25 wxxml-lbp)
(defprop marrow 25 wxxml-rbp)

(defprop mfactorial wxxml-postfix wxxml)
(defprop mfactorial ("<mn>!</mn>") wxxmlsym)
(defprop mfactorial 160. wxxml-lbp)

(defprop mexpt wxxml-mexpt wxxml)
(defprop mexpt 140. wxxml-lbp)
(defprop mexpt 139. wxxml-rbp)

(defprop %sum 90. wxxml-rbp)
(defprop %product 95. wxxml-rbp)

;; insert left-angle-brackets for mncexpt. a^<n> is how a^^n looks.
(defun wxxml-mexpt (x l r)
  (let((nc (eq (caar x) 'mncexpt)))
    (setq l (wxxml (cadr x) (append l (if nc
                                          '("<msup mat=\"true\"><mrow>")
                                        '("<msup><mrow>")))
                   nil lop (caar x))
          r (if (mmminusp (setq x (nformat (caddr x))))
                ;; the change in base-line makes parens unnecessary
                (wxxml (cadr x) '("</mrow> <mrow>-")
                       (cons "</mrow></msup> " r) 'mparen 'mparen)
              (if (and (integerp x) (< x 10))
                  (wxxml x (list "</mrow> ")
                         (cons "</msup> " r) 'mparen 'mparen)
                (wxxml x (list "</mrow> <mrow>")
                       (cons "</mrow></msup> " r) 'mparen 'mparen)
                )))
    (append l r)))

(defprop mncexpt wxxml-mexpt wxxml)

(defprop mncexpt 135. wxxml-lbp)
(defprop mncexpt 134. wxxml-rbp)

(defprop mnctimes wxxml-nary wxxml)
(defprop mnctimes "<mn>.</mn> " wxxmlsym)
(defprop mnctimes 110. wxxml-lbp)
(defprop mnctimes 109. wxxml-rbp)

(defprop mtimes wxxml-nary wxxml)
(defprop mtimes "<mh>*</mh>" wxxmlsym)
(defprop mtimes 120. wxxml-lbp)
(defprop mtimes 120. wxxml-rbp)

(defprop %sqrt wxxml-sqrt wxxml)

(defun wxxml-sqrt (x l r)
  (wxxml (cadr x) (append l  '("<msqrt>"))
         (append '("</msqrt>") r) 'mparen 'mparen))

(defprop mquotient wxxml-mquotient wxxml)
(defprop mquotient ("<mn>/</mn>") wxxmlsym)
(defprop mquotient 122. wxxml-lbp) ;;dunno about this
(defprop mquotient 123. wxxml-rbp)

(defun wxxml-mquotient (x l r)
  (if (or (null (cddr x)) (cdddr x)) (wna-err (caar x)))
  (setq l (wxxml (cadr x) (append l '("<mfrac><mrow>")) nil 'mparen 'mparen)
	r (wxxml (caddr x) (list "</mrow> <mrow>")
                 (append '("</mrow></mfrac> ")r) 'mparen 'mparen))
  (append l r))

(defprop $matrix wxxml-matrix wxxml)

(defun wxxml-matrix(x l r) ;;matrix looks like ((mmatrix)((mlist) a b) ...)
  (append l `("<mtable>")
          (mapcan #'(lambda(y)
                        (cond ((null (cdr y)) (list "<mtr><mtd><mspace/></mtd></mtr>"))
                              (t
                                (wxxml-list (cdr y)
                                     (list "<mtr><mtd>")
                                     (list "</mtd></mtr> ") "</mtd><mtd>"))))
                  (cdr x))
          '("</mtable>") r))

;; macsyma sum or prod is over integer range, not  low <= index <= high
;; wxxml is lots more flexible .. but

(defprop %sum wxxml-sum wxxml)
(defprop %lsum wxxml-lsum wxxml)
(defprop %product wxxml-sum wxxml)

;; easily extended to union, intersect, otherops

(defun wxxml-lsum(x l r)
  (let ((op (cond ((eq (caar x) '%lsum) "<msum><mrow>")))
	;; gotta be one of those above 
	(s1 (wxxml (cadr x) nil nil 'mparen rop));; summand
	(index ;; "index = lowerlimit"
         (wxxml `((min simp) , (caddr x), (cadddr x))
                nil nil 'mparen 'mparen)))
    (append l `(,op ,@index
                    "</mrow><mrow><mn/></mrow><mrow>"
                    ,@s1 "</mrow></msum> ") r)))

(defun wxxml-sum(x l r)
  (let ((op (cond ((eq (caar x) '%sum) "<msum><mrow>")
		  ((eq (caar x) '%product) "<msum type=\"prod\"><mrow>")
                  ;; extend here
		  ))
	;; gotta be one of those above
	(s1 (wxxml (cadr x) nil nil 'mparen rop));; summand
	(index ;; "index = lowerlimit"
         (wxxml `((mequal simp) ,(caddr x) ,(cadddr x))
                nil nil 'mparen 'mparen))
	(toplim (wxxml (car (cddddr x)) nil nil 'mparen 'mparen)))
    (append l `( ,op ,@index "</mrow><mrow>" ,@toplim
                     "</mrow><mrow>"
                     ,@s1 "</mrow></msum> ") r)))

(defprop %integrate wxxml-int wxxml)

(defun wxxml-int (x l r)
  (let ((s1 (wxxml (cadr x) nil nil 'mparen 'mparen));;integrand delims / & d
	(var (wxxml (caddr x) nil nil 'mparen rop))) ;; variable
    (cond ((= (length x) 3)
           (append l `("<mint def=\"false\"><mrow><mparen print=\"false\">"
                       ,@s1
                       "</mparen></mrow> <mrow><ms>d</ms>"
                       ,@var
                       "</mrow></mint> ") r))
          (t ;; presumably length 5
           (let ((low (wxxml (nth 3 x) nil nil 'mparen 'mparen))
                 ;; 1st item is 0
                 (hi (wxxml (nth 4 x) nil nil 'mparen 'mparen)))
             (append l `("<mint><mrow>"
                         ,@low
                         "</mrow> <mrow>"
                         ,@hi
                         "</mrow> <mrow><mparen print=\"false\">"
                         ,@s1
                         "</mparen></mrow> <mrow><ms>d</ms>"
                         ,@var "</mrow></mint> ") r))))))

(defprop %limit wxxml-limit wxxml)

(defprop mrarr wxxml-infix wxxml)
(defprop mrarr ("<mn>-></mn> ") wxxmlsym)
(defprop mrarr 80. wxxml-lbp)
(defprop mrarr 80. wxxml-rbp)

(defun wxxml-limit (x l r) ;; ignoring direction, last optional arg to limit
  (let ((s1 (wxxml (second x) nil nil 'mparen rop));; limitfunction
	(subfun ;; the thing underneath "limit"
         (wxxml `((mrarr simp) ,(third x)
                  ,(fourth x)) nil nil 'mparen 'mparen)))
    (append l `("<mlimit><mn>lim</mn><mrow>"
                ,@subfun "</mrow> <mrow>"
                ,@s1 "</mrow></mlimit>") r)))

(defprop %at wxxml-at wxxml)
;; e.g.  at(diff(f(x)),x=a)
(defun wxxml-at (x l r)
  (let ((s1 (wxxml (cadr x) nil nil lop rop))
	(sub (wxxml (caddr x) nil nil 'mparen 'mparen)))
    (append l '("<mat><mrow>") s1
            '("</mrow> <mrow>") sub '("</mrow> </mat> ") r)))

;;binomial coefficients

(defprop %binomial wxxml-choose wxxml)


(defun wxxml-choose (x l r)
  `(,@l
    "<mparen print=\"no\"><mfrac line=\"no\"><mrow>"
    ,@(wxxml (cadr x) nil nil 'mparen 'mparen)
    "</mrow> <mrow>"
    ,@(wxxml (caddr x) nil nil 'mparen 'mparen)
    "</mrow></mfrac></mparen> "
    ,@r))


(defprop rat wxxml-rat wxxml)
(defprop rat 120. wxxml-lbp)
(defprop rat 121. wxxml-rbp)
(defun wxxml-rat(x l r) (wxxml-mquotient x l r))

(defprop mplus wxxml-mplus wxxml)
(defprop mplus 100. wxxml-lbp)
(defprop mplus 100. wxxml-rbp)

(defun wxxml-mplus (x l r)
  (cond ((memq 'trunc (car x))(setq r (cons "<mn>+</mn><mn>...</mn> " r))))
  (cond ((null (cddr x))
         (if (null (cdr x))
             (wxxml-function x l r t)
           (wxxml (cadr x) l r 'mplus rop)))
        (t (setq l (wxxml (cadr x) l nil lop 'mplus)
                 x (cddr x))
           (do ((nl l)  (dissym))
               ((null (cdr x))
                (if (mmminusp (car x)) (setq l (cadar x) dissym
                                             (list "<mn>-</mn> "))
                  (setq l (car x) dissym (list "<mn>+</mn> ")))
                (setq r (wxxml l dissym r 'mplus rop))
                (append nl r))
               (if (mmminusp (car x)) (setq l (cadar x) dissym
                                            (list "<mn>-</mn> "))
                 (setq l (car x) dissym (list "<mn>+</mn> ")))
               (setq nl (append nl (wxxml l dissym nil 'mplus 'mplus))
                     x (cdr x))))))

(defprop mminus wxxml-prefix wxxml)
(defprop mminus ("-") wxxmlsym)
(defprop mminus 100. wxxml-rbp)
(defprop mminus 100. wxxml-lbp)

(defprop $~ wxxml-infix wxxml)
(defprop $~ ("<mn>~</mn> ") wxxmlsym)
(defprop $~ 80. wxxml-lbp)
(defprop $~ 80. wxxml-rbp)

(defprop min wxxml-infix wxxml)
(defprop min ("<mn>in</mn> ") wxxmlsym)
(defprop min 80. wxxml-lbp)
(defprop min 80. wxxml-rbp)

(defprop mequal wxxml-infix wxxml)
(defprop mequal ("<mn>=</mn> ") wxxmlsym)
(defprop mequal 80. wxxml-lbp)
(defprop mequal 80. wxxml-rbp)

(defprop mnotequal wxxml-infix wxxml)
(defprop mnotequal 80. wxxml-lbp)
(defprop mnotequal 80. wxxml-rbp)

(defprop mgreaterp wxxml-infix wxxml)
(defprop mgreaterp ("<mn>&gt;</mn> ") wxxmlsym)
(defprop mgreaterp 80. wxxml-lbp)
(defprop mgreaterp 80. wxxml-rbp)

(defprop mgeqp wxxml-infix wxxml)
(defprop mgeqp ("<mn>&gt;=</mn> ") wxxmlsym)
(defprop mgeqp 80. wxxml-lbp)
(defprop mgeqp 80. wxxml-rbp)

(defprop mlessp wxxml-infix wxxml)
(defprop mlessp ("<mn>&lt;</mn> ") wxxmlsym)
(defprop mlessp 80. wxxml-lbp)
(defprop mlessp 80. wxxml-rbp)

(defprop mleqp wxxml-infix wxxml)
(defprop mleqp ("<mn>&lt;=</mn> ") wxxmlsym)
(defprop mleqp 80. wxxml-lbp)
(defprop mleqp 80. wxxml-rbp)

(defprop mnot wxxml-prefix wxxml)
(defprop mnot ("<mn>not</mn> ") wxxmlsym)
(defprop mnot 70. wxxml-rbp)

(defprop mand wxxml-nary wxxml)
(defprop mand ("<mn>and</mn> ") wxxmlsym)
(defprop mand 60. wxxml-lbp)
(defprop mand 60. wxxml-rbp)

(defprop mor wxxml-nary wxxml)
(defprop mor ("<mn>or</mn> ") wxxmlsym)

(defun wxxml-setup (x)
  (let((a (car x))
       (b (cadr x)))
    ;;      (setf (get a 'wxxml) 'wxxml-prefix) ; we don't want sin x
    (setf (get a 'wxxmlword) b)
    (setf (get a 'wxxmlsym) (list b))
    (setf (get a 'wxxml-rbp) 320)
    (setf (get a 'wxxml-lbp) 320)))


(mapc #'wxxml-setup
      '(
        (%acos "<mn>acos</mn> ")
        (%asin "<mn>asin</mn> ")
        (%asinh "<mn>asin</mn> ")
        (%acosh "<mn>acosh</mn> ")
        (%atan "<mn>atan</mn> ")
        (%arg "<mn>arg</mn> ")
        (%bessel_j "<mn>bessel_j</mn> ")
        (%bessel_i "<mn>bessel_i</mn> ")
        (%bessel_k "<mn>bessel_k</mn> ")
        (%bessel_y "<mn>bessel_y</mn> ")
        (%beta "<mn>beta</mn> ")
        (%cos "<mn>cos</mn> ")
        (%cosh "<mn>cosh</mn> ")
        (%cot "<mn>cot</mn> ")
        (%coth "<mn>coth</mn> ")
        (%csc "<mn>csc</mn> ")
        (%deg "<mn>deg</mn> ")
        (%determinant "<mn>determinant</mn> ")
        (%dim "<mn>dim</mn> ")
        (%exp "<mn>exp</mn> ")
        (%gamma "<g>gamma</g> ")
        (%gcd "<mn>gcd</mn> ")
        (%hom "<mn>hom</mn> ")
        (%ker "<mn>ker</mn> ")
        (%lg "<mn>lg</mn> ")
        (%liminf "<mn>lim inf</mn> ")
        (%limsup "<mn>lim sup</mn> ")
        (%ln "<mn>ln</mn> ")
        ($li "<mn>li</mn> ")
        (%log "<mn>log</mn> ")
        (%max "<mn>max</mn> ")
        (%min "<mn>min</mn> ")
        ($psi "<mn>psi</mn> ")
        (%sec "<mn>sec</mn> ")
        (%sech "<mn>sech</mn> ")
        (%sin "<mn>sin</mn> ")
        (%sinh "<mn>sinh</mn> ")
        (%sup "<mn>sup</mn> ")
        (%tan "<mn>tan</mn> ")
        (%tanh "<mn>tanh</mn> ")
        (%erf "<mn>erf</mn> ")
        (%laplace "<mn>laplace</mn> ")
        ))

(defprop mor wxxml-nary wxxml)
(defprop mor 50. wxxml-lbp)
(defprop mor 50. wxxml-rbp)

(defprop mcond wxxml-mcond wxxml)
(defprop mcond 25. wxxml-lbp)
(defprop mcond 25. wxxml-rbp)

(defprop %derivative wxxml-derivative wxxml)
(defprop %derivative 120. wxxml-lbp)
(defprop %derivative 119. wxxml-rbp)

(defun wxxml-derivative (x l r)
  (wxxml (wxxml-d x "<ms>d</ms>") (append l '("<mdiff>"))
         (append '("</mdiff>") r) 'mparen 'mparen))

(defun wxxml-d (x dsym) ;dsym should be "&DifferentialD;" or "&PartialD;"
  ;; format the macsyma derivative form so it looks
  ;; sort of like a quotient times the deriva-dand.
  (let*
      (($simp t)
       (arg (cadr x)) ;; the function being differentiated
       (difflist (cddr x)) ;; list of derivs e.g. (x 1 y 2)
       (ords (odds difflist 0)) ;; e.g. (1 2)
       (ords (cond ((null ords) '(1))
                   (t ords)))
       (vars (odds difflist 1)) ;; e.g. (x y)
       (numer `((mexpt) ,dsym ((mplus) ,@ords))) ; d^n numerator
       (denom (cons '(mtimes)
                    (mapcan #'(lambda(b e)
                                `(,dsym ,(simplifya `((mexpt) ,b ,e) nil)))
                            vars ords))))
    `((mtimes)
      ((mquotient) ,(simplifya numer nil) ,denom)
      ,arg)))

(defun wxxml-mcond (x l r)
  (append l
          (wxxml (cadr x) '("<mn>if</mn><mspace/>")
                 '("<mspace/> <mn>then</mn><mspace/> ") 'mparen 'mparen)
          (if (eql (fifth x) '$false)
              (wxxml (caddr x) nil r 'mcond rop)
            (append (wxxml (caddr x) nil nil 'mparen 'mparen)
                    (wxxml (fifth x) '("<mspace/> <mn>else</mn><mspace/> ")
                           r 'mcond rop)))))

(defprop mdo wxxml-mdo wxxml)
(defprop mdo 30. wxxml-lbp)
(defprop mdo 30. wxxml-rbp)
(defprop mdoin wxxml-mdoin wxxml)
(defprop mdoin 30. wxxml-rbp)

(defun wxxml-lbp (x)
  (cond ((get x 'wxxml-lbp))
        (t(lbp x))))

(defun wxxml-rbp (x)
  (cond ((get x 'wxxml-rbp))
        (t(lbp x))))

;; these aren't quite right

(defun wxxml-mdo (x l r)
  (wxxml-list (wxxmlmdo x) l r "<mspace/> "))

(defun wxxml-mdoin (x l r)
  (wxxml-list (wxxmlmdoin x) l r "<mspace/> "))

(defun wxxmlmdo (x)
  (nconc (cond ((second x) `("<mn>for</mn><mspace/> " ,(second x))))
	 (cond ((equal 1 (third x)) nil)
	       ((third x)  `("<mn>from</mn><mspace/> " ,(third x))))
	 (cond ((equal 1 (fourth x)) nil)
	       ((fourth x) `("<mn>step</mn><mspace/> " ,(fourth x)))
	       ((fifth x)  `("<mn>next</mn><mspace/> " ,(fifth x))))
	 (cond ((sixth x)  `("<mn>thru</mn><mspace/>  " ,(sixth x))))
	 (cond ((null (seventh x)) nil)
	       ((eq 'mnot (caar (seventh x)))
		`("<mn>while</mn><mspace/>  " ,(cadr (seventh x))))
	       (t `("<mn>unless</mn><mspace/>  " ,(seventh x))))
	 `("<mn>do</mn><mspace/>  " ,(eighth x))))

(defun wxxmlmdoin (x)
  (nconc `("<mn>for</mn><mspace/> " ,(second x) "<mn>in</mn><mspace/>  "
           ,(third x))
	 (cond ((sixth x) `("<mn>thru</mn><mspace/>  " ,(sixth x))))
	 (cond ((null (seventh x)) nil)
	       ((eq 'mnot (caar (seventh x)))
		`("<mn>while</mn><mspace/>  " ,(cadr (seventh x))))
	       (t `("<mn>unless</mn><mspace/>  " ,(seventh x))))
	 `("<mn>do</mn><mspace/>  " ,(eighth x))))


(defun wxxml-matchfix-np (x l r)
  (setq l (append l (car (wxxmlsym (caar x))))
	;; car of wxxmlsym of a matchfix operator is the lead op
	r (append (cdr (wxxmlsym (caar x))) r)
	;; cdr is the trailing op
	x (wxxml-list (cdr x) nil r "")) 
  (append l x))

(defun wxxml-matchfix-sp (x l r)
  (setq l (append l (car (wxxmlsym (caar x))))
	;; car of wxxmlsym of a matchfix operator is the lead op
	r (append (cdr (wxxmlsym (caar x))) r)
	;; cdr is the trailing op
	x (wxxml-list (cdr x) nil r " ")) 
  (append l x))

(defprop text-string wxxml-matchfix-np wxxml)
(defprop text-string (("<mstr>")"</mstr>") wxxmlsym)

(defprop mtext wxxml-matchfix-sp wxxml)
(defprop mtext ((" ")" ") wxxmlsym)

(defun wxxml-mlable (x l r)
  (wxxml (caddr x)
         (append l
                 (if (cadr x)
                     (list (format nil "<lbl>(~A)<mspace/></lbl>"
                                   (stripdollar (wxxml-symbol-to-string (cadr x)))))
                   nil))
         r 'mparen 'mparen))

(defprop mlable wxxml-mlable wxxml)


(defun wxxml-spaceout (x l r)
  (append l (list " " (make-string (cadr x) :initial-element #\.) "") r))

(defprop spaceout wxxml-spaceout wxxml)

(defun mydispla (x)
  (let ((ccol 1)
        (texport *standard-output*))
    (mapc #'myprinc
          (wxxml x '("<mth>") '("</mth>") 'mparen 'mparen))))

(setf *alt-display2d* 'mydispla)

;;;
;;; This is the display support only - copy/paste will not work
;;;

(defmvar $pdiff_uses_prime_for_derivatives nil)
(defmvar $pdiff_prime_limit 3)
(defmvar $pdiff_uses_named_subscripts_for_derivatives nil)
(defmvar $pdiff_diff_var_names (list '(mlist) '|$x| '|$y| '|$z|))

(setf (get '%pderivop 'wxxml) 'wxxml-pderivop)

(defun wxxml-pderivop (x l r)
  (cond ((and $pdiff_uses_prime_for_derivatives (eq 3 (length x)))
	 (let* ((n (car (last x)))
		(p))
	   
	   (cond ((<= n $pdiff_prime_limit)
		  (setq p (make-list n :initial-element "'")))
		 (t
		  (setq p (list "(" n ")"))))
	   (cond ((eq rop 'mexpt)
		  (append l (list "<mparen><msup><mrow>")
                          (wxxml (cadr x) nil nil lop rop) 
			  (list "</mrow><mrow>") p
                          (list "</mrow></msup>") (list "</mparen>") r))
		 (t
		  (append (append l '("<msup><mrow>"))
                          (wxxml (cadr x) nil nil lop rop) 
			  (list "</mrow><mrow>") p
                          (list "</mrow></msup>")  r)))))
        
	((and $pdiff_uses_named_subscripts_for_derivatives 
	      (< (apply #'+ (cddr x)) $pdiff_prime_limit))
	 (let ((n (cddr x))
	       (v (mapcar #'stripdollar (cdr $pdiff_diff_var_names)))
	       (p))
	   (cond ((> (length n) (length v))
		  (merror "Not enough elements in pdiff_diff_var_names to display the expression")))
	   (dotimes (i (length n))
	     (setq p (append p (make-list (nth i n)
                                          :initial-element (nth i v)))))
	   (append (append l '("<msub><mrow>"))
                   (wxxml (cadr x) nil nil lop rop)
                   (list "</mrow><mrow>") p (list "</mrow></msub>") r)))
	(t
	 (append (append l '("<msub><mrow>"))
                 (wxxml (cadr x) nil nil lop rop)
                 (list "</mrow><mrow>(") 
		 (wxxml-list (cddr x) nil nil ",")
                 (list ")</mrow></msub>") r))))

;;(defmvar $playback_with_loadfile
;;         t  "Should we issue playback when loading sessions."  boolean)

;;(defmspec $loadfile (form)
;;  (loadfile (filestrip (cdr form)) nil
;;	    (not (memq $loadprint '(nil $autoload))))
;;  (if $playback_with_loadfile (meval '($playback))))

(declare-top
 (special $grind))

(defmspec $playback (x)
  (setq x (cdr x))
  (let ((state-pdl (cons 'playback state-pdl)))
    (prog (l l1 l2 numbp slowp nostringp inputp timep grindp inchar largp)
          (setq inchar (getlabcharn $inchar))
          (setq timep $showtime grindp $grind)
          (do ((x x (cdr x)))( (null x))
              (cond ((eq (ml-typep (car x)) 'fixnum) (setq numbp (car x)))
                    ((eq (car x) '$all))
                    ((eq (car x) '$slow) (setq slowp t))
                    ((eq (car x) '$nostring) (setq nostringp t))
                    ((eq (car x) '$grind) (setq grindp t))
                    ((eq (car x) '$input) (setq inputp t))
                    ((memq (car x) '($showtime $time))
                     (setq timep (or timep t)))
                    ((memq (car x) '($gctime $totaltime))
                     (setq timep '$all))
                    ((setq l2 (listargp (car x)))
                     (setq l1 (nconc l1 (getlabels (car l2) (cdr l2) nil))
                           largp t))
                    (t (improper-arg-err (car x) '$playback))))
          (cond ((and largp (null numbp)) (go loop))
                ((and (setq l (cdr $labels)) (not $nolabels))
                 (setq l (cdr l))))
          (when (or (null numbp) (< (length l) numbp))
            (setq l1 (reverse l)) (go loop))
          (do ((i numbp (f1- i)) (l2))
              ((zerop i) (setq l1 (nconc l1 l2)))
              (setq l2 (cons (car l) l2) l (cdr l)))
          loop (if (null l1) (return '$done))
          ((lambda (errset incharp)
             (errset
              (cond ((and (not nostringp) incharp)
                     (let ((linelable (car l1)))
                       (mterpri) (princ "<mth><prompt>")
                       (printlabel)
                       (princ "</prompt><mspace/><input>"))
                     (if grindp (mgrind (meval1 (car l1)) nil)
                       (mapc #'tyo (mstring (meval1 (car l1)))))
                     (if (get (car l1) 'nodisp) (princ '$) (princ '|;|))
                     (princ "</input></mth>")
                     (mterpri))
                    ((or incharp
                         (prog2 (when (and timep (setq l (get (car l1) 'time)))
                                  (setq x (gctimep timep (cdr l)))
                                  (mtell-open "~A msec." (car l))
                                  #+gc
                                  (if x 
                                      (mtell-open "  GCtime= ~A msec." (cdr l)))
                                  (mterpri))
                             (not (or inputp (get (car l1) 'nodisp)))))
                     (mterpri) (displa (list '(mlable) (car l1) (meval1 (car l1)))))
                    (t (go a)))))
           'errbreak2 (char= (getlabcharn (car l1)) inchar))
          (if (and slowp (cdr l1) (not (continuep))) (return '$terminated))
          a    (setq l1 (cdr l1))
          (go loop))))

(defmspec $example (l)   (setq l (cdr l))
	  (block
	      $example
	    (let ((example (car l))
		  (file (or (cadr l)  (combine-path 
				       (list *maxima-demodir* $manual_demo)))))
	      (or (symbolp example)
		  (merror
		   "First arg ~M to example must be a symbol, eg example(functions)"))
	      (setq file ($file_search1 $manual_demo '((mlist) $file_search_demo)))
	      (with-open-file
		  (st file)
		(let (			;*mread-prompt*
		      )
		  (prog ( tem  all c-tag d-tag)

		   again
		   (setq tem (read-char st nil))
		   (or tem (go notfound))
		   (or (eql tem #\&) (go again))
		   (setq tem (read-char st nil))
		   (or (eql tem #\&) (go again))
		   ;; so we are just after having read &&
	  
		   (setq tem (read st nil nil))
		   (or tem (go notfound))
		   (setq tem ($concat tem))
		   (cond ((eql tem example)
			  (go doit))
			 (t (push tem all)
			    (go again)))
		   ;; at this stage we read maxima forms and print and eval
		   ;; until a peek sees '&' as the first character of next expression.
		   doit
		   (setq tem (peek-char nil st nil))
		   (cond ((or (null tem) (eql tem #\&))
			  (return-from $example '$done)))
		   (setq tem (dbm-read st nil nil))
		   (setq $linenum (+ 1 $linenum))
		   (set (setq c-tag (makelabel $inchar)) (nth 2 tem))
		   (let ($display2d)
         (princ "<mth><prompt>")
		     (displa `((mlable) ,c-tag ""))
         (princ "</prompt><input><mspace/>")
         (displa (nth 2 tem))
         (princ "</input></mth>")
					;(mformat nil "Input: ~M;" (nth 2 tem))
		     )
		   (setq $% (meval* (nth 2 tem)))
		   (set (setq d-tag (makelabel $outchar)) $%)
		   (if (eq (caar tem) 'displayinput)
		       (displa `((mlable) ,d-tag ,$%)))
					;(mformat nil "==> ~M"  (setq $% (meval* (nth 2 tem))))
		   (go doit) 	

		   notfound
		   (format t "Not Found.  You can look at:")
		   (return-from $example
		     `((mlist) ,@ (nreverse all)))
		   ))))))

;;
;; Port of Barton Willis's texput function.
;;

(defun $wxxmlput (e s &optional tx lbp rbp)
  (cond ((mstringp e)
	 (setq e (define-symbol (string-left-trim '(#\&) e)))))
  (cond (($listp s)
	 (setq s (margs s)))
	(t
	 (setq s (list s))))
  (setq s (mapcar #'stripdollar s))
  (cond ((or (null lbp) (not (integerp lbp)))
         (setq lbp 180)))
  (cond ((or (null rbp) (not (integerp rbp)))
         (setq rbp 180)))
  (cond ((null tx)
	 (putprop e (nth 0 s) 'wxxmlword))
	((eq tx '$matchfix)
	 (putprop e 'wxxml-matchfix 'wxxml)
	 (cond ((< (length s) 2)
		(merror "Improper 2nd argument to `wxxmlput' for matchfix operator."))
	       ((eq (length s) 2)
		(putprop e (list (list (nth 0 s)) (nth 1 s)) 'wxxmlsym))
	       (t
		(putprop e (list (list (nth 0 s)) (nth 1 s) (nth 2 s)) 'wxxmlsym))))
	((eq tx '$prefix)
	 (putprop e 'wxxml-prefix 'wxxml)
	 (putprop e s 'wxxmlsym)
         (putprop e lbp 'wxxml-lbp)
         (putprop e rbp 'wxxml-rbp))
	((eq tx '$infix)
	 (putprop e 'wxxml-infix 'wxxml)
	 (putprop e  s 'wxxmlsym)
         (putprop e lbp 'wxxml-lbp)
         (putprop e rbp 'wxxml-rbp))
	((eq tx '$postfix)
	 (putprop e 'wxxml-postfix 'wxxml)
	 (putprop e  s 'wxxmlsym)
         (putprop e lbp 'wxxml-lbp))
        (t (merror "Improper arguments to `wxxmlput'."))))
