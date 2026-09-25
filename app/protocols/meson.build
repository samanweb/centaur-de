# Wayland protocols Centaur speaks directly. The XML is vendored because no
# distribution package ships the wlr protocols reliably; wayland-scanner turns
# each into a client header and its interface tables at build time, so nothing
# extra is needed at runtime.

wayland_scanner = find_program('wayland-scanner')
wayland_client_dep = dependency('wayland-client')

protocol_sources = {}

foreach name : [
    'wlr-foreign-toplevel-management-unstable-v1',
    'wlr-output-management-unstable-v1',
  ]
  xml = files(name + '.xml')
  header = custom_target(name + '-header',
    input: xml,
    output: name + '-client-protocol.h',
    command: [wayland_scanner, 'client-header', '@INPUT@', '@OUTPUT@'],
  )
  code = custom_target(name + '-code',
    input: xml,
    output: name + '-protocol.c',
    command: [wayland_scanner, 'private-code', '@INPUT@', '@OUTPUT@'],
  )
  protocol_sources += { name: [header, code] }
endforeach
