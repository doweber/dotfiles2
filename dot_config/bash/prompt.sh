# Bash prompt with git branch + dirty marker.
# __git_ps1 comes from git's own prompt script.
for f in /usr/share/git/completion/git-prompt.sh /usr/share/git-core/contrib/completion/git-prompt.sh /usr/lib/git-core/git-sh-prompt; do
  [ -r "$f" ] && . "$f" && break
done
command -v __git_ps1 >/dev/null || __git_ps1() { :; }

parse_git_dirty() {
  [[ -n $(git status -s 2> /dev/null | grep -v ^# | grep -v "working directory clean") ]] && echo "*"
}

export PS1='\u:\w$(__git_ps1 "[\[\e[0;32m\]%s\[\e[0m\]\[\e[0;33m\]$(parse_git_dirty)\[\e[0m\]]")$ '
export PROMPT_COMMAND='PS1=$PS1; echo -ne "\033]0;`hostname -s`:`pwd`\007"'
