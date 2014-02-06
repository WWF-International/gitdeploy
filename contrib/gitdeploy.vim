"" -- this will probably eventually be a legitimate plugin ... when I can be
"" bothered

"" contains useful functions for working with the git-deploy system

"" push the current version of the file. Will use the commit message if it is provided

if !exists('g:gitdeploy_default_msg')
  let g:gitdeploy_default_msg = "."
endif

"" setus up the current file to be used with GitDeploy
function! GitDeployInit()
	argadd %
	nnoremap <buffer> <localleader>dd :call GitDeployPush()<cr>
	nnoremap <buffer> <localleader>dm :call GitDeployPush(input("Commit message: "))<cr>
endfunction

function! GitDeployPush(...)
	let msg = g:gitdeploy_default_msg
	if a:0 > 0
		let msg = join(a:000, "\n")
	endif
	" now 'git-add' all of the files on the arg list
	argdo Gwrite
	execute "Gcommit -m '" . msg . "'"
	Git push
endfunction
