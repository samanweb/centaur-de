project('centaur', ['c', 'vala'],
  version: '0.1.11',
  license: 'GPL-3.0-or-later',
  meson_version: '>= 0.62.0',
  default_options: ['warning_level=2', 'c_std=gnu11'],
)

gnome = import('gnome')
i18n_domain = 'centaur'

prefix     = get_option('prefix')
bindir     = get_option('bindir')
libexecdir = get_option('libexecdir')
datadir    = get_option('datadir')
sysconfdir = get_option('sysconfdir')

pkgdatadir = datadir / 'centaur'

# The version is the only build-time constant Centaur needs compiled in.
# Paths are resolved at runtime from XDG_DATA_DIRS so that a --prefix install
# and an uninstalled tree both work without a second build.
version_conf = configuration_data()
version_conf.set('VERSION', meson.project_version())
version_vala = configure_file(
  input: 'version.vala.in',
  output: 'version.vala',
  configuration: version_conf,
)

add_project_arguments('-DG_LOG_DOMAIN="centaur"', language: 'c')
add_project_arguments('-w', language: 'c')  # generated C; Vala warnings are what matter

glib_dep    = dependency('glib-2.0',    version: '>= 2.70')
gobject_dep = dependency('gobject-2.0')
gio_dep     = dependency('gio-2.0')
giounix_dep = dependency('gio-unix-2.0')
json_dep    = dependency('json-glib-1.0')
gtk_dep     = dependency('gtk4',        version: '>= 4.12')  # load_from_string

# GTK 4.20 replaced two APIs Centaur uses (Calendar.select_day and
# Settings:gtk-application-prefer-dark-theme). The code picks the new one with
# `#if GTK_4_20`, so a current GTK builds without deprecation warnings and
# 4.12 still builds at all.
if gtk_dep.version().version_compare('>= 4.20')
  add_project_arguments('--define=GTK_4_20', language: 'vala')
endif
layershell_dep = dependency('gtk4-layer-shell-0', required: get_option('topbar'))
math_dep    = meson.get_compiler('c').find_library('m', required: false)

# libm is in base_deps rather than only in ui_deps: any target may reach for
# GLib's Math bindings, and -Wl,--as-needed drops the link for those that do not.
base_deps = [glib_dep, gobject_dep, gio_dep, giounix_dep, json_dep, math_dep]
ui_deps   = base_deps + [gtk_dep]

subdir('protocols')
subdir('lib')
subdir('daemons/sysd')
subdir('daemons/settingsd')
subdir('daemons/bg')
subdir('session')
if get_option('topbar')
  subdir('modules/topbar')
endif
if get_option('displays')
  subdir('modules/displays')
endif
if get_option('background')
  subdir('modules/background')
endif
if get_option('screenshot')
  subdir('modules/screenshot')
endif
subdir('data')

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)

summary({
  'prefix'      : prefix,
  'topbar'      : get_option('topbar'),
  'displays'    : get_option('displays'),
  'background'  : get_option('background'),
  'screenshot'  : get_option('screenshot'),
}, section: 'Centaur')
