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

Code overview
=============

Code in this repository generate input for javascript
code generator (https://github.com/BartekLew/home/blob/master/js.lisp)
to be called in the static page generator (https://github.com/BartekLew/home/blob/master/js.lisp)
source. That's why it's quite a non-statandard Common Lisp code as it
uses special synax for code generator.

Deeper explanation of syntax can be found here:
https://it-wiedz-net-pl.translate.goog/misc/interpreter.html?_x_tr_sl=pl&_x_tr_tl=en&_x_tr_hl=pl&_x_tr_pto=wapp

Main function is `interpreter`, which gets language grammar description
as an input and produces code that will generate whole javascript
for interpreter. In lndn example, it's combined with html5 canvas and
text field for code input. Grammar is defined as set of tokens for lexer
and their semantic meaning. However, unlike in traditional approach
(like in flex/bison), meaning in one place with it's scanner, as described
in link above. Tokens are listed in interpretation precedence order.
