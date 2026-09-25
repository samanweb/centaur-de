centaur_screenshot = executable('centaur-screenshot',
  centaur_core_sources,
  centaur_ui_sources,
  version_vala,
  files(
    'capture.vala',
    'toast.vala',
    'window.vala',
    'main.vala',
  ),
  dependencies: ui_deps + [layershell_dep, dependency('gdk-pixbuf-2.0')],
  install: true,
  install_dir: bindir,
)
