# Terminal dog: a greeting with a random fact when a terminal opens, and a mood icon in the prompt.
# The icon is shown by starship's env_var modules (PET_OK / PET_ERR / PET_ZZ / PET_HUNGRY).
# Feed it with the `pet` command (~/.local/bin/pet). Set PET_GREETING=0 to skip the greeting.

zmodload zsh/datetime

_PET_DIR=~/.local/state/pet
_PET_FACTS=${XDG_CACHE_HOME:-$HOME/.cache}/besbes/facts.txt

# Hungry when the last meal (mtime of the "fed" file) was more than 8 hours ago, or never
_pet_hungry() { local fed=($_PET_DIR/fed(Nmh-8)); (( ! $#fed )); }

_pet_precmd() {
    local s=$? h
    unset PET_OK PET_ERR PET_ZZ PET_HUNGRY
    strftime -s h %H $EPOCHSECONDS
    if (( s != 0 && s != 130 )); then  # 130 = Ctrl+C, not a real failure
        export PET_ERR="󰩃"
    elif _pet_hungry; then
        export PET_HUNGRY="󰩃 ?"
    elif (( 10#$h < 6 )); then
        export PET_ZZ="󰩃 󰒲"
    else
        export PET_OK="󰩃"
    fi
}
# Run first, so $? is still the last command's status
precmd_functions=(_pet_precmd ${precmd_functions:#_pet_precmd})

# Take one random fact out of the stock (so it doesn't repeat) and top the stock up
# in the background when it runs low. Facts are downloaded by ~/.local/bin/besbes-facts.
_pet_fact() {
    local -a facts
    [[ -r $_PET_FACTS ]] && facts=("${(@f)$(<$_PET_FACTS)}")
    facts=(${facts:#})  # drop empty lines
    if (( $#facts < 10 )); then
        ( besbes-facts refill 25 >/dev/null 2>&1 & )
    fi
    (( $#facts )) || return 1
    local i=$(( RANDOM % $#facts + 1 ))
    REPLY=$facts[i]
    print -rl -- "${(@)facts[1,i-1]}" "${(@)facts[i+1,-1]}" > $_PET_FACTS
}

# Greeting shown once when a terminal opens
_pet_greet() {
    [[ $PET_GREETING == 0 || -n $PET_GREETED || ! -t 1 ]] && return
    export PET_GREETED=1  # once per terminal, not again in nested shells

    local hour when date name
    strftime -s hour %H $EPOCHSECONDS
    strftime -s date '%A, %d %B · %I:%M %p' $EPOCHSECONDS
    if   (( 10#$hour < 5 ));  then when="working hard at night"
    elif (( 10#$hour < 12 )); then when="good morning"
    elif (( 10#$hour < 18 )); then when="good afternoon"
    else                           when="good evening"
    fi
    [[ -r $_PET_DIR/name ]] && name=$(<$_PET_DIR/name)
    name=${name:-Max}

    printf '  \e[35;1m󰩃\e[0m  \e[1m%s, boss\e[0m\n' "$when"
    printf '  \e[34m󰃭\e[0m  \e[2m%s\e[0m\n' "$date"
    _pet_hungry && printf '  \e[33m󰏩\e[0m  \e[33m%s is hungry, run \e[1mpet\e[0m\n' "$name"

    if _pet_fact; then
        printf '  \e[35m󰏩\e[0m  \e[35;1m%s found a fact:\e[0m\n' "$name"
        # Wrap to the terminal width, indented under the icon
        print -r -- "$REPLY" | fold -s -w $(( COLUMNS > 20 ? COLUMNS - 8 : 60 )) | sed 's/^/     \x1b[3m/; s/$/\x1b[0m/'
        printf '\n'
    else
        printf '  \e[35m󰏩\e[0m  \e[2m%s says woof\e[0m\n\n' "$name"
    fi
}
_pet_greet
