; XT-IDE owns INT 13h after the early preload. SBM's optional INT 13h wrapper
; is intentionally disabled so it cannot replace or uninstall XT-IDE.

install_myint13h:
uninstall_myint13h:
set_drive_map:
set_io_ports:
	ret
