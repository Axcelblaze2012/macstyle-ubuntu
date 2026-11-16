# MacStyle Ubuntu — Zsh integrations
# Oh My Zsh manages autosuggestions and syntax highlighting separately.

# FZF: Ctrl+R history, Ctrl+T files, Alt+C directories.
if (( $+commands[fzf] )); then
  export FZF_DEFAULT_OPTS='--color=16 --height=45% --layout=reverse --border=rounded --info=inline-right'
  source <(fzf --zsh)
fi

# Zoxide: smart directory navigation.
if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi

# LSD: enhanced directory listings.
# Preserve plain output in Claude Code environments.
if (( $+commands[lsd] )) && [[ -z $CLAUDECODE ]]; then
  alias ls='lsd'
  alias ll='lsd -l'
  alias la='lsd -A'
  alias lla='lsd -lA'
  alias lt='lsd --tree --depth=2'
fi
