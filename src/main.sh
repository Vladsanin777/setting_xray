source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.setting.sh"

key-gen-xray() {
    local keys=$(xray x25519) || { \
        echo "FATEL_ERROR: failed to generate keys"; \
        exit -1; }

    local priv=$(echo "$keys" | awk '/PrivateKey:/ {print $2}')
    local pub=$(echo "$keys" | awk '/Password:/ {print $2}')

    local sid=$(openssl rand -hex 8) || { \
        echo "FATEL_ERROR: failed to generate sid"; \
        exit -1; }

    echo "PrivateKey: $priv" > "$KEYS_PATH"
    echo "Password: $pub" >> "$KEYS_PATH"
    echo "shortsid: $sid" >> "$KEYS_PATH"

    # Update private key in config xray
    jq --arg priv "$priv" --arg sid "$sid" \
        '.inbounds[0].streamSettings.realitySettings.privateKey = $priv | .inbounds[0].streamSettings.realitySettings.shortIds = [$sid]' \
        "$CONFIG_PATH" > tmp.json && mv tmp.json "$CONFIG_PATH"
}

# $1 - username
info-user-xray() {
    jq --arg email "$1" '.inbounds[0].settings.clients[] | select(.email == $email)' "${CONFIG_PATH}"
}

# $1 - username
is-user-xray() {
    local user_data=$(info-user-xray $1)
    if [[ -n "$user_data" ]]; then
        echo 1; return
    fi
    echo 0
}

restart-xray() {
    sudo systemctl restart xray
}

start-xray() {
    sudo systemctl start xray
}

stop-xray() {
    sudo systemctl stop xray
}

enable-xray() {
    sudo systemctl enable --now xray
}

disable-xray() {
    sudo systemctl disable --now xray
}

status-xray() {
    sudo systemctl status xray
}

# $1 - username
print-link-for-user-xray() {
    if [ ! -s "$KEYS_PATH" ]; then
        echo "WARNING: Generating new keys for the server."
        key-gen-xray
    fi

    if [[ "$(is-user-xray "$1")" -ne "1" ]]; then
        echo "ERROR: Username ${1} is invalid."
        return 1
    fi

    local protocol=$(jq -r '.inbounds[0].protocol' "$CONFIG_PATH")
    local port=$(jq -r '.inbounds[0].port' "$CONFIG_PATH")

    local uuid=$(jq -r --arg email "${1}" \
        '.inbounds[0].settings.clients[] | select(.email == $email) | .id' \
        "$CONFIG_PATH")
    
    local pbk=$(awk -F': ' '/Password/ {print $2}' "$KEYS_PATH")
    local sid=$(awk -F': ' '/shortsid/ {print $2}' "$KEYS_PATH")
    local sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_PATH")
    local ip=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')

    local security=$(jq -r '.inbounds[0].streamSettings.security' "${CONFIG_PATH}")
    local flow=$(jq -r --arg email "$1" '.inbounds[0].settings.clients[] | select(.email == $email) | .flow // ""' "$CONFIG_PATH")
    local path="/"
    local spx="/"
    local fake=$(jq -r '.inbounds[0].streamSettings.network' "${CONFIG_PATH}")

    local params=()
    [[ -n "$security" ]] && params+=(--data-urlencode "security=$security")
    [[ -n "$flow" ]]     && params+=(--data-urlencode "flow=$flow")
    [[ -n "$sni" ]]      && params+=(--data-urlencode "sni=$sni")
    [[ -n "$pbk" ]]      && params+=(--data-urlencode "pbk=$pbk")
    [[ -n "$sid" ]]      && params+=(--data-urlencode "sid=$sid")
    [[ -n "$fake" ]]     && params+=(--data-urlencode "type=$fake")
    
    params+=(--data-urlencode "fp=chrome")
    params+=(--data-urlencode "path=/")
    params+=(--data-urlencode "spx=/")

    local query_string=$(curl -Gso /dev/null -w "%{url_effective}" "${params[@]}" "http://localhost" | cut -d'?' -f2)

    local fragment=$(curl -Gso /dev/null -w "%{url_effective}" --data-urlencode "$1" "http://localhost" | cut -d'?' -f2 | sed 's/^.*=//')

    local link="${protocol}://${uuid}@${ip}:${port}?${query_string}#${fragment}"

    echo -e "\nLink for client: \n${link}"
}

# $1 - username
new-user-xray-row() {
    local uuid=$(xray uuid)
    jq --arg email "$1" --arg uuid "$uuid" \
        '.inbounds[0].settings.clients += [{"email": $email, "id": $uuid, "flow": "xtls-rprx-vision"}]' \
        "$CONFIG_PATH" > tmp.json && mv tmp.json "$CONFIG_PATH"
}

new-user-xray() {
    read -p "Enter username: " username
    
    if [[ -z "$username" ]]; then
        echo "ERROR: Enter username is empty."
        return 1
    elif [[ "$(is-user-xray $username)" -eq "1" ]]; then
        echo "ERROR: Enter username is exists."
        return 1
    fi

    new-user-xray-row "${username}"

    restart-xray

    print-link-for-user-xray "${username}"
}

create-symlinks-xray() {
    chmod +x "${FULL_NAME_MAIN_SH}"

    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/create-symlinks"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/disable-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/enable-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/include-qf-bbr-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/info-user-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/install-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/is-user-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/key-gen-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/new-user-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/new-user-xray-row"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/print-link-for-user-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/remove-symlinks-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/remove-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/remove-utils-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/restart-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/setting-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/setting-utils-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/show-all-users-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/start-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/status-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/stop-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/update-beta-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/update-utils-xray"
    sudo -E ln -sf "${FULL_NAME_MAIN_SH}" "${PLACE_SYMLINKS}/update-xray"
    sudo -E ln -sf "${KEYS_PATH}" "${KEYS_SYMLINK}"
    sudo -E ln -sf "${CONFIG_PATH}" "${CONFIG_SYMLINK}"
}

install-xray() {
    sudo bash -c "$(curl -4 -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
}

update-xray() {
    remove-xray
    install-xray
}

update-beta-xray() {
    remove-xray
    install-beta-xray
}

install-beta-xray() {
    sudo bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --beta
}

remove-xray() {
    sudo bash -c "$(curl -4 -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove
}

setting-xray() {
    install-xray
    include-qf-bbr-xray
    key-gen-xray
    enable-xray
}

install-depens-xray() {
    sudo apt-get update && sudo apt-get install -y ${PACKAGES} || \
    sudo dnf install -y ${PACKAGES} || sudo yum install -y ${PACKAGES} || \
    sudo pacman -Syu --noconfirm ${PACKAGES} ||\
    sudo zypper install -y ${PACKAGES} || \
    sudo apk add ${PACKAGES} || \
    { echo "ERROR: not install depens."; return -1; }
}

setting-utils-xray() {
    install-depens-xray
    setting-xray
    create-symlinks-xray
}


update-utils-xray() {
    sudo cd "${OPT_UTILS_XRAY}" || \
        git checkout master --force || \
        git pull || setting-utils-xray
}

remove-symlinks-xray() {
    sudo -E unlink "${PLACE_SYMLINKS}/create-symlinks"
    sudo -E unlink "${PLACE_SYMLINKS}/disable-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/enable-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/include-qf-bbr-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/info-user-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/install-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/is-user-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/key-gen-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/new-user-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/new-user-xray-row"
    sudo -E unlink "${PLACE_SYMLINKS}/print-link-for-user-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/remove-symlinks-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/remove-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/remove-utils-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/restart-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/setting-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/setting-utils-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/show-all-users-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/start-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/status-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/stop-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/update-beta-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/update-utils-xray"
    sudo -E unlink "${PLACE_SYMLINKS}/update-xray"
    sudo -E unlink "${KEYS_SYMLINK}"
    sudo -E unlink "${CONFIG_SYMLINK}"
}

remove-utils-xray() {
    remove-symlinks-xray
    rm -rf "${OPT_UTILS_XRAY}"
}

include-bbr-xray() {
    echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
}

include-fq-xray() {
    echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
}

include-qf-bbr-xray() {
    sysctl -n net.core.default_qdisc 2>null | grep -q "fq" && \
        echo "WARNING: FQ is already on" || include-fq-xray

    sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null | \
        grep -q "bbr" && echo "WARNING: BBR is already on." || include-bbr-xray

    sudo sysctl -p || { echo "FATEL_ERROR: Failed to apply sysctl settings"; return 1; }

    echo "SUCCESS: FQ and BBR are configured."
}

show-all-users-xray() {
    [ ! -f "$CONFIG_PATH" ] && { echo "ERROR: config file not found"; return 1; }
    jq -r '.inbounds[0].settings.clients[].email' $CONFIG_PATH | \
    { awk '{ printf "%d) %s\t", NR, $0 }'; echo; }
}

work-syslink() {
    local func=$(basename "${0}")

    [ "${func}" = "${FUNCNAME[0]}" ] && { echo "ERROR: Dead symlink ${0}"; return 1; }

    command -v "${func}" >/dev/null 2>&1 && { ${func} ${@}; return "${?}"; }

    [ "${func}" = "main.sh" ] && { setting-utils-xray "${@}"; return "${?}"; }

    echo "WARNING: Not found function ${func}." >&2

    return 1
}

work-syslink "${@}"
