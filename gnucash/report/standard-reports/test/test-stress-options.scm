(use-modules (gnucash utilities))
(use-modules (gnucash gnc-module))
(gnc:module-begin-syntax (gnc:module-load "gnucash/app-utils" 0))
(use-modules (gnucash engine test test-extras))
(use-modules (gnucash report standard-reports))
(use-modules (gnucash report business-reports))
(use-modules (gnucash report view-column))
(use-modules (gnucash report stylesheets))
(use-modules (gnucash report taxinvoice))
(use-modules (gnucash report report-system))
(use-modules (gnucash report report-system test test-extras))
(use-modules (srfi srfi-64))
(use-modules (gnucash engine test srfi64-extras))
(use-modules (sxml simple))
(use-modules (sxml xpath))

(load "test-stress-optionslist.scm")
;; The above optionslist was generated programmatically.  It was
;; generated by running a sentinel function in the middle of an
;; existing report renderer. The sentinel function is defined as
;; follows, then was cleaned up using emacs' indenting. No other
;; processing was done.  Only the multichoice and boolean options for
;; most reports were dumped.  Although this cannot provide whole
;; coverage for option permutations, it can catch many errors while
;; refactoring inner functions.

;; (define (mydump)
;;   (with-output-to-file "test-stress-optionslist.scm"
;;     (lambda ()
;;       (display "(define optionslist\n (list \n")
;;       (gnc:report-templates-for-each
;;        (lambda (report-id template)
;;          (let* ((options-generator (gnc:report-template-options-generator template))
;;                 (name (gnc:report-template-name template))
;;                 (options (and (not (string=? name "General Journal"))
;;                               (options-generator))))
;;            (define (disp d)
;;              (define (try proc)
;;                (catch 'wrong-type-arg
;;                  (lambda () (proc d))
;;                  (const #f)))
;;              (or (and (symbol? d) (string-append "'" (symbol->string d)))
;;                  (and (list? d) (string-append "(list " (string-join (map disp d) " ") ")"))
;;                  (and (pair? d) (format #f "(cons ~a . ~a)"
;;                                         (disp (car d))
;;                                         (disp (cdr d))))
;;                  (try gnc-commodity-get-mnemonic)
;;                  (try xaccAccountGetName)
;;                  (try gnc-budget-get-name)
;;                  (format #f "~s" d)))
;;            (format #t "(list (cons 'report-id ~s)\n      (cons 'report-name ~s)\n      (cons 'options\n (list\n"
;;                    report-id (gnc:report-template-name template))
;;            (if options
;;                (gnc:options-for-each
;;                 (lambda (option)
;;                   (if (memq (gnc:option-type option) '(multichoice boolean))
;;                       (format #t "                  (vector ~s ~s '~s '~s)\n"
;;                               (gnc:option-section option)
;;                               (gnc:option-name option)
;;                               (gnc:option-type option)
;;                               (case (gnc:option-type option)
;;                                 ((multichoice) (map (lambda (d) (vector-ref d 0)) (gnc:option-data option)))
;;                                 ((boolean) (list #t #f))
;;                                 ;; (else "\"\"")
;;                                 (else (disp (gnc:option-value option)))))))
;;                 options)
;;                )
;;            (display ")))\n"))))
;;       (display "))\n"))))


;; Explicitly set locale to make the report output predictable
(setlocale LC_ALL "C")

(define (run-test)
  (test-runner-factory gnc:test-runner)
  (test-begin "stress options")
  (tests)
  (test-end "stress options"))

(define (set-option! options section name value)
  (let ((option (gnc:lookup-option options section name)))
    (if option
        (gnc:option-set-value option value))))

(define (mnemonic->commodity sym)
  (gnc-commodity-table-lookup
   (gnc-commodity-table-get-table (gnc-get-current-book))
   (gnc-commodity-get-namespace (gnc-default-report-currency))
   sym))

(define structure
  (list "Root" (list (cons 'type ACCT-TYPE-ASSET))
        (list "Asset"
              (list "Bank")
              (list "GBP Bank" (list (cons 'commodity (mnemonic->commodity "GBP"))))
              (list "Wallet"))
        (list "Income" (list (cons 'type ACCT-TYPE-INCOME)))
        (list "Income-GBP" (list (cons 'type ACCT-TYPE-INCOME)
                                 (cons 'commodity (mnemonic->commodity "GBP"))))
        (list "Expenses" (list (cons 'type ACCT-TYPE-EXPENSE)))
        (list "Liabilities" (list (cons 'type ACCT-TYPE-LIABILITY)))
        (list "Equity" (list (cons 'type ACCT-TYPE-EQUITY)))
        ))

(define (test report-name uuid report-options)
  (let ((options (gnc:make-report-options uuid)))
    (test-assert (format #f "basic test ~a" report-name)
      (gnc:options->render uuid options (string-append "stress-" report-name) "test"))
    (format #t "Testing SIMPLE combinations for:\n~a" report-name)
    (for-each
     (lambda (option)
       (format #t ",~a/~a"
               (vector-ref option 0)
               (vector-ref option 1)))
     report-options)
    (newline)
    (for-each
     (lambda (idx)
       (display report-name)
       (for-each
        (lambda (option)
          (let* ((section (vector-ref option 0))
                 (name (vector-ref option 1))
                 (value (list-ref (vector-ref option 3)
                                  (modulo idx (length (vector-ref option 3))))))
            (set-option! options section name value)
            (format #t ",~a"
                    (cond
                     ((boolean? value) (if value 't 'f))
                     (else value)))))
        report-options)
       (catch #t
         (lambda ()
           (gnc:options->render uuid options "stress-test" "test")
           (display "[pass]\n"))
         (lambda (k . args)
           (format #t "[fail]... error: (~s . ~s) options-list are:\n~a"
                   k args
                   (gnc:html-render-options-changed options #t))
           (test-assert "logging test failure as above..."
             #f))))
     (iota
      (apply max
             (map (lambda (opt) (length (vector-ref opt 3)))
                  report-options)))
     )))

(define (tests)
  (let* ((env (create-test-env))
         (account-alist (env-create-account-structure-alist env structure))
         (bank (cdr (assoc "Bank" account-alist)))
         (gbp-bank (cdr (assoc "GBP Bank" account-alist)))
         (wallet (cdr (assoc "Wallet" account-alist)))
         (income (cdr (assoc "Income" account-alist)))
         (gbp-income (cdr (assoc "Income-GBP" account-alist)))
         (expense (cdr (assoc "Expenses" account-alist)))
         (liability (cdr (assoc "Liabilities" account-alist)))
         (equity (cdr (assoc "Equity" account-alist))))
    ;; populate datafile with old transactions
    (env-transfer env 01 01 1970 bank expense       5   #:description "desc-1" #:num "trn1" #:memo "memo-3")
    (env-transfer env 31 12 1969 income bank       10   #:description "desc-2" #:num "trn2" #:void-reason "void" #:notes "notes3")
    (env-transfer env 31 12 1969 income bank       29   #:description "desc-3" #:num "trn3"
                  #:reconcile (cons #\c (gnc-dmy2time64 01 03 1970)))
    (env-transfer env 01 02 1970 bank expense      15   #:description "desc-4" #:num "trn4" #:notes "notes2" #:memo "memo-1")
    (env-transfer env 10 01 1970 liability expense 10   #:description "desc-5" #:num "trn5" #:void-reason "any")
    (env-transfer env 10 01 1970 liability expense 11   #:description "desc-6" #:num "trn6" #:notes "notes1")
    (env-transfer env 10 02 1970 bank liability     8   #:description "desc-7" #:num "trn7" #:notes "notes1" #:memo "memo-2"
                  #:reconcile (cons #\y (gnc-dmy2time64 01 03 1970)))
    (let ((txn (xaccMallocTransaction (gnc-get-current-book)))
          (split-1 (xaccMallocSplit  (gnc-get-current-book)))
          (split-2 (xaccMallocSplit  (gnc-get-current-book)))
          (split-3 (xaccMallocSplit  (gnc-get-current-book))))
      (xaccTransBeginEdit txn)
      (xaccTransSetDescription txn "$100bank -> $80expenses + $20wallet")
      (xaccTransSetCurrency txn (xaccAccountGetCommodity bank))
      (xaccTransSetDate txn 14 02 1971)
      (xaccSplitSetParent split-1 txn)
      (xaccSplitSetParent split-2 txn)
      (xaccSplitSetParent split-3 txn)
      (xaccSplitSetAccount split-1 bank)
      (xaccSplitSetAccount split-2 expense)
      (xaccSplitSetAccount split-3 wallet)
      (xaccSplitSetValue split-1 -100)
      (xaccSplitSetValue split-2 80)
      (xaccSplitSetValue split-3 20)
      (xaccSplitSetAmount split-1 -100)
      (xaccSplitSetAmount split-2 80)
      (xaccSplitSetAmount split-3 20)
      (xaccTransSetNotes txn "multisplit")
      (xaccTransCommitEdit txn))
    (let ((closing-txn (env-transfer env 31 12 1977 expense equity 111 #:description "Closing")))
      (xaccTransSetIsClosingTxn closing-txn #t))
    (env-transfer-foreign env 15 01 2000 gbp-bank bank 10 14 #:description "GBP 10 to USD 14")
    (env-transfer-foreign env 15 02 2000 bank gbp-bank  9  6 #:description "USD 9 to GBP 6")
    (for-each (lambda (m)
                (env-transfer env 08 (1+ m) 1978 gbp-income gbp-bank 51 #:description "#51 income")
                (env-transfer env 03 (1+ m) 1978 income bank  103 #:description "$103 income")
                (env-transfer env 15 (1+ m) 1978 bank expense  22 #:description "$22 expense")
                (env-transfer env 09 (1+ m) 1978 income bank  109 #:description "$109 income"))
              (iota 12))
    (let ((mid (floor (/ (+ (gnc-accounting-period-fiscal-start)
                            (gnc-accounting-period-fiscal-end)) 2))))
      (env-create-transaction env mid bank income 200))

    (for-each
     (lambda (option-set)
       (let ((report-name (assq-ref option-set 'report-name))
             (report-guid (assq-ref option-set 'report-id))
             (report-options (assq-ref option-set 'options)))
         (if (member report-name
                     ;; these reports seem to cause problems when running...
                     '("Income Statement"
                       "Tax Invoice"
                       "Net Worth Linechart"
                       "Tax Schedule Report/TXF Export"
                       "Receipt"
                       "Future Scheduled Transactions Summary"
                       "Welcome to GnuCash"
                       "Hello, World"
                       "Budget Income Statement"
                       "Multicolumn View"
                       "General Journal"
                       "Australian Tax Invoice"
                       "Balance Sheet (eguile)"
                       "networth"
                       ))
             (format #t "Skipping ~a...\n" report-name)
           (test report-name report-guid report-options))))
     optionslist)))
