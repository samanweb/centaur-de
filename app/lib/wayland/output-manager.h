#pragma once

#include <glib.h>

G_BEGIN_DECLS

/*
 * Reads and changes the display layout through wlr-output-management, which
 * labwc and sway both implement: the one display API that works the same on
 * both, and what wlr-randr and kanshi use.
 *
 * GLib and libwayland only -- no GTK -- so the headless centaur-settingsd can
 * link it as well as the display settings window.
 *
 * The boundary with Vala is GVariant, not structs: the protocol delivers a
 * head as a dozen separate events, and a snapshot of plain values is the only
 * shape that crosses into Vala without a hand-written binding per field.
 *
 * Snapshot, one a{sv} per head:
 *   name s, description s, make s, model s, serial s,
 *   width-mm i, height-mm i, enabled b, x i, y i, transform i, scale d,
 *   current i (index into modes, -1 when disabled),
 *   modes a(iiib): width, height, refresh in mHz, preferred
 *
 * Configuration, one a{sv} per head to change, keyed by name:
 *   name s (required), enabled b, mode i (index into that head's modes),
 *   x i, y i, transform i, scale d
 * Missing keys keep the head's current value, and heads not listed keep
 * their current state -- the protocol requires every head to be configured,
 * so this fills the rest in.
 */

typedef struct _CentaurOutputManager CentaurOutputManager;

/* heads is an aa{sv}; borrowed for the duration of the call. */
typedef void (*CentaurOutputChangedFunc) (GVariant *heads, gpointer user_data);

/* "succeeded", "failed" or "cancelled" (the layout changed underneath). */
typedef void (*CentaurOutputResultFunc) (const char *result, gpointer user_data);

/* Uses a wl_display someone else dispatches -- GDK's, in a GTK program. */
CentaurOutputManager *centaur_output_manager_new_for_display (gpointer                 wl_display,
                                                              CentaurOutputChangedFunc changed,
                                                              gpointer                 user_data);

/* Opens its own connection to $WAYLAND_DISPLAY and dispatches it from the
 * GLib main loop. NULL when there is no Wayland display. */
CentaurOutputManager *centaur_output_manager_new_connected   (CentaurOutputChangedFunc changed,
                                                              gpointer                 user_data);

void                  centaur_output_manager_free            (CentaurOutputManager    *self);

/* FALSE until the compositor has announced the protocol and sent the first
 * complete layout. */
gboolean              centaur_output_manager_is_ready        (CentaurOutputManager    *self);

/* test: validate only, change nothing. */
void                  centaur_output_manager_apply           (CentaurOutputManager    *self,
                                                              GVariant                *config,
                                                              gboolean                 test,
                                                              CentaurOutputResultFunc  result,
                                                              gpointer                 user_data,
                                                              GDestroyNotify           destroy);

G_END_DECLS
