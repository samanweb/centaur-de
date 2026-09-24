# Core only. No compositor, and above all no ui: this process runs as root and
# must never map GTK, Pango or a font cache.
centaur_sysd = executable('centaur-sysd',
  centaur_core_sources,
  version_vala,
  files(
    'polkit.vala',
    'backends/package-backend.vala',
    'job.vala',
    'packages.vala',
    'host.vala',
    'security.vala',
    'main.vala',
  ),
  dependencies: base_deps,
  vala_args: ['--pkg', 'posix'],
  install: true,
  install_dir: libexecdir,
)
