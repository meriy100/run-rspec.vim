"
" Custmizable variables
"
" * g:run_rspec_bin
"
" Set path to rspec binary
" Ex)
" let g:run_rspec_bin = 'bin/rspec'
" let g:run_rspec_bin = 'bundle exec rspec'
" let g:run_rspec_bin = 'spring rspec'
"
if !exists('g:run_rspec_bin')
  let g:run_rspec_bin = 'rspec'
endif

"
" * g:run_rspec_command_option
"
" Set additional rspec options
" Ex)
" let g:run_rspec_command_option = '--only-failure'
"
" NOTICE:
" -c --color, -f --format options will be ignored.
"
if !exists('g:run_rspec_command_option')
  let g:run_rspec_command_option = ''
endif

"
" * g:run_rspec_src_dir
"
" Set the directory where src files are
" Ex)
" let g:run_rspec_src_dir = 'src'
"
if !exists('g:run_rspec_src_dir')
  let g:run_rspec_src_dir = 'app'
endif

"
" * g:run_rspec_spec_dir
"
" Set the directory where spec files are
" Ex)
" let g:run_rspec_spec_dir = 'extra_spec'
"
if !exists('g:run_rspec_spec_dir')
  let g:run_rspec_spec_dir = 'spec'
endif

"
" * g:run_rspec_result_lines
"
" Set number of the result buffer lines
" Ex)
" let g:run_rspec_result_lines = 20
"
if !exists('g:run_rspec_result_lines')
  let g:run_rspec_result_lines = 15
endif


let s:FALSE = 0
let s:TRUE = !s:FALSE
let s:NOT_FOUND = -1

let s:result_buffer = 'RunRspecResult'
let s:last_full_cmd = ''

function! runrspec#rspec_current_file()
  let filepath = s:get_current_filepath()
  if !s:validate_spec_file(filepath)
    let filepath = s:detect_spec_filepath()
    if filepath == ''
      call s:show_error("Not found a spec file.")
      return
    endif
    call s:show_info("Auto detected the spec file - " . filepath)
  endif
  call s:do_rspec(s:build_full_cmd(filepath))
endfunction

function! runrspec#rspec_current_line()
  let filepath = s:get_current_filepath()
  if !s:validate_spec_file(filepath)
    call s:show_error('This is not a rspec file.')
    return
  endif
  let linenum = getpos('.')[1]
  call s:do_rspec(s:build_full_cmd_with_linenum(filepath, linenum))
endfunction

function! runrspec#rspec_last_run()
  if s:last_full_cmd == ''
    call s:show_warning('Nothing to re-run! You have not run any rspec yet.')
    return
  endif
  call s:do_rspec(s:last_full_cmd)
endfunction

function! runrspec#close_result_window()
  if !exists('s:result_window_number')
    call s:show_warning('Result window is not opened.')
    return
  endif
  silent execute s:result_window_number 'wincmd w'
  normal q
endfunction


function! s:get_current_filepath()
  return expand('%:p')
endfunction

function! s:detect_spec_filepath()
  let filename = substitute(expand('%:t'), '\.rb', '_spec.rb', '')
  let dir = substitute(substitute(expand('%:p'), g:run_rspec_src_dir, g:run_rspec_spec_dir, ''), expand('%:t'), '', '')
  return findfile(filename, dir)
endfunction

function! s:validate_spec_file(filepath)
  if a:filepath !~? '.*_spec\.rb$'
    return s:FALSE
  endif
  return s:TRUE
endfunction

function! s:build_full_cmd(filepath)
  return join([
        \ g:run_rspec_bin,
        \ g:run_rspec_command_option,
        \ '--no-colour --format progress',
        \ a:filepath,
        \ ], ' ')
endfunction

function! s:build_full_cmd_with_linenum(filepath, linenum)
  return s:build_full_cmd(a:filepath) . ':' . a:linenum
endfunction

function! s:do_rspec(full_cmd)
  " prepare result buffer
  if bufexists(s:result_buffer)
    silent execute 'bw!' s:result_buffer
  endif
  silent execute 'botright' 'new'
  silent execute 'edit' s:result_buffer
  silent setlocal buftype=nofile
  silent setlocal syntax=rspecresult
  let s:result_window_number = winnr()

  " run rspec
  if has('channel')
    let job = job_start(a:full_cmd, {
          \ 'out_io': 'buffer',
          \ 'out_name': s:result_buffer,
          \ 'out_modifiable': 0,
          \ 'err_io': 'buffer',
          \ 'err_name': s:result_buffer,
          \ 'err_modifiable': 0
          \ })
    silent setlocal nobuflisted
    silent execute 'resize' g:run_rspec_result_lines
    execute ':normal i' . 'Running spec...'
  elseif has('nvim')
    let job = job_start(a:full_cmd, {
          \ 'out_io': 'buffer',
          \ 'out_name': s:result_buffer,
          \ 'out_modifiable': 0,
          \ 'err_io': 'buffer',
          \ 'err_name': s:result_buffer,
          \ 'err_modifiable': 0
          \ })
    silent setlocal nobuflisted
    silent execute 'resize' g:run_rspec_result_lines
    execute ':normal i' . 'Running spec...'
  else
    silent execute 'r!' a:full_cmd
    silent setlocal nobuflisted nomodifiable readonly
    silent execute 'resize' g:run_rspec_result_lines
    normal gg
  endif
  let s:last_full_cmd = a:full_cmd

  " map in result buffer
  nnoremap <silent> <buffer> q :q<BAR>:wincmd p<CR>
  nnoremap <silent> <buffer> <CR> :call <SID>open_file()<CR>
  nnoremap <silent> <buffer> e    :call <SID>open_file()<CR>:call runrspec#close_result_window()<CR>
  nnoremap <buffer> n /^\s\+[0-9][0-9]*)<CR>
  nnoremap <buffer> p ?^\s\+[0-9][0-9]*)<CR>
endfunction

function! s:open_file()
  let filepath_with_linenum = s:search_spec_file_with_linenum()
  if filepath_with_linenum == ''
    call s:show_warning('Not found spec file path.')
    return
  endif
  let [filepath, linenum] = s:split_into_path_and_linenum(filepath_with_linenum)
  if !s:back_to_spec_window(filepath, linenum)
    call s:open_spec_in_previous_window(filepath, linenum)
  endif
endfunction

function! s:search_spec_file_with_linenum()
  let pattern = '\S\+_spec\.rb:[0-9]\+'
  " \zs$ : Hit at the end of line to include the current line.
  call search(pattern . '.*\zs$', 'csW')
  let result = matchstr(getline('.'), pattern)
  " Get back to the position marked when searching.
  if result != ''
    normal `'
  end
  return result
endfunction

function! s:split_into_path_and_linenum(filepath_with_linenum)
  let [filepath, linenum] = split(a:filepath_with_linenum, ':')
  let trimed_filepath = substitute(filepath, '^\./', '', '')
  return [trimed_filepath, linenum]
endfunction

function! s:back_to_spec_window(filepath, linenum)
  let winnum = s:find_winnum(a:filepath)
  if winnum != s:NOT_FOUND
    silent execute winnum 'wincmd w'
    call cursor(a:linenum, 1)
    return s:TRUE
  endif
  return s:FALSE
endfunction

function! s:open_spec_in_previous_window(filepath, linenum)
  silent wincmd p
  silent execute 'e' a:filepath
  call cursor(a:linenum, 1)
endfunction

function! s:find_winnum(filepath)
  for i in range(1, winnr('$'))
    let bname = bufname(winbufnr(i))
    if match(bname, a:filepath) > s:NOT_FOUND
      return i
    endif
  endfor
  return s:NOT_FOUND
endfunction

function! s:show_error(message)
  echohl ErrorMsg | echo '[run-rspec] ' . a:message | echohl None
endfunction

function! s:show_warning(message)
  echohl WarningMsg | echo '[run-rspec] ' . a:message | echohl None
endfunction

function! s:show_info(message)
  echo '[run-rspec] ' . a:message
endfunction
