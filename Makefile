main: main.c
	gcc -o main main.c -lglfw -lGL -lm

clean:
	rm -f main
