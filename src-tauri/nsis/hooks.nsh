; U-file shell integration. The installer runs in current-user mode, so all
; registrations stay under HKCU and never require administrator elevation.
; The keys are U-file's own, so an installed FileMoa keeps its menu entry.

!define UFILE_SHELL_LABEL "U-file로 정리 / Organize with U-file"

!macro UFILE_WRITE_SHELL_VERB ROOT_PATH PATH_TOKEN
  WriteRegStr HKCU "${ROOT_PATH}" "MUIVerb" "${UFILE_SHELL_LABEL}"
  WriteRegStr HKCU "${ROOT_PATH}" "Icon" "$INSTDIR\${MAINBINARYNAME}.exe"
  WriteRegStr HKCU "${ROOT_PATH}" "Position" "Top"
  WriteRegStr HKCU "${ROOT_PATH}\command" "" '"$INSTDIR\${MAINBINARYNAME}.exe" --organize "${PATH_TOKEN}"'
!macroend

!macro NSIS_HOOK_POSTINSTALL
  ; A folder itself, a folder background, and a drive root are all useful
  ; entry points. %1 is the selected item; %V is the current background path.
  !insertmacro UFILE_WRITE_SHELL_VERB "Software\Classes\Directory\shell\U-file" "%1"
  !insertmacro UFILE_WRITE_SHELL_VERB "Software\Classes\Directory\Background\shell\U-file" "%V"
  WriteRegStr HKCU "Software\Classes\Directory\Background\shell\U-file" "NoWorkingDirectory" ""
  !insertmacro UFILE_WRITE_SHELL_VERB "Software\Classes\DesktopBackground\shell\U-file" "%V"
  WriteRegStr HKCU "Software\Classes\DesktopBackground\shell\U-file" "NoWorkingDirectory" ""
  !insertmacro UFILE_WRITE_SHELL_VERB "Software\Classes\Drive\shell\U-file" "%1"
!macroend

!macro NSIS_HOOK_PREUNINSTALL
  DeleteRegKey HKCU "Software\Classes\Directory\shell\U-file"
  DeleteRegKey HKCU "Software\Classes\Directory\Background\shell\U-file"
  DeleteRegKey HKCU "Software\Classes\DesktopBackground\shell\U-file"
  DeleteRegKey HKCU "Software\Classes\Drive\shell\U-file"
!macroend
