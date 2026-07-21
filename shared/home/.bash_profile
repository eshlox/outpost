# Login shells (box sh runs `bash -lc`): load ~/.profile then ~/.bashrc, so the
# interactive setup in .bashrc applies even on a login shell.
[ -f ~/.profile ] && . ~/.profile
[ -f ~/.bashrc ]  && . ~/.bashrc
