CC = gcc
CFLAGS = -Wall -Wextra -Werror=return-type -O2 -g
LIBS = -lglfw -lGL -lm

main: main.c
	$(CC) $(CFLAGS) -o main main.c $(LIBS)

clean:
	rm -f main