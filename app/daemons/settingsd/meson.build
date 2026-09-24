# Links libcentaur, which links GTK. settingsd opens no window and needs no
# display -- see README.md "Deviations from architecture.md" for why the
# single-archive decision costs it a GTK link it does not use.
centaur_settingsd = executable('centaur-settingsd',
  files(
    'applier.vala',
    'main.vala',
  ),
  dependencies: [libcentaur_dep],
  vala_args: ['--pkg', 'posix'],
  install: true,
  install_dir: libexecdir,
)
