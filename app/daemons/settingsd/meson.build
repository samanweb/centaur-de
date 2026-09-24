# Core and compositor. Genuinely headless -- it opens no window and, unlike the
# earlier single-archive build, no longer links GTK at all.
centaur_settingsd = executable('centaur-settingsd',
  centaur_core_sources,
  centaur_compositor_sources,
  version_vala,
  files(
    'applier.vala',
    'main.vala',
  ),
  dependencies: base_deps,
  vala_args: ['--pkg', 'posix'],
  install: true,
  install_dir: libexecdir,
)
