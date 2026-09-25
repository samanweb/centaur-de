centaur_background = executable('centaur-background',
  centaur_core_sources,
  centaur_ui_sources,
  version_vala,
  files(
    'window.vala',
    'main.vala',
  ),
  dependencies: ui_deps + [dependency('gdk-pixbuf-2.0')],
  install: true,
  install_dir: bindir,
)
