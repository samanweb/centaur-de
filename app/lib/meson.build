# One static archive holding three namespaces: Centaur.Core, Centaur.Ui and
# Centaur.Compositor. See README.md "Deviations from architecture.md" for why
# these are not three separate libraries yet.

libcentaur_sources = files(
  'core/log.vala',
  'core/distro.vala',
  'core/config.vala',
  'core/system-client.vala',
  'ui/theme.vala',
  'ui/card.vala',
  'ui/rows.vala',
  'ui/chip.vala',
  'ui/stat-tile.vala',
  'ui/meter-ring.vala',
  'compositor/backend.vala',
  'compositor/sway.vala',
  'compositor/labwc.vala',
  'compositor/detect.vala',
)

libcentaur = static_library('centaur',
  libcentaur_sources,
  version_vala,
  dependencies: ui_deps,
  vala_header: 'centaur.h',
  vala_vapi: 'centaur.vapi',
  vala_args: ['--pkg', 'posix'],
)

libcentaur_dep = declare_dependency(
  link_with: libcentaur,
  include_directories: include_directories('.'),
  dependencies: ui_deps,
)
