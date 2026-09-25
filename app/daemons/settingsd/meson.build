# Core, compositor and the display layout. Genuinely headless -- it opens no window and, unlike the
# earlier single-archive build, no longer links GTK at all.
centaur_settingsd = executable('centaur-settingsd',
  centaur_core_sources,
  centaur_compositor_sources,
  version_vala,
  centaur_display_sources,
  files(
    'applier.vala',
    'displays.vala',
    'main.vala',
  ),
  include_directories: centaur_display_inc,
  # wayland-client is not GTK: settingsd stays toolkit-free.
  dependencies: base_deps + [wayland_client_dep],
  vala_args: ['--pkg', 'posix'],
  install: true,
  install_dir: libexecdir,
)
