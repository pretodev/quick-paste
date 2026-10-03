#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>

#include "wlr-data-control-unstable-v1-client-protocol.h"

struct format {
  const char *mime;
  const char *path;
};

struct state {
  struct wl_display *display;
  struct wl_seat *seat;
  struct zwlr_data_control_manager_v1 *manager;
  struct zwlr_data_control_device_v1 *device;
  struct zwlr_data_control_source_v1 *source;
  struct zwlr_data_control_offer_v1 *selection_offer;
  struct zwlr_data_control_offer_v1 *primary_offer;
  struct format *formats;
  size_t format_count;
  bool cancelled;
};

static volatile sig_atomic_t interrupted;

static void handle_signal(int signal_number) {
  (void)signal_number;
  interrupted = 1;
}

static const struct format *find_format(const struct state *state, const char *mime) {
  for (size_t i = 0; i < state->format_count; i++)
    if (strcmp(state->formats[i].mime, mime) == 0) return &state->formats[i];
  return NULL;
}

static void source_send(void *data, struct zwlr_data_control_source_v1 *source,
                        const char *mime, int output_fd) {
  (void)source;
  struct state *state = data;
  const struct format *format = find_format(state, mime);
  if (!format) {
    close(output_fd);
    return;
  }

  int input_fd = open(format->path, O_RDONLY | O_CLOEXEC);
  if (input_fd < 0) {
    close(output_fd);
    return;
  }

  char buffer[65536];
  ssize_t count;
  while ((count = read(input_fd, buffer, sizeof(buffer))) > 0) {
    ssize_t offset = 0;
    while (offset < count) {
      ssize_t written = write(output_fd, buffer + offset, (size_t)(count - offset));
      if (written < 0) {
        if (errno == EINTR) continue;
        goto finished;
      }
      offset += written;
    }
  }

finished:
  close(input_fd);
  close(output_fd);
}

static void source_cancelled(void *data, struct zwlr_data_control_source_v1 *source) {
  (void)source;
  ((struct state *)data)->cancelled = true;
}

static const struct zwlr_data_control_source_v1_listener source_listener = {
  .send = source_send,
  .cancelled = source_cancelled,
};

static void offer_mime(void *data, struct zwlr_data_control_offer_v1 *offer,
                       const char *mime) {
  (void)data;
  (void)offer;
  (void)mime;
}

static const struct zwlr_data_control_offer_v1_listener offer_listener = {
  .offer = offer_mime,
};

static void device_data_offer(void *data, struct zwlr_data_control_device_v1 *device,
                              struct zwlr_data_control_offer_v1 *offer) {
  (void)data;
  (void)device;
  zwlr_data_control_offer_v1_add_listener(offer, &offer_listener, NULL);
}

static void replace_offer(struct zwlr_data_control_offer_v1 **current,
                          struct zwlr_data_control_offer_v1 *next) {
  if (*current && *current != next) zwlr_data_control_offer_v1_destroy(*current);
  *current = next;
}

static void device_selection(void *data, struct zwlr_data_control_device_v1 *device,
                             struct zwlr_data_control_offer_v1 *offer) {
  (void)device;
  replace_offer(&((struct state *)data)->selection_offer, offer);
}

static void device_finished(void *data, struct zwlr_data_control_device_v1 *device) {
  (void)device;
  ((struct state *)data)->cancelled = true;
}

static void device_primary_selection(void *data, struct zwlr_data_control_device_v1 *device,
                                     struct zwlr_data_control_offer_v1 *offer) {
  (void)device;
  replace_offer(&((struct state *)data)->primary_offer, offer);
}

static const struct zwlr_data_control_device_v1_listener device_listener = {
  .data_offer = device_data_offer,
  .selection = device_selection,
  .finished = device_finished,
  .primary_selection = device_primary_selection,
};

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
                            const char *interface, uint32_t version) {
  struct state *state = data;
  if (strcmp(interface, wl_seat_interface.name) == 0 && !state->seat) {
    state->seat = wl_registry_bind(registry, name, &wl_seat_interface, version > 7 ? 7 : version);
  } else if (strcmp(interface, zwlr_data_control_manager_v1_interface.name) == 0
             && !state->manager) {
    state->manager = wl_registry_bind(registry, name,
      &zwlr_data_control_manager_v1_interface, version > 2 ? 2 : version);
  }
}

static void registry_remove(void *data, struct wl_registry *registry, uint32_t name) {
  (void)data;
  (void)registry;
  (void)name;
}

static const struct wl_registry_listener registry_listener = {
  .global = registry_global,
  .global_remove = registry_remove,
};

static void usage(const char *program) {
  fprintf(stderr, "Usage: %s MIME PATH [MIME PATH ...]\n", program);
}

int main(int argc, char **argv) {
  if (argc < 3 || argc % 2 == 0) {
    usage(argv[0]);
    return 2;
  }

  struct state state = {0};
  state.format_count = (size_t)(argc - 1) / 2;
  state.formats = calloc(state.format_count, sizeof(*state.formats));
  if (!state.formats) return 1;

  for (size_t i = 0; i < state.format_count; i++) {
    state.formats[i].mime = argv[i * 2 + 1];
    state.formats[i].path = argv[i * 2 + 2];
    if (!*state.formats[i].mime || access(state.formats[i].path, R_OK) != 0) {
      fprintf(stderr, "Unreadable clipboard payload for MIME type %s\n", state.formats[i].mime);
      free(state.formats);
      return 1;
    }
  }

  state.display = wl_display_connect(NULL);
  if (!state.display) {
    fputs("Unable to connect to the Wayland display\n", stderr);
    free(state.formats);
    return 1;
  }

  struct wl_registry *registry = wl_display_get_registry(state.display);
  wl_registry_add_listener(registry, &registry_listener, &state);
  wl_display_roundtrip(state.display);
  if (!state.seat || !state.manager) {
    fputs("The compositor does not expose wlr-data-control-v1\n", stderr);
    wl_registry_destroy(registry);
    wl_display_disconnect(state.display);
    free(state.formats);
    return 1;
  }

  state.source = zwlr_data_control_manager_v1_create_data_source(state.manager);
  zwlr_data_control_source_v1_add_listener(state.source, &source_listener, &state);
  for (size_t i = 0; i < state.format_count; i++)
    zwlr_data_control_source_v1_offer(state.source, state.formats[i].mime);

  state.device = zwlr_data_control_manager_v1_get_data_device(state.manager, state.seat);
  zwlr_data_control_device_v1_add_listener(state.device, &device_listener, &state);
  zwlr_data_control_device_v1_set_selection(state.device, state.source);
  wl_display_flush(state.display);

  signal(SIGINT, handle_signal);
  signal(SIGTERM, handle_signal);
  while (!state.cancelled && !interrupted && wl_display_dispatch(state.display) != -1) {}

  if (state.selection_offer) zwlr_data_control_offer_v1_destroy(state.selection_offer);
  if (state.primary_offer && state.primary_offer != state.selection_offer)
    zwlr_data_control_offer_v1_destroy(state.primary_offer);
  zwlr_data_control_device_v1_destroy(state.device);
  zwlr_data_control_source_v1_destroy(state.source);
  zwlr_data_control_manager_v1_destroy(state.manager);
  wl_seat_destroy(state.seat);
  wl_registry_destroy(registry);
  wl_display_disconnect(state.display);
  free(state.formats);
  return 0;
}
