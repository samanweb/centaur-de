# Core only: the supervisor spawns processes and watches them.
centaur_session = executable('centaur-session',
  centaur_core_sources,
  version_vala,
  files('centaur-session.vala'),
  dependencies: base_deps,
  vala_args: ['--pkg', 'posix'],
  install: true,
  install_dir: bindir,
)
