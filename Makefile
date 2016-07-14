all: internal.so

internal.so: popclick.o detectors.o
	$(CC) $(LIBFLAG) -g -o $@ -std=c++11 -stdlib=libc++ -L$(LUA_LIBDIR) popclick.o detectors.o

popclick.o: popclick.m detectors.h
	$(CC) -g -c $(CFLAGS) -I$(LUA_INCDIR) $< -o $@

detectors.o: detectors.cpp detectors.h popTemplate.h
	$(CC) -g -c $(CFLAGS) -std=c++11 -stdlib=libc++ $< -o $@

install: internal.so popclick.lua
	mkdir -p $(INST_LIBDIR)/thume/popclick/
	cp internal.so $(INST_LIBDIR)/thume/popclick/
	mkdir -p $(INST_LUADIR)/thume/
	cp popclick.lua $(INST_LUADIR)/thume/
