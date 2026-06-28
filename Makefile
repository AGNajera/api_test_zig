BASE_URL := http://127.0.0.1:6969

.PHONY: list create get update delete

list:
	curl -sS $(BASE_URL)/notes

post:
	curl -sS -X POST $(BASE_URL)/notes -d 'Post desde Zig'

get:
	curl -sS $(BASE_URL)/notes/1

update:
	curl -sS -X PUT $(BASE_URL)/notes/1 -d 'Update desde Zig'

delete:
	curl -sS -X DELETE $(BASE_URL)/notes/1
