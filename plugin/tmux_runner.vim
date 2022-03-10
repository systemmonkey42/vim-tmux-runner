"
"
"
"
"
"
"

function! VtrSendCommand(command, ...)
    let l:ensure_pane = 0
    if exists("a:1")
      let l:ensure_pane = a:1
    endif
    call tmux_runner#SendCommandToRunner(l:ensure_pane, a:command)
endfunction

call tmux_runner#InitializeVariables()
call tmux_runner#DefineCommands()
call tmux_runner#DefineKeymaps()

" vim: set sw=4 ts=4 sts=4 et:
