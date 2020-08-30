all: example/lndn.html

home:
	git clone https://github.com/BartekLew/home

example/lndn.html: example/lndn.txt jslang.cl example/lndn.cl example/lndn.lang jslang.lang home
	HOME_LANG="jslang.lang example/lndn.lang" sbcl --script home/make.lisp example/lndn.txt
