all : ants

include configuration.mak

SOURCES = $(shell find src -name \*.d)

ants : $(SOURCES)
	$(DC) -o $@ $^ $(DFLAGS) $(LDFLAGS)
