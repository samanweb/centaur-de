#include "toplevel-tracker.h"

#include <gdk/wayland/gdkwayland.h>
#include <wayland-client.h>

#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

#define MANAGER_VERSION 3

struct _CentaurToplevelTracker {
  struct wl_display *display;
  struct wl_registry *registry;
  struct zwlr_foreign_toplevel_manager_v1 *manager;
  GdkSeat *seat;

  CentaurToplevelFunc func;
  gpointer user_data;

  GHashTable *toplevels;   /* id -> Toplevel */
  guint next_id;
};

/* Properties arrive one event at a time and only mean something together, at
 * `done`. Until then they are pending, and nothing is reported. */
typedef struct {
  CentaurToplevelTracker *tracker;
  struct zwlr_foreign_toplevel_handle_v1 *handle;
  guint id;
  char *app_id;
  char *title;
  gboolean activated;
  gboolean minimized;
} Toplevel;

static void
toplevel_free (gpointer data)
{
  Toplevel *toplevel = data;

  zwlr_foreign_toplevel_handle_v1_destroy (toplevel->handle);
  g_free (toplevel->app_id);
  g_free (toplevel->title);
  g_free (toplevel);
}

static void
handle_title (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
              const char *title)
{
  Toplevel *toplevel = data;
  g_free (toplevel->title);
  toplevel->title = g_strdup (title);
}

static void
handle_app_id (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
               const char *app_id)
{
  Toplevel *toplevel = data;
  g_free (toplevel->app_id);
  toplevel->app_id = g_strdup (app_id);
}

static void
handle_output_enter (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
                     struct wl_output *output)
{
}

static void
handle_output_leave (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
                     struct wl_output *output)
{
}

static void
handle_state (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
              struct wl_array *state)
{
  Toplevel *toplevel = data;
  uint32_t *entry;

  toplevel->activated = FALSE;
  toplevel->minimized = FALSE;

  wl_array_for_each (entry, state) {
    if (*entry == ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_ACTIVATED)
      toplevel->activated = TRUE;
    else if (*entry == ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MINIMIZED)
      toplevel->minimized = TRUE;
  }
}

static void
handle_done (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle)
{
  Toplevel *toplevel = data;
  CentaurToplevelTracker *tracker = toplevel->tracker;

  tracker->func (CENTAUR_TOPLEVEL_CHANGED, toplevel->id,
                 toplevel->app_id ? toplevel->app_id : "",
                 toplevel->title ? toplevel->title : "",
                 toplevel->activated, toplevel->minimized,
                 tracker->user_data);
}

static void
handle_closed (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle)
{
  Toplevel *toplevel = data;
  CentaurToplevelTracker *tracker = toplevel->tracker;

  tracker->func (CENTAUR_TOPLEVEL_CLOSED, toplevel->id, "", "", FALSE, FALSE,
                 tracker->user_data);

  /* Frees the Toplevel and destroys the handle, as the protocol asks once
   * `closed` has been received. */
  g_hash_table_remove (tracker->toplevels, GUINT_TO_POINTER (toplevel->id));
}

static void
handle_parent (void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
               struct zwlr_foreign_toplevel_handle_v1 *parent)
{
}

static const struct zwlr_foreign_toplevel_handle_v1_listener handle_listener = {
  .title = handle_title,
  .app_id = handle_app_id,
  .output_enter = handle_output_enter,
  .output_leave = handle_output_leave,
  .state = handle_state,
  .done = handle_done,
  .closed = handle_closed,
  .parent = handle_parent,
};

static void
manager_toplevel (void *data, struct zwlr_foreign_toplevel_manager_v1 *manager,
                  struct zwlr_foreign_toplevel_handle_v1 *handle)
{
  CentaurToplevelTracker *tracker = data;
  Toplevel *toplevel = g_new0 (Toplevel, 1);

  toplevel->tracker = tracker;
  toplevel->handle = handle;
  toplevel->id = ++tracker->next_id;

  g_hash_table_insert (tracker->toplevels, GUINT_TO_POINTER (toplevel->id), toplevel);
  zwlr_foreign_toplevel_handle_v1_add_listener (handle, &handle_listener, toplevel);
}

static void
manager_finished (void *data, struct zwlr_foreign_toplevel_manager_v1 *manager)
{
  CentaurToplevelTracker *tracker = data;

  zwlr_foreign_toplevel_manager_v1_destroy (tracker->manager);
  tracker->manager = NULL;
}

static const struct zwlr_foreign_toplevel_manager_v1_listener manager_listener = {
  .toplevel = manager_toplevel,
  .finished = manager_finished,
};

static void
registry_global (void *data, struct wl_registry *registry, uint32_t name,
                 const char *interface, uint32_t version)
{
  CentaurToplevelTracker *tracker = data;

  if (tracker->manager != NULL ||
      g_strcmp0 (interface, zwlr_foreign_toplevel_manager_v1_interface.name) != 0)
    return;

  tracker->manager = wl_registry_bind (registry, name,
                                       &zwlr_foreign_toplevel_manager_v1_interface,
                                       MIN (version, MANAGER_VERSION));
  zwlr_foreign_toplevel_manager_v1_add_listener (tracker->manager,
                                                 &manager_listener, tracker);
}

static void
registry_global_remove (void *data, struct wl_registry *registry, uint32_t name)
{
}

static const struct wl_registry_listener registry_listener = {
  .global = registry_global,
  .global_remove = registry_global_remove,
};

CentaurToplevelTracker *
centaur_toplevel_tracker_new (GdkDisplay          *display,
                              CentaurToplevelFunc  func,
                              gpointer             user_data)
{
  CentaurToplevelTracker *tracker;

  if (!GDK_IS_WAYLAND_DISPLAY (display))
    return NULL;

  tracker = g_new0 (CentaurToplevelTracker, 1);
  tracker->display = gdk_wayland_display_get_wl_display (display);
  tracker->seat = gdk_display_get_default_seat (display);
  tracker->func = func;
  tracker->user_data = user_data;
  tracker->toplevels = g_hash_table_new_full (g_direct_hash, g_direct_equal,
                                              NULL, toplevel_free);

  tracker->registry = wl_display_get_registry (tracker->display);
  wl_registry_add_listener (tracker->registry, &registry_listener, tracker);
  wl_display_flush (tracker->display);

  return tracker;
}

void
centaur_toplevel_tracker_free (CentaurToplevelTracker *self)
{
  if (self == NULL)
    return;

  g_hash_table_destroy (self->toplevels);
  if (self->manager != NULL)
    zwlr_foreign_toplevel_manager_v1_stop (self->manager);
  wl_registry_destroy (self->registry);
  g_free (self);
}

static Toplevel *
lookup (CentaurToplevelTracker *self, guint id)
{
  return g_hash_table_lookup (self->toplevels, GUINT_TO_POINTER (id));
}

void
centaur_toplevel_tracker_activate (CentaurToplevelTracker *self, guint id)
{
  Toplevel *toplevel = lookup (self, id);
  struct wl_seat *seat;

  if (toplevel == NULL || self->seat == NULL)
    return;

  seat = gdk_wayland_seat_get_wl_seat (self->seat);
  if (toplevel->minimized)
    zwlr_foreign_toplevel_handle_v1_unset_minimized (toplevel->handle);
  zwlr_foreign_toplevel_handle_v1_activate (toplevel->handle, seat);
  wl_display_flush (self->display);
}

void
centaur_toplevel_tracker_minimize (CentaurToplevelTracker *self, guint id)
{
  Toplevel *toplevel = lookup (self, id);

  if (toplevel == NULL)
    return;

  zwlr_foreign_toplevel_handle_v1_set_minimized (toplevel->handle);
  wl_display_flush (self->display);
}
