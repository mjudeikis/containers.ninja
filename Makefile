MAKEFLAGS += --silent

#########################   docker build
start:
	jekyll serve
	
upload:
	git add *; git commit -m "update"; git push 
