all : ants

include configuration.mak

SOURCES = $(shell find src -name \*.d)

ants : $(SOURCES)
	$(DC) -o $@ $^ $(DFLAGS) $(LDFLAGS)

win32package :: escher.exe
	zip "escher-win32-$(shell hg id|grep -o '^\S*').zip" $(shell ls escher.exe init.txt glsl/*/* res/images/* res/md5/* res/esc5/* )
