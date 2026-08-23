SRCDIR ?= /opt/fpp/src
include $(SRCDIR)/makefiles/common/setup.mk
include $(SRCDIR)/makefiles/platform/*.mk

# FPP constructs the shlib path as: lib + <plugin-dir-name> + .so (confirmed
# in FPP's PluginManager::loadSHLIBPlugin()). Deriving PLUGIN_NAME from
# CURDIR — rather than hardcoding "showpilot" — means this keeps building
# the file fppd will actually dlopen() no matter what pluginInfo.json's
# repoName is set to, now or after any future rename. `make` is always
# invoked with this directory as cwd (fpp_install.sh/fpp_upgrade.sh both do
# `cd "$PLUGIN_DIR" && make`), so CURDIR is the real install directory.
# This is what fpp-data#209 taught us the hard way: repoName changed once
# already and every hardcoded "showpilot" reference broke.
PLUGIN_NAME := $(notdir $(CURDIR))
SHLIB_NAME := lib$(PLUGIN_NAME).$(SHLIB_EXT)

all: $(SHLIB_NAME)
debug: all

OBJECTS_fpp_showpilot_so += src/FPPShowPilotSync.o
LIBS_fpp_showpilot_so += -L$(SRCDIR) -lfpp
CXXFLAGS_src/FPPShowPilotSync.o += -I$(SRCDIR)

%.o: %.cpp Makefile
	$(CCACHE) $(CC) $(CFLAGS) $(CXXFLAGS) $(CXXFLAGS_$@) -c $< -o $@

$(SHLIB_NAME): $(OBJECTS_fpp_showpilot_so) $(SRCDIR)/libfpp.$(SHLIB_EXT)
	$(CCACHE) $(CC) -shared $(CFLAGS_$@) $(OBJECTS_fpp_showpilot_so) $(LIBS_fpp_showpilot_so) $(LDFLAGS) -o $@

clean:
	rm -f libfpp-showpilot.$(SHLIB_EXT) libshowpilot.$(SHLIB_EXT) $(SHLIB_NAME) $(OBJECTS_fpp_showpilot_so)
