all : ants

include configuration.mak

SOURCES = $(shell find src -name \*.d)

ants : $(SOURCES)
	$(DC) -o $@ $^ $(DFLAGS) $(LDFLAGS)

win32package ::
	rm -fR Escher-Win32
	mkdir Escher-Win32
	cp -v escher.exe *.dll init.txt Escher-Win32/
	cp -vR glsl Escher-Win32
	mkdir Escher-Win32/res
	cp -vR res/images Escher-Win32/res
	cp -vR res/md5 Escher-Win32/res
	cp -vR res/esc5 Escher-Win32/res
	#cp $(shell ls escher.exe *.dll init.txt glsl/*/* res/images/* res/md5/* res/esc5/* ) Escher-Win32/
	(echo Version: ; hg id ; hg parents) > Escher-Win32/version.txt
	zip "Escher-Win32.zip" -r Escher-Win32/
