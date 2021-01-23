LUAJIT_VERSION := 2.0.5
# LUAJIT_VERSION := 2.1.0-beta3
WITH_PLUGINS=1
# WITH_LIBCURL=1
# SHELL=/bin/sh
DESTDIR?=/usr/local/bin/
LC_ALL=C
CC=gcc
STRIP=strip
CFLAGS+=-I./luajit/src

WARNINGS=-Wall -Wno-missing-braces -Wno-unused-variable -Wno-unused-but-set-variable
eon_cflags:=$(CFLAGS) -O2 -D_GNU_SOURCE $(WARNINGS) -g -I./mlbuf/ -I./termbox/src/ -I ./src/libs -I~/.nix-profile/include
eon_ldlibs:=$(LDLIBS)
eon_objects:=$(patsubst %.c,%.o,$(wildcard src/*.c))
eon_static:=

# this is required for building under nix environments
# PKG_CONFIG_PATH=${HOME}/.nix-profile/lib/pkgconfig/

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	eon_ldlibs+=`pkg-config --libs libpcre`
else
	eon_ldlibs+=-lrt -lpcre
endif

ifdef WITH_PLUGINS
        eon_cflags+=-I./luajit/src
	eon_ldlibs+=-L./luajit/src -lluajit -lm -ldl
	ifeq ($(UNAME_S),Darwin) # needed for luajit to work
		eon_ldlibs+=-pagezero_size 10000 -image_base 100000000
	endif
else
	eon_ldlibs+=-lm
	# remove plugins stuff from list of objects
	eon_objects:=$(subst src/plugins.o ,,$(eon_objects))
	eon_objects:=$(subst src/plugin_api.o ,,$(eon_objects))
endif

ifdef WITH_LIBCURL
	eon_cflags+=-DWITH_LIBCURL
	eon_ldlibs+=`pkg-config --libs-only-l --libs-only-L libcurl`
endif

all: eon

eon: ./mlbuf/libmlbuf.a ./termbox/build/libtermbox.a luajit/src/libluajit.a $(eon_objects)
	$(CC) $(eon_objects) $(eon_static) ./mlbuf/libmlbuf.a luajit/src/libluajit.a ./termbox/build/libtermbox.a $(eon_ldlibs) -o eon
	$(STRIP) eon

eon_static: eon_static:=-static
eon_static: eon_ldlibs:=$(eon_ldlibs) -lpthread
ifdef WITH_LIBCURL # include ssl/crypto and libz
	eon_static: eon_ldlibs:=$(eon_ldlibs) -lssl -lcrypto -ldl -lz
endif
eon_static: eon

$(eon_objects): %.o: %.c
	$(CC) -c $(eon_cflags) $< -o $@

./mlbuf/libmlbuf.a:
	$(MAKE) -C mlbuf

./termbox/build/libtermbox.a:
	@echo "Building termbox..."
	if [ ! -e termbox/build ]; then mkdir termbox/build; cd termbox/build; cmake ..; cd ..; fi
	cd termbox/build && make

luajit/src/libluajit.a: luajit
	# these below are slitaz compile flags
	# CFLAGS = -march=i486 -Os -pipe -fomit-frame-pointer
	# CPPFLAGS : -D_GLIBCXX_USE_C99_MATH=1
	# LDFLAGS  : -Wl,-Os,--as-needed
	@cd luajit; make -j2

luajit:
	@wget "http://luajit.org/download/LuaJIT-$(LUAJIT_VERSION).tar.gz"
	@tar xfv LuaJIT-$(LUAJIT_VERSION).tar.gz
	@ln -s LuaJIT-$(LUAJIT_VERSION) luajit

test: eon test_eon
	$(MAKE) -C mlbuf test

test_eon: eon
	$(MAKE) -C tests && ./eon -v

sloc:
	find . -name '*.c' -or -name '*.h' | \
		grep -Pv '(termbox|test|ut)' | \
		xargs -rn1 cat | \
		wc -l

install: eon
	install -v -m 755 eon $(DESTDIR)

clean:
	rm -f src/*.o eon.bak.* gmon.out perf.data perf.data.old eon
	$(MAKE) -C mlbuf clean
	rm -Rf termbox/build

list:
	@grep '^[a-z]*:' Makefile

.PHONY: all eon_static test test_eon sloc install clean
