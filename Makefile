.PHONY: all clean validate test

build_dir := build
protocol_xml := /usr/share/qt6/wayland/protocols/wlr-data-control/wlr-data-control-unstable-v1.xml
protocol_header := $(build_dir)/wlr-data-control-unstable-v1-client-protocol.h
protocol_code := $(build_dir)/wlr-data-control-unstable-v1-protocol.c
provider := $(build_dir)/qick-paste-clipboard-provider

all: $(provider)

$(build_dir):
	mkdir -p $@

$(protocol_header): $(protocol_xml) | $(build_dir)
	wayland-scanner client-header $< $@

$(protocol_code): $(protocol_xml) | $(build_dir)
	wayland-scanner private-code $< $@

$(provider): clipboard-provider.c $(protocol_header) $(protocol_code)
	$(CC) $(CFLAGS) -std=c11 -Wall -Wextra -Werror -O2 \
		-I$(build_dir) $< $(protocol_code) -o $@ $$(pkg-config --cflags --libs wayland-client)

validate: test $(provider)
	omarchy plugin validate .

test:
	node tests/clipboard-history.test.js
	bash tests/paste.test.sh
	bash tests/capture.test.sh
	bash tests/edit-in-tensaku.test.sh

clean:
	rm -rf -- $(build_dir)
