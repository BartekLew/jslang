jslang — browser-based interpreter generator
============================================

jslang generates pure javascript interpreter for
user defined language. It's implemented as Common
Lisp (SBCL) library. It depends on
https://github.com/BartekLew/home for generating
javascript (this functionality could be achieved
importing only js.lisp, lang.lisp and util.lisp,
which are standard Common Lisp). Example uses whole tool.

Use Makefile to clone dependency repository
and build example or use precompiled
`examples/lndn.html`
