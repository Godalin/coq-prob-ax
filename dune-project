(lang dune 3.8)

(using coq 0.8)

(name coq-proba-ax)

(license "GPL 3.0")

(authors "Linyu Yang")

(maintainers "Linyu Yang")

; (source
;  (github vellvm/ctrees))

; (bug_reports "https://github.com/vellvm/ctrees/issues")

(generate_opam_files true)

(package
 (name coq-proba-ax)
 (synopsis "axioms for probabilistic constructions")
 (version 0.2)
 (depends
  (coq
   (>= 8.18))
  (coq-ext-lib
   (>= 0.0))))
