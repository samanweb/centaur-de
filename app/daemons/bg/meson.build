# Headless like settingsd: GLib and GSettings only. The drawing is swaybg's.
centaur_bg = executable('centaur-bg',
  centaur_core_sources,
  version_vala,
  files('main.vala'),
  dependencies: base_deps,
  vala_args: ['--pkg', 'posix'],
  install: true,
  install_dir: libexecdir,
)
