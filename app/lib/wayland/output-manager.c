#include "output-manager.h"

#include <glib-unix.h>
#include <wayland-client.h>

#include "wlr-output-management-unstable-v1-client-protocol.h"

#define MANAGER_VERSION 4

typedef struct _Head Head;

typedef struct {
  struct zwlr_output_mode_v1 *wl;
  Head *head;
  int32_t width;
  int32_t height;
  int32_t refresh;      /* mHz; 0 when the compositor does not say */
  gboolean preferred;
} Mode;

struct _Head {
  CentaurOutputManager *manager;
  struct zwlr_output_head_v1 *wl;
  char *name;
  char *description;
  char *make;
  char *model;
  char *serial;
  int32_t width_mm;
  int32_t height_mm;
  gboolean enabled;
  Mode *current;
  int32_t x;
  int32_t y;
  int32_t transform;
  double scale;
  GPtrArray *modes;     /* Mode*, owned */
};

struct _CentaurOutputManager {
  struct wl_display *display;
  gboolean owns_display;
  guint source;

  struct wl_registry *registry;
  struct zwlr_output_manager_v1 *wl;
  uint32_t version;

  GPtrArray *heads;     /* Head*, owned */
  uint32_t serial;
  gboolean ready;

  CentaurOutputChangedFunc changed;
  gpointer user_data;
};

typedef struct {
  CentaurOutputManager *manager;
  struct zwlr_output_configuration_v1 *wl;
  GPtrArray *heads;     /* configuration_head proxies */
  CentaurOutputResultFunc func;
  gpointer user_data;
  GDestroyNotify destroy;
} Pending;

static void
flush (CentaurOutputManager *self)
{
  wl_display_flush (self->display);
}

/* --- modes ------------------------------------------------------------- */

static void
mode_destroy (Mode *mode, uint32_t version)
{
  if (version >= ZWLR_OUTPUT_MODE_V1_RELEASE_SINCE_VERSION)
    zwlr_output_mode_v1_release (mode->wl);
  else
    zwlr_output_mode_v1_destroy (mode->wl);
  g_free (mode);
}

static void
mode_size (void *data, struct zwlr_output_mode_v1 *wl, int32_t width, int32_t height)
{
  Mode *mode = data;
  mode->width = width;
  mode->height = height;
}

static void
mode_refresh (void *data, struct zwlr_output_mode_v1 *wl, int32_t refresh)
{
  ((Mode *) data)->refresh = refresh;
}

static void
mode_preferred (void *data, struct zwlr_output_mode_v1 *wl)
{
  ((Mode *) data)->preferred = TRUE;
}

static void
mode_finished (void *data, struct zwlr_output_mode_v1 *wl)
{
  Mode *mode = data;
  Head *head = mode->head;

  if (head->current == mode)
    head->current = NULL;
  g_ptr_array_remove (head->modes, mode);
  mode_destroy (mode, head->manager->version);
}

static const struct zwlr_output_mode_v1_listener mode_listener = {
  .size = mode_size,
  .refresh = mode_refresh,
  .preferred = mode_preferred,
  .finished = mode_finished,
};

/* --- heads ------------------------------------------------------------- */

static void
head_free (Head *head)
{
  uint32_t version = head->manager->version;

  for (guint i = 0; i < head->modes->len; i++)
    mode_destroy (g_ptr_array_index (head->modes, i), version);
  g_ptr_array_free (head->modes, TRUE);

  if (version >= ZWLR_OUTPUT_HEAD_V1_RELEASE_SINCE_VERSION)
    zwlr_output_head_v1_release (head->wl);
  else
    zwlr_output_head_v1_destroy (head->wl);

  g_free (head->name);
  g_free (head->description);
  g_free (head->make);
  g_free (head->model);
  g_free (head->serial);
  g_free (head);
}

#define HEAD_STRING(field)                                                   \
  static void                                                                \
  head_##field (void *data, struct zwlr_output_head_v1 *wl, const char *v)   \
  {                                                                          \
    Head *head = data;                                                       \
    g_free (head->field);                                                    \
    head->field = g_strdup (v);                                              \
  }

HEAD_STRING (name)
HEAD_STRING (description)
HEAD_STRING (make)
HEAD_STRING (model)

static void
head_serial_number (void *data, struct zwlr_output_head_v1 *wl, const char *serial)
{
  Head *head = data;
  g_free (head->serial);
  head->serial = g_strdup (serial);
}

static void
head_physical_size (void *data, struct zwlr_output_head_v1 *wl, int32_t w, int32_t h)
{
  Head *head = data;
  head->width_mm = w;
  head->height_mm = h;
}

static void
head_mode (void *data, struct zwlr_output_head_v1 *wl, struct zwlr_output_mode_v1 *wl_mode)
{
  Head *head = data;
  Mode *mode = g_new0 (Mode, 1);

  mode->wl = wl_mode;
  mode->head = head;
  g_ptr_array_add (head->modes, mode);
  zwlr_output_mode_v1_add_listener (wl_mode, &mode_listener, mode);
}

static void
head_enabled (void *data, struct zwlr_output_head_v1 *wl, int32_t enabled)
{
  Head *head = data;
  head->enabled = enabled != 0;
  if (!head->enabled)
    head->current = NULL;
}

static void
head_current_mode (void *data, struct zwlr_output_head_v1 *wl, struct zwlr_output_mode_v1 *wl_mode)
{
  ((Head *) data)->current = zwlr_output_mode_v1_get_user_data (wl_mode);
}

static void
head_position (void *data, struct zwlr_output_head_v1 *wl, int32_t x, int32_t y)
{
  Head *head = data;
  head->x = x;
  head->y = y;
}

static void
head_transform (void *data, struct zwlr_output_head_v1 *wl, int32_t transform)
{
  ((Head *) data)->transform = transform;
}

static void
head_scale (void *data, struct zwlr_output_head_v1 *wl, wl_fixed_t scale)
{
  ((Head *) data)->scale = wl_fixed_to_double (scale);
}

static void
head_finished (void *data, struct zwlr_output_head_v1 *wl)
{
  Head *head = data;
  /* The array's free function releases the head. */
  g_ptr_array_remove (head->manager->heads, head);
}

static void
head_adaptive_sync (void *data, struct zwlr_output_head_v1 *wl, uint32_t state)
{
}

static const struct zwlr_output_head_v1_listener head_listener = {
  .name = head_name,
  .description = head_description,
  .physical_size = head_physical_size,
  .mode = head_mode,
  .enabled = head_enabled,
  .current_mode = head_current_mode,
  .position = head_position,
  .transform = head_transform,
  .scale = head_scale,
  .finished = head_finished,
  .make = head_make,
  .model = head_model,
  .serial_number = head_serial_number,
  .adaptive_sync = head_adaptive_sync,
};

/* --- snapshot ---------------------------------------------------------- */

static GVariant *
snapshot (CentaurOutputManager *self)
{
  GVariantBuilder heads;

  g_variant_builder_init (&heads, G_VARIANT_TYPE ("aa{sv}"));

  for (guint i = 0; i < self->heads->len; i++) {
    Head *head = g_ptr_array_index (self->heads, i);
    GVariantBuilder props, modes;
    int current = -1;

    g_variant_builder_init (&modes, G_VARIANT_TYPE ("a(iiib)"));
    for (guint m = 0; m < head->modes->len; m++) {
      Mode *mode = g_ptr_array_index (head->modes, m);
      if (mode == head->current)
        current = (int) m;
      g_variant_builder_add (&modes, "(iiib)",
                             mode->width, mode->height, mode->refresh, mode->preferred);
    }

    g_variant_builder_init (&props, G_VARIANT_TYPE ("a{sv}"));
#define PUT(key, fmt, value) \
    g_variant_builder_add (&props, "{sv}", key, g_variant_new (fmt, value))
    PUT ("name", "s", head->name ? head->name : "");
    PUT ("description", "s", head->description ? head->description : "");
    PUT ("make", "s", head->make ? head->make : "");
    PUT ("model", "s", head->model ? head->model : "");
    PUT ("serial", "s", head->serial ? head->serial : "");
    PUT ("width-mm", "i", head->width_mm);
    PUT ("height-mm", "i", head->height_mm);
    PUT ("enabled", "b", head->enabled);
    PUT ("x", "i", head->x);
    PUT ("y", "i", head->y);
    PUT ("transform", "i", head->transform);
    PUT ("scale", "d", head->scale);
    PUT ("current", "i", current);
#undef PUT
    g_variant_builder_add (&props, "{sv}", "modes", g_variant_builder_end (&modes));

    g_variant_builder_add (&heads, "a{sv}", &props);
  }

  return g_variant_ref_sink (g_variant_builder_end (&heads));
}

/* --- manager ----------------------------------------------------------- */

static void
manager_head (void *data, struct zwlr_output_manager_v1 *wl, struct zwlr_output_head_v1 *wl_head)
{
  CentaurOutputManager *self = data;
  Head *head = g_new0 (Head, 1);

  head->manager = self;
  head->wl = wl_head;
  head->scale = 1.0;
  head->modes = g_ptr_array_new ();
  g_ptr_array_add (self->heads, head);
  zwlr_output_head_v1_add_listener (wl_head, &head_listener, head);
}

/* Every change arrives as a batch of events closed by `done`; the layout only
 * means something at that point. */
static void
manager_done (void *data, struct zwlr_output_manager_v1 *wl, uint32_t serial)
{
  CentaurOutputManager *self = data;
  GVariant *heads;

  self->serial = serial;
  self->ready = TRUE;

  heads = snapshot (self);
  self->changed (heads, self->user_data);
  g_variant_unref (heads);
}

static void
manager_finished (void *data, struct zwlr_output_manager_v1 *wl)
{
  CentaurOutputManager *self = data;

  zwlr_output_manager_v1_destroy (self->wl);
  self->wl = NULL;
  self->ready = FALSE;
}

static const struct zwlr_output_manager_v1_listener manager_listener = {
  .head = manager_head,
  .done = manager_done,
  .finished = manager_finished,
};

static void
registry_global (void *data, struct wl_registry *registry, uint32_t name,
                 const char *interface, uint32_t version)
{
  CentaurOutputManager *self = data;

  if (self->wl != NULL ||
      g_strcmp0 (interface, zwlr_output_manager_v1_interface.name) != 0)
    return;

  self->version = MIN (version, MANAGER_VERSION);
  self->wl = wl_registry_bind (registry, name, &zwlr_output_manager_v1_interface,
                               self->version);
  zwlr_output_manager_v1_add_listener (self->wl, &manager_listener, self);
}

static void
registry_global_remove (void *data, struct wl_registry *registry, uint32_t name)
{
}

static const struct wl_registry_listener registry_listener = {
  .global = registry_global,
  .global_remove = registry_global_remove,
};

static CentaurOutputManager *
manager_new (struct wl_display *display, gboolean owns_display,
             CentaurOutputChangedFunc changed, gpointer user_data)
{
  CentaurOutputManager *self = g_new0 (CentaurOutputManager, 1);

  self->display = display;
  self->owns_display = owns_display;
  self->changed = changed;
  self->user_data = user_data;
  self->heads = g_ptr_array_new_with_free_func ((GDestroyNotify) head_free);

  self->registry = wl_display_get_registry (display);
  wl_registry_add_listener (self->registry, &registry_listener, self);
  flush (self);

  return self;
}

CentaurOutputManager *
centaur_output_manager_new_for_display (gpointer                 wl_display,
                                        CentaurOutputChangedFunc changed,
                                        gpointer                 user_data)
{
  g_return_val_if_fail (wl_display != NULL, NULL);
  return manager_new (wl_display, FALSE, changed, user_data);
}

/* Reads whatever is waiting and dispatches it. Requests sent from inside the
 * handlers (a release, say) are flushed before going back to sleep. */
static gboolean
dispatch (gint fd, GIOCondition condition, gpointer data)
{
  CentaurOutputManager *self = data;

  if ((condition & (G_IO_ERR | G_IO_HUP)) ||
      wl_display_dispatch (self->display) == -1) {
    g_warning ("lost the Wayland connection; display changes are no longer followed");
    self->source = 0;
    self->ready = FALSE;
    return G_SOURCE_REMOVE;
  }

  flush (self);
  return G_SOURCE_CONTINUE;
}

CentaurOutputManager *
centaur_output_manager_new_connected (CentaurOutputChangedFunc changed,
                                      gpointer                 user_data)
{
  struct wl_display *display = wl_display_connect (NULL);
  CentaurOutputManager *self;

  if (display == NULL)
    return NULL;

  self = manager_new (display, TRUE, changed, user_data);
  self->source = g_unix_fd_add (wl_display_get_fd (display),
                                G_IO_IN | G_IO_ERR | G_IO_HUP, dispatch, self);
  return self;
}

void
centaur_output_manager_free (CentaurOutputManager *self)
{
  if (self == NULL)
    return;

  if (self->source != 0)
    g_source_remove (self->source);

  g_ptr_array_free (self->heads, TRUE);
  if (self->wl != NULL)
    zwlr_output_manager_v1_stop (self->wl);
  wl_registry_destroy (self->registry);
  flush (self);

  if (self->owns_display)
    wl_display_disconnect (self->display);
  g_free (self);
}

gboolean
centaur_output_manager_is_ready (CentaurOutputManager *self)
{
  return self != NULL && self->wl != NULL && self->ready;
}

/* --- configuration ----------------------------------------------------- */

static void
pending_finish (Pending *pending, const char *result)
{
  pending->func (result, pending->user_data);
  if (pending->destroy != NULL)
    pending->destroy (pending->user_data);
  if (pending->wl != NULL)
    zwlr_output_configuration_v1_destroy (pending->wl);
  /* configuration_head has no destructor request: the server drops it with
   * its configuration, and only the client-side proxy is left to free. */
  for (guint i = 0; i < pending->heads->len; i++)
    wl_proxy_destroy (g_ptr_array_index (pending->heads, i));
  g_ptr_array_free (pending->heads, TRUE);
  flush (pending->manager);
  g_free (pending);
}

static void
config_succeeded (void *data, struct zwlr_output_configuration_v1 *wl)
{
  pending_finish (data, "succeeded");
}

static void
config_failed (void *data, struct zwlr_output_configuration_v1 *wl)
{
  pending_finish (data, "failed");
}

static void
config_cancelled (void *data, struct zwlr_output_configuration_v1 *wl)
{
  pending_finish (data, "cancelled");
}

static const struct zwlr_output_configuration_v1_listener config_listener = {
  .succeeded = config_succeeded,
  .failed = config_failed,
  .cancelled = config_cancelled,
};

static gboolean
finish_later (gpointer data)
{
  pending_finish (data, "failed");
  return G_SOURCE_REMOVE;
}

/* The request for one head, or NULL when the caller did not mention it. */
static GVariantDict *
lookup_request (GVariant *config, const char *name)
{
  GVariantIter iter;
  GVariant *props;

  g_variant_iter_init (&iter, config);
  while ((props = g_variant_iter_next_value (&iter)) != NULL) {
    GVariantDict *dict = g_variant_dict_new (props);
    const char *wanted = NULL;

    g_variant_unref (props);
    if (g_variant_dict_lookup (dict, "name", "&s", &wanted) &&
        g_strcmp0 (wanted, name) == 0)
      return dict;
    g_variant_dict_unref (dict);
  }
  return NULL;
}

static Mode *
fallback_mode (Head *head)
{
  if (head->current != NULL)
    return head->current;
  for (guint m = 0; m < head->modes->len; m++) {
    Mode *mode = g_ptr_array_index (head->modes, m);
    if (mode->preferred)
      return mode;
  }
  return head->modes->len > 0 ? g_ptr_array_index (head->modes, 0) : NULL;
}

void
centaur_output_manager_apply (CentaurOutputManager    *self,
                              GVariant                *config,
                              gboolean                 test,
                              CentaurOutputResultFunc  result,
                              gpointer                 user_data,
                              GDestroyNotify           destroy)
{
  Pending *pending;

  g_return_if_fail (g_variant_is_of_type (config, G_VARIANT_TYPE ("aa{sv}")));

  pending = g_new0 (Pending, 1);
  pending->manager = self;
  pending->heads = g_ptr_array_new ();
  pending->func = result;
  pending->user_data = user_data;
  pending->destroy = destroy;

  /* Reported from an idle rather than inline, so a caller that waits on the
   * result never sees it arrive before it has started waiting. */
  if (!centaur_output_manager_is_ready (self)) {
    g_idle_add (finish_later, pending);
    return;
  }

  pending->wl = zwlr_output_manager_v1_create_configuration (self->wl, self->serial);
  zwlr_output_configuration_v1_add_listener (pending->wl, &config_listener, pending);

  /* The protocol makes it an error to leave any head unconfigured. */
  for (guint i = 0; i < self->heads->len; i++) {
    Head *head = g_ptr_array_index (self->heads, i);
    GVariantDict *request = lookup_request (config, head->name);
    gboolean enabled = head->enabled;
    struct zwlr_output_configuration_head_v1 *wl_head;
    Mode *mode;
    int32_t index, x = head->x, y = head->y, transform = head->transform;
    double scale = head->scale;

    if (request != NULL)
      g_variant_dict_lookup (request, "enabled", "b", &enabled);

    if (!enabled) {
      zwlr_output_configuration_v1_disable_head (pending->wl, head->wl);
      if (request != NULL)
        g_variant_dict_unref (request);
      continue;
    }

    mode = fallback_mode (head);
    if (request != NULL) {
      if (g_variant_dict_lookup (request, "mode", "i", &index) &&
          index >= 0 && (guint) index < head->modes->len)
        mode = g_ptr_array_index (head->modes, index);
      g_variant_dict_lookup (request, "x", "i", &x);
      g_variant_dict_lookup (request, "y", "i", &y);
      g_variant_dict_lookup (request, "transform", "i", &transform);
      g_variant_dict_lookup (request, "scale", "d", &scale);
      g_variant_dict_unref (request);
    }

    wl_head = zwlr_output_configuration_v1_enable_head (pending->wl, head->wl);
    g_ptr_array_add (pending->heads, wl_head);
    if (mode != NULL)
      zwlr_output_configuration_head_v1_set_mode (wl_head, mode->wl);
    zwlr_output_configuration_head_v1_set_position (wl_head, x, y);
    zwlr_output_configuration_head_v1_set_transform (wl_head, transform);
    zwlr_output_configuration_head_v1_set_scale (wl_head, wl_fixed_from_double (scale));
  }

  if (test)
    zwlr_output_configuration_v1_test (pending->wl);
  else
    zwlr_output_configuration_v1_apply (pending->wl);
  flush (self);
}
