# NETRA operator guide (Indonesian): make  ->  ../NETRA-Panduan-Operator.pdf
.PHONY: pdf clean
pdf:
	latexmk -pdf -interaction=nonstopmode -halt-on-error main.tex
	cp main.pdf ../NETRA-Panduan-Operator.pdf
clean:
	latexmk -C
