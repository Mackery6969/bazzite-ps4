#!/usr/bin/bash
# Shared by install-ps4.sh and build-ps4-image.sh: deploy the bazzite-ps4
# image with bootc onto a mounted ext4 filesystem and add the PS4 boot shim.
#
#   deploy_ps4 <mountpoint> <filesystem-uuid> <image> <target-imgref>

deploy_ps4() {
    local mnt="$1" uuid="$2" image="$3" target_imgref="$4"

    run_image() {
        sudo podman run --rm --privileged --pid=host \
            --security-opt label=type:unconfined_t \
            -v /var/lib/containers:/var/lib/containers \
            -v /dev:/dev \
            -v "${mnt}:/target" \
            "${image}" "$@"
    }

    # bootc requires UUID= mount specs; the PS4 boot shim ignores them anyway
    run_image bootc install to-filesystem \
        --bootloader none \
        --skip-finalize \
        --root-mount-spec "UUID=${uuid}" \
        --boot-mount-spec "UUID=${uuid}" \
        --target-imgref "${target_imgref}" \
        /target

    # bootc writes a /boot mount for the boot spec, but /boot is a plain
    # directory on the same filesystem; left in fstab it sends boot to
    # emergency mode
    run_image bash -c 'sed -i "\| /boot |d" /target/ostree/deploy/*/deploy/*/etc/fstab'

    run_image /usr/libexec/bazzite-ps4/sync-init /target
}

# Optionally preconfigure WiFi in the deployment, so the console comes up
# online without a keyboard. Prompts on the terminal; the password is only
# written into this install, never into the published image.
#
#   add_wifi_ps4 <mountpoint>
add_wifi_ps4() {
    local mnt="$1" answer ssid user pass etc conn

    [[ -t 0 ]] || return 0
    read -r -p "Preconfigure a WiFi network for the PS4? [y/N] " answer
    [[ "${answer,,}" == y* ]] || return 0

    read -r -p "  Network name (SSID): " ssid
    read -r -p "  Username (leave empty for home WiFi): " user
    read -r -s -p "  Password: " pass
    echo
    [[ -n "${ssid}" && -n "${pass}" ]] || { echo "  Skipping WiFi: name and password are required."; return 0; }

    conn="[connection]
id=${ssid}
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=${ssid}
"
    if [[ -z "${user}" ]]; then
        conn+="
[wifi-security]
key-mgmt=wpa-psk
psk=${pass}
"
    else
        conn+="
[wifi-security]
key-mgmt=wpa-eap

[802-1x]
eap=peap;
identity=${user}
password=${pass}
phase2-auth=mschapv2
"
    fi
    conn+="
[ipv4]
method=auto

[ipv6]
method=auto
"

    for etc in "${mnt}"/ostree/deploy/*/deploy/*/etc; do
        sudo install -d -m 0700 "${etc}/NetworkManager/system-connections"
        printf '%s' "${conn}" | sudo install -m 0600 /dev/stdin \
            "${etc}/NetworkManager/system-connections/ps4-wifi.nmconnection"
    done
    echo "  WiFi '${ssid}' added."
}
