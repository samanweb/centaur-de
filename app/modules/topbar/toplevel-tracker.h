#pragma once

#include <gtk/gtk.h>

G_BEGIN_DECLS

/*
 * Follows every open window through wlr-foreign-toplevel-management, which
 * both labwc and sway implement. The compositor backends cannot supply this:
 * labwc has no IPC for it at all, and the protocol is the one view of the
 * window list that works the same on both.
 *
 * The protocol objects are created on GDK's own wl_display and default queue,
 * so GDK's event source dispatches them: no thread, no second connection and
 * no polling.
 */

typedef enum {
  CENTAUR_TOPLEVEL_CHANGED,
  CENTAUR_TOPLEVEL_CLOSED,
} CentaurToplevelEvent;

typedef void (*CentaurToplevelFunc) (CentaurToplevelEvent event,
                                     guint                id,
                                     const char          *app_id,
                                     const char          *title,
                                     gboolean             activated,
                                     gboolean             minimized,
                                     gpointer             user_data);

typedef struct _CentaurToplevelTracker CentaurToplevelTracker;

/* NULL when the display is not Wayland. A compositor without the protocol
 * gives a tracker that simply never reports anything. */
CentaurToplevelTracker *centaur_toplevel_tracker_new      (GdkDisplay             *display,
                                                           CentaurToplevelFunc     func,
                                                           gpointer                user_data);
void                    centaur_toplevel_tracker_free     (CentaurToplevelTracker *self);

void                    centaur_toplevel_tracker_activate (CentaurToplevelTracker *self,
                                                           guint                   id);
void                    centaur_toplevel_tracker_minimize (CentaurToplevelTracker *self,
                                                           guint                   id);

G_END_DECLS
