# Source sets, not a library.
#
# These used to be one static archive with a generated centaur.h. That header
# carried every public type, including Ui.Chip with its `GtkLabel
# parent_instance` -- and core/log.c, which uses no GTK and so includes no
# gtk/gtk.h, still included the header. GtkLabel was an incomplete type there
# and the C compile failed.
#
# Compiling the sources into each target instead gives every .c file exactly
# the declarations and includes it needs, with no shared public header to get
# this wrong. It also restores something the archive had cost: centaur-sysd and
# centaur-settingsd now genuinely link no GTK, as architecture.md section 2.3
# requires, because they never compile the ui sources at all.
#
# The price is compiling these files once per target. They are small, and the
# security property is worth more than the build seconds.

centaur_core_sources = files(
  'core/log.vala',
  'core/distro.vala',
  'core/config.vala',
  'core/system-client.vala',
  'core/wallpaper.vala',
)

# No GTK: the compositor adapter deals in plain structs and D-Bus/sockets.
centaur_compositor_sources = files(
  'compositor/backend.vala',
  'compositor/sway.vala',
  'compositor/labwc.vala',
  'compositor/detect.vala',
)

# The only source set that pulls in GTK.
centaur_ui_sources = files(
  'ui/theme.vala',
)

# Display layout: the wlr-output-management client (C, no GTK) and the model
# both centaur-displays and centaur-settingsd work from.
centaur_display_sources = files(
  'wayland/output-manager.c',
  'wayland/output-manager.vapi',
  'displays/model.vala',
  'displays/store.vala',
) + protocol_sources['wlr-output-management-unstable-v1']

centaur_display_inc = include_directories('wayland')
