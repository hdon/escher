all : ants

include configuration.mak

SOURCES = $(shell find -L src -name \*.d)

ants : $(SOURCES)
	$(DC) -o $@ $^ $(DFLAGS) $(LDFLAGS)
