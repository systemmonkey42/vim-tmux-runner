function! s:InitVariable(var, value)
    if !exists(a:var)
        let l:escaped_value = substitute(a:value, "'", "''", "g")
        exec 'let ' . a:var . ' = ' . "'" . l:escaped_value . "'"
        return 1
    endif
    return 0
endfunction

function! s:DictFetch(dict, key, default)
    if has_key(a:dict, a:key)
        return a:dict[a:key]
    else
        return a:default
    endif
endfunction

function! s:CreateRunnerPane(...)
    if exists("a:1")
        let s:vtr_orientation = s:DictFetch(a:1, 'orientation', s:vtr_orientation)
        let s:vtr_percentage = s:DictFetch(a:1, 'percentage', s:vtr_percentage)
        let g:VtrInitialCommand = s:DictFetch(a:1, 'cmd', g:VtrInitialCommand)
    endif
    let s:vim_pane = s:GetPaneID()
    let s:runner_pane = s:SendTmuxCommand("split-window", "-d", "-P", "-F", "'#{pane_id}'", "-p", s:vtr_percentage, "-".s:vtr_orientation)
    if g:VtrGitCdUpOnOpen
        call s:GitCdUp()
    endif
    if g:VtrInitialCommand != ""
        call s:SendKeys(g:VtrInitialCommand)
    endif
endfunction

function! s:DetachRunnerPane()
    if !s:ValidRunnerPaneSet() | return | endif
    call s:BreakRunnerPaneToTempWindow()
    let l:cmd = join(["rename-window -t", s:detached_window, g:VtrDetachedName])
    call s:SendTmuxCommand(l:cmd)
endfunction

function! s:ValidRunnerPaneSet()
    if !exists("s:runner_pane")
        call s:EchoError("No runner pane attached.")
        return 0
    endif
    if !s:ValidRunnerPaneNumber(s:runner_pane)
        call s:EchoError("Runner pane setting (" . s:runner_pane . ") is invalid. Please reattach.")
        return 0
    endif
    return 1
endfunction

function! s:DetachedWindowOutOfSync()
  let l:window_map = s:WindowMap()
  if index(keys(l:window_map), s:detached_window) == -1
    return 1
  endif
  if s:WindowMap()[s:detached_window] != g:VtrDetachedName
    return 1
  endif
  return 0
endfunction

function! s:DetachedPaneAvailable()
  if exists("s:detached_window")
    if s:DetachedWindowOutOfSync()
      call s:EchoError("Detached pane out of sync. Unable to kill")
      unlet s:detached_window
      return 0
    endif
  else
    call s:EchoError("No detached runner pane.")
    return 0
  endif
  return 1
endfunction

function! s:RequireLocalPaneOrDetached()
    if !exists('s:detached_window') && !exists('s:runner_pane')
        call s:EchoError("No pane, local or detached.")
        return 0
    endif
    return 1
endfunction

function! s:KillLocalRunner()
    if s:ValidRunnerPaneSet()
      call s:SendTmuxCommand('kill-pane', '-t', s:runner_pane)
      unlet s:runner_pane
    endif
endfunction

function! s:WindowMap()
  let l:window_pattern = '\v(\d+): ([-_a-zA-Z]{-})[-\* ]\s.*'
  let l:window_map = {}
  for l:line in split(s:SendTmuxCommand("list-windows"), "\n")
    let l:dem = split(substitute(l:line, l:window_pattern, '\1:\2', ""), ':')
    let l:window_map[l:dem[0]] = l:dem[1]
  endfor
  return l:window_map
endfunction

function! s:KillDetachedWindow()
    if !s:DetachedPaneAvailable() | return | endif
    call s:SendTmuxCommand("kill-window", '-t', s:detached_window)
    unlet s:detached_window
endfunction

function! s:KillRunnerPane()
    if !s:RequireLocalPaneOrDetached() | return | endif
    if exists("s:runner_pane")
        call s:KillLocalRunner()
    else
        call s:KillDetachedWindow()
    endif
endfunction

function! s:GetPaneID(...)
    let l:target=''
    if !empty(a:0)
        let l:target = '-t '.a:0
    endif
  echo "display-message ".l:target."-p '#{pane_id}'"
  call getchar()
  return str2nr(s:SendTmuxCommand("display-message ".l:target."-p \"#{pane_id}\""))
endfunction

function! s:ActivePaneIndex()
  return s:SendTmuxCommand("display-message -p \"#{pane_id}\"")
endfunction

function! s:TmuxPanes()
    let l:panes = s:SendTmuxCommand("list-panes")
    return split(l:panes, '\n')
endfunction

function! s:FocusTmuxPane(pane_number)
    call s:SendTmuxCommand('select-pane', '-t', a:pane_number)
endfunction

function! s:RunnerPaneDimensions()
    let [ l:width, l:height ] = s:GetTmuxInfo('#{pane_width}','#{pane_height}')
    return {'width': l:width, 'height': l:height}
endfunction

function! s:FocusRunnerPane(should_zoom)
    if !s:ValidRunnerPaneSet() | return | endif
    call s:FocusTmuxPane(s:runner_pane)
    if a:should_zoom
        call s:SendTmuxCommand("resize-pane -Z")
    endif
endfunction

function! s:Strip(string)
    return substitute(a:string, '^\s*\(.\{-}\)\s*\n\?$', '\1', '')
endfunction

function! s:SendTmuxCommand(...)
    return s:Strip(system('tmux ' . join(a:000)))
endfunction

function! s:GetTmuxInfo(...) abort
    echo "args = ".str(a:0)
endfunction

function! s:_SendKeys(keys)
    call s:SendTmuxCommand('send-keys','-t',s:runner_pane,a:keys)
endfunction

function! s:SendKeys(keys)
    let l:cmd = g:VtrClearBeforeSend ? g:VtrClearSequence.a:keys : a:keys
    call s:_SendKeys(l:cmd)
    call s:SendEnterSequence()
endfunction

function! s:SendKeysRaw(keys)
  if !s:ValidRunnerPaneSet() | return | endif
  call s:_SendKeys(a:keys)
endfunction

function! s:SendCtrlD()
  call s:SendKeysRaw('')
endfunction

function! s:SendCtrlC()
  call s:SendKeysRaw('')
endfunction

function! s:SendEnterSequence()
    call s:_SendKeys("Enter")
endfunction

function! s:SendClearSequence()
    if !s:ValidRunnerPaneSet() | return | endif
    call s:SendTmuxCopyModeExit()
    call s:_SendKeys(g:VtrClearSequence)
endfunction

function! s:SendQuitSequence()
    if !s:ValidRunnerPaneSet() | return | endif
    call s:_SendKeys("q")
endfunction

function! s:GitCdUp()
    let s:pane_path = s:SendTmuxCommand("display-message", "-p", "'#{pane_current_path}'")
    let l:git_repo_check = "git rev-parse --git-dir > /dev/null 2>&1"
    let l:cdup_cmd = "cd './'$(git rev-parse --show-cdup)"
    let l:cmd = shellescape(join([l:git_repo_check, '&&', l:cdup_cmd]))
    call s:SendTmuxCopyModeExit()
    call s:SendKeys(l:cmd)
    call s:SendClearSequence()
endfunction

function! s:FocusVimPane()
    call s:FocusTmuxPane(s:vim_pane)
endfunction

function! s:LastWindowNumber()
    return split(s:SendTmuxCommand("list-windows"), '\n')[-1][0]
endfunction

function! s:ToggleOrientationVariable()
    let s:vtr_orientation = (s:vtr_orientation == "v" ? "h" : "v")
endfunction

function! s:BreakRunnerPaneToTempWindow()
    call s:SendTmuxCommand('break-pane', '-d', '-t', s:runner_pane)
    let s:detached_window = s:LastWindowNumber()
    let s:vim_pane = s:ActivePaneIndex()
    unlet s:runner_pane
endfunction

function! s:RunnerDimensionSpec()
    return join(["-p", s:vtr_percentage, "-".s:vtr_orientation])
endfunction

function! s:TmuxInfo(message)
  " TODO: this should accept optional target pane, default to current.
  " Pass that to TargetedCommand as "display-message", "-p '#{...}')
  return s:SendTmuxCommand("display-message -p '#{" . a:message . "}'")
endfunction

function! s:PaneCount()
  return str2nr(s:TmuxInfo('window_panes'))
endfunction

function! s:AvailableRunnerPaneIndices()
  return filter([], "v:val != " . s:ActivePaneIndex())
endfunction

function! s:AltPane()
  if s:PaneCount() == 2
    return s:AvailableRunnerPaneIndices()[0]
  else
    echoerr "AltPane only valid if two panes open"
  endif
endfunction

function! s:AttachToPane(...)
  if exists("a:1") && a:1 != ""
    call s:AttachToSpecifiedPane(a:1)
  elseif s:PaneCount() == 2
    call s:AttachToSpecifiedPane(s:AltPane())
  else
    call s:PromptForPaneToAttach()
  endif
endfunction

function! s:PromptForPaneToAttach()
  if g:VtrDisplayPaneNumbers
    call s:SendTmuxCommand('source ~/.tmux.conf && tmux display-panes')
  endif
  echohl String | let l:desired_pane = input('Pane #: ') | echohl None
  if !empty(l:desired_pane)
    call s:AttachToSpecifiedPane(l:desired_pane)
  else
    call s:EchoError("No pane specified. Cancelling.")
  endif
endfunction

function! s:CurrentMajorOrientation()
  let l:orientation_map = { '[': 'v', '{': 'h' }
  let l:layout = s:TmuxInfo('window_layout')
  let l:outermost_orientation = substitute(l:layout, '[^[{]', '', 'g')[0]
  return l:orientation_map[l:outermost_orientation]
endfunction

function! s:AttachToSpecifiedPane(desired_pane)
  let l:desired_pane = str2nr(a:desired_pane)
  if s:ValidRunnerPaneNumber(l:desired_pane)
    let s:runner_pane = l:desired_pane
    let s:vim_pane = s:ActivePaneIndex()
    let s:vtr_orientation = s:CurrentMajorOrientation()
    echohl String | echo "\rRunner pane set to: " . l:desired_pane | echohl None
  else
    call s:EchoError("Invalid pane number: " . l:desired_pane)
  endif
endfunction

function! s:EchoError(message)
  echohl ErrorMsg | echo "\rVTR: ". a:message | echohl None
endfunction

function! s:DesiredPaneExists(desired_pane)
    let l:r = s:SendTmuxCommand('list-panes','-f',"'#{==:#{pane_id},".a:desired_pane."}'")
    echo 'desired pane ='.a:desired_pane
    echo 'result = '.l:r
    call getchar()
endfunction

function! s:ValidRunnerPaneNumber(desired_pane)
  if a:desired_pane == s:ActivePaneIndex() | return 0 | endif
  if s:DesiredPaneExists(a:desired_pane) | return 0 | endif
  return 1
endfunction

function! s:ReattachPane()
    if !s:DetachedPaneAvailable() | return | endif
    let s:vim_pane = s:ActivePaneIndex()
    call s:_ReattachPane()
    call s:FocusVimPane()
    if g:VtrClearOnReattach
        call s:SendClearSequence()
    endif
endfunction

function! s:_ReattachPane()
    let l:join_cmd = join(["join-pane", "-s", ":".s:detached_window.".0",
        \ s:RunnerDimensionSpec()])
    call s:SendTmuxCommand(l:join_cmd)
    unlet s:detached_window
    let s:runner_pane = s:ActivePaneIndex()
endfunction

function! s:ReorientRunner()
    if !s:ValidRunnerPaneSet() | return | endif
    call s:BreakRunnerPaneToTempWindow()
    call s:ToggleOrientationVariable()
    call s:_ReattachPane()
    call s:FocusVimPane()
    if g:VtrClearOnReorient
        call s:SendClearSequence()
    endif
endfunction

function! s:HighlightedPrompt(prompt)
    echohl String | let l:input = shellescape(input(a:prompt)) | echohl None
    return l:input
endfunction

function! s:FlushCommand()
    if exists("s:user_command")
        unlet s:user_command
    endif
endfunction

function! s:SendTmuxCopyModeExit()
    let l:session = s:TmuxInfo('session_name')
    let l:win = s:TmuxInfo('window_index')
    let l:target_cmd = join([l:session.':'.l:win.".".s:runner_pane])
    if s:SendTmuxCommand("display-message -p -F '#{pane_in_mode}' -t " . l:target_cmd)
        call s:SendQuitSequence()
    endif
endfunction

function! s:SendCommandToRunner(ensure_pane, ...)
    if a:ensure_pane | call s:EnsureRunnerPane() | endif
    if !s:ValidRunnerPaneSet() | return | endif
    if exists("a:1") && a:1 != ""
        let s:user_command = shellescape(a:1)
    endif
    if !exists("s:user_command")
        let s:user_command = s:HighlightedPrompt(g:VtrPrompt)
    endif
    let l:escaped_empty_string = "''"
    if s:user_command == l:escaped_empty_string
        unlet s:user_command
        call s:EchoError("command string required")
        return
    endif
    call s:SendTmuxCopyModeExit()
    if g:VtrClearBeforeSend
        call s:SendClearSequence()
    endif
    call s:SendKeys(s:user_command)
endfunction

function! s:EnsureRunnerPane(...)
    if exists('s:detached_window')
        call s:ReattachPane()
    elseif exists('s:runner_pane')
        return
    else
        if exists('a:1')
            call s:CreateRunnerPane(a:1)
        else
            call s:CreateRunnerPane()
        endif
    endif
endfunction

function! s:SendLinesToRunner(ensure_pane) range
    if a:ensure_pane | call s:EnsureRunnerPane() | endif
    if !s:ValidRunnerPaneSet() | return | endif
    call s:SendTmuxCopyModeExit()
    call s:SendTextToRunner(getline(a:firstline, a:lastline))
endfunction

function! s:PrepareLines(lines)
    let l:prepared = a:lines
    if g:VtrStripLeadingWhitespace
        let l:prepared = map(a:lines, 'substitute(v:val,"^\\s*","","")')
    endif
    if g:VtrClearEmptyLines
        let l:prepared = filter(l:prepared, "!empty(v:val)")
    endif
    if g:VtrAppendNewline && len(a:lines) > 1
        let l:prepared = add(l:prepared, "\r")
    endif
    return l:prepared
endfunction

function! s:SendTextToRunner(lines)
    if !s:ValidRunnerPaneSet() | return | endif
    let l:prepared = s:PrepareLines(a:lines)
    let l:send_keys_cmd = join(['send-keys', '-t', s:runner_pane])
    for l:line in l:prepared
      let l:targeted_cmd = l:send_keys_cmd . ' ' . shellescape(l:line . "\r")
      call s:SendTmuxCommand(l:targeted_cmd)
    endfor
endfunction

function! s:SendFileViaVtr(ensure_pane)
    let l:runners = s:CurrentFiletypeRunners()
    if has_key(l:runners, &filetype)
        write
        let l:runner = l:runners[&filetype]
        let l:local_file_path = expand('%')
        let l:run_command = substitute(l:runner, '{file}', l:local_file_path, 'g')
        call VtrSendCommand(l:run_command, a:ensure_pane)
    else
        echoerr 'Unable to determine runner'
    endif
endfunction

function! s:CurrentFiletypeRunners()
    let l:default_runners = {
            \ 'elixir': 'elixir {file}',
            \ 'javascript': 'node {file}',
            \ 'python': 'python {file}',
            \ 'ruby': 'ruby {file}',
            \ 'sh': 'sh {file}'
            \ }
    if exists("g:vtr_filetype_runner_overrides")
      return extend(copy(l:default_runners), g:vtr_filetype_runner_overrides)
    else
      return l:default_runners
    endif
endfunction

function! VtrSendCommand(command, ...)
    let l:ensure_pane = 0
    if exists("a:1")
      let l:ensure_pane = a:1
    endif
    call s:SendCommandToRunner(l:ensure_pane, a:command)
endfunction

function! s:DefineCommands()
    command! -bang -nargs=? VtrSendCommandToRunner call s:SendCommandToRunner(<bang>0, <f-args>)
    command! -bang -range VtrSendLinesToRunner <line1>,<line2>call s:SendLinesToRunner(<bang>0)
    command! -bang VtrSendFile call s:SendFileViaVtr(<bang>0)
    command! -nargs=? VtrOpenRunner call s:EnsureRunnerPane(<args>)
    command! VtrKillRunner call s:KillRunnerPane()
    command! -bang VtrFocusRunner call s:FocusRunnerPane(<bang>!0)
    command! VtrReorientRunner call s:ReorientRunner()
    command! VtrDetachRunner call s:DetachRunnerPane()
    command! VtrReattachRunner call s:ReattachPane()
    command! VtrClearRunner call s:SendClearSequence()
    command! VtrFlushCommand call s:FlushCommand()
    command! VtrSendCtrlD call s:SendCtrlD()
    command! VtrSendCtrlC call s:SendCtrlC()
    command! -bang -nargs=? -bar VtrAttachToPane call s:AttachToPane(<f-args>)
    command! -nargs=1 VtrSendKeysRaw call s:SendKeysRaw(<q-args>)
endfunction

function! s:DefineKeymaps()
    if g:VtrUseVtrMaps
        nnoremap <leader>va :VtrAttachToPane<cr>
        nnoremap <leader>ror :VtrReorientRunner<cr>
        nnoremap <leader>sc :VtrSendCommandToRunner<cr>
        nnoremap <leader>sl :VtrSendLinesToRunner<cr>
        vnoremap <leader>sl :VtrSendLinesToRunner<cr>
        nnoremap <leader>or :VtrOpenRunner<cr>
        nnoremap <leader>kr :VtrKillRunner<cr>
        nnoremap <leader>fr :VtrFocusRunner<cr>
        nnoremap <leader>dr :VtrDetachRunner<cr>
        nnoremap <leader>cr :VtrClearRunner<cr>
        nnoremap <leader>fc :VtrFlushCommand<cr>
        nnoremap <leader>sf :VtrSendFile<cr>
    endif
endfunction

function! s:InitializeVariables()
    call s:InitVariable("g:VtrPercentage", 20)
    call s:InitVariable("g:VtrOrientation", "v")
    call s:InitVariable("g:VtrInitialCommand", "")
    call s:InitVariable("g:VtrGitCdUpOnOpen", 0)
    call s:InitVariable("g:VtrClearBeforeSend", 1)
    call s:InitVariable("g:VtrPrompt", "Command to run: ")
    call s:InitVariable("g:VtrUseVtrMaps", 0)
    call s:InitVariable("g:VtrClearOnReorient", 1)
    call s:InitVariable("g:VtrClearOnReattach", 1)
    call s:InitVariable("g:VtrDetachedName", "VTR_Pane")
    call s:InitVariable("g:VtrClearSequence", "")
    call s:InitVariable("g:VtrDisplayPaneNumbers", 1)
    call s:InitVariable("g:VtrStripLeadingWhitespace", 1)
    call s:InitVariable("g:VtrClearEmptyLines", 1)
    call s:InitVariable("g:VtrAppendNewline", 0)
    let s:vtr_percentage = g:VtrPercentage
    let s:vtr_orientation = g:VtrOrientation
endfunction

call s:InitializeVariables()
call s:DefineCommands()
call s:DefineKeymaps()

" vim: set fdm=marker
