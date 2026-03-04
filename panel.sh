#!/usr/bin/env bash

# admin_panel.sh — Interactive user-management panel

# Usage: sudo admin_panel.sh

# Sudoers: operator ALL=(root) NOPASSWD: /usr/local/sbin/admin_panel.sh

set -u

# ── Configuration ─────────────────────────────────────────────────────────────

ALLOWED_USERNAME_RE=’^[a-z_]{1,30}$’

# Only groups listed here can ever be assigned. If it is not in this list,

# it cannot be used — no exceptions.

ALLOWED_GROUPS=(developers docker sudo_limited backup monitoring)

DEFAULT_SHELL=”/bin/bash”
HOME_BASE=”/home”
TRANSFER_SOURCE=”/opt/shared_files”  # root-only source directory

INVOKED_BY=”${SUDO_USER:-${USER}}”

# ── Colours ───────────────────────────────────────────────────────────────────

RED=’\033[0;31m’; GREEN=’\033[0;32m’; YELLOW=’\033[1;33m’
CYAN=’\033[0;36m’; BOLD=’\033[1m’; DIM=’\033[2m’; RESET=’\033[0m’

# ── Helpers ───────────────────────────────────────────────────────────────────

info() { echo -e “${GREEN}$*${RESET}”; }
warn() { echo -e “${YELLOW}$*${RESET}”; }
err()  { echo -e “${RED}$*${RESET}”; }
sep()  { echo -e “${CYAN}$(printf ‘─%.0s’ {1..72})${RESET}”; }

pause() { echo; read -rp “  Press Enter to continue…”; }

# Reads /etc/shadow and sets two plain variables:

# ACCOUNT_LOCKED  — yes / no

# ACCOUNT_PWD     — yes / no

# 

# Shadow password field:

# !! / ! / empty  → no password, not explicitly locked

# !<hash>         → explicitly locked (had a real password before)

# <hash>          → active, has a password

account_info() {
local user=”$1”
local shadow_pass
shadow_pass=$(getent shadow “$user” 2>/dev/null | cut -d: -f2)

if [[ -z “$shadow_pass” || “$shadow_pass” == “!!” || “$shadow_pass” == “!” ]]; then
ACCOUNT_LOCKED=“no”
ACCOUNT_PWD=“no”
elif [[ “$shadow_pass” == !* ]]; then
ACCOUNT_LOCKED=“yes”
ACCOUNT_PWD=“yes”
else
ACCOUNT_LOCKED=“no”
ACCOUNT_PWD=“yes”
fi
}

# ── 1. List users ─────────────────────────────────────────────────────────────

do_list() {
echo
sep
echo -e “${BOLD}  Users (UID 1000-60000)${RESET}”
sep
printf “  ${BOLD}%-18s %-7s %-7s %-5s %-22s %s${RESET}\n” “USERNAME” “UID” “LOCKED” “PWD” “COMMENT” “GROUPS”
echo -e “${DIM}$(printf ‘╌%.0s’ {1..72})${RESET}”

while IFS=: read -r uname _ uid _ comment _ _; do
if (( uid >= 1000 && uid < 60000 )); then
grps=$(id -Gn “$uname” 2>/dev/null | tr ’ ’ ‘,’)

```
  ACCOUNT_LOCKED="" ACCOUNT_PWD=""
  account_info "$uname"

  if [[ "$ACCOUNT_LOCKED" == "yes" ]]; then
    locked_col="${RED}yes${RESET}   "
  else
    locked_col="${GREEN}no${RESET}    "
  fi

  if [[ "$ACCOUNT_PWD" == "yes" ]]; then
    pwd_col="${GREEN}yes${RESET}"
  else
    pwd_col="${YELLOW}no${RESET} "
  fi

  printf "  %-18s %-7s " "$uname" "$uid"
  printf "%b " "$locked_col"
  printf "%b  " "$pwd_col"
  printf "%-22s %s\n" "${comment:0:21}" "$grps"
fi
```

done < /etc/passwd
sep
}

# ── 2. Create user ────────────────────────────────────────────────────────────

do_create() {
echo
sep
echo -e “${BOLD}  Create New User${RESET}”
sep

# — username

local username=””
while true; do
echo -n “  Username: “
read -r username
if [[ -z “$username” ]]; then
warn “Username cannot be empty.”
elif ! [[ “$username” =~ $ALLOWED_USERNAME_RE ]]; then
warn “Invalid username. Use lowercase letters, digits, - or _. Max 31 chars.”
elif id “$username” &>/dev/null; then
warn “User ‘$username’ already exists.”
else
break
fi
done

# — comment

local comment=””
while true; do
echo -n “  Full name / comment (optional, press Enter to skip): “
read -r comment
if [[ “$comment” =~ [^[:print:]] ]]; then
warn “Comment contains invalid characters. Use printable characters only.”
else
break
fi
done

# Strip colons — they are the /etc/passwd field delimiter and would corrupt it

comment=”${comment//:/}”

# — groups

echo
echo “  Available groups:”
local i=1
for g in “${ALLOWED_GROUPS[@]}”; do
echo “    $i) $g”
(( i++ ))
done
echo “  Enter group numbers separated by spaces, or press Enter to skip:”
echo -n “  Selection: “
local group_input=””
read -r group_input

local selected_groups=()
for token in $group_input; do
if [[ “$token” =~ ^[0-9]+$ ]] && (( token >= 1 && token <= ${#ALLOWED_GROUPS[@]} )); then
selected_groups+=(”${ALLOWED_GROUPS[$((token-1))]}”)
else
warn “Ignoring invalid group selection: $token”
fi
done

# — confirm

echo
sep
echo “    Username : $username”
echo “    Comment  : ${comment:-(none)}”
echo “    Groups   : ${selected_groups[*]:-(none)}”
echo “    Shell    : $DEFAULT_SHELL”
sep
echo
echo “  Confirm?”
echo “    1) Yes — create user”
echo “    2) No  — cancel”
echo -n “  Choice: “
local confirm=””
read -r -n 1 confirm
echo
if [[ “$confirm” != “1” ]]; then
warn “Cancelled.”
return
fi

# — run useradd

if [[ -n “$comment” ]]; then
useradd -m -d “${HOME_BASE}/${username}” -s “$DEFAULT_SHELL” -c “$comment” “$username” || { err “useradd failed.”; return; }
else
useradd -m -d “${HOME_BASE}/${username}” -s “$DEFAULT_SHELL” “$username” || { err “useradd failed.”; return; }
fi
info “User ‘$username’ created.”

# — add groups

local gcsv=“none”
local g
for g in “${selected_groups[@]}”; do
getent group “$g” &>/dev/null || groupadd “$g”
if usermod -aG “$g” “$username”; then
info “Added to group: $g”
[[ “$gcsv” == “none” ]] && gcsv=”$g” || gcsv=”$gcsv,$g”
else
err “Failed to add to group: $g”
fi
done

# — optional password

echo
echo “  Set a password now?”
echo “    1) Yes — set password interactively”
echo “    2) No  — skip (account will be locked until a password is set)”
echo -n “  Choice: “
local pwchoice=””
read -r -n 1 pwchoice
echo
if [[ “$pwchoice” == “1” ]]; then
passwd “$username”
info “Password set. Account is ready.”
else
info “Skipped. Account is locked until a password is assigned.”
fi
}

# ── 3. Lock / Unlock ──────────────────────────────────────────────────────────

do_lock_unlock() {
echo
sep
echo -e “${BOLD}  Lock / Unlock Account${RESET}”
sep

local username=””
while true; do
echo -n “  Username: “
read -r username
if [[ -z “$username” ]]; then
warn “Username cannot be empty.”
elif ! [[ “$username” =~ $ALLOWED_USERNAME_RE ]]; then
warn “Invalid username.”
elif ! id “$username” &>/dev/null; then
warn “User ‘$username’ does not exist.”
else
break
fi
done

ACCOUNT_LOCKED=”” ACCOUNT_PWD=””
account_info “$username”
echo -e “  Locked : $ACCOUNT_LOCKED”
echo -e “  Has pwd: $ACCOUNT_PWD”
echo
echo “  Action:”
echo “    1) Lock account”
echo “    2) Unlock account”
echo -n “  Choice: “
local choice=””
read -r -n 1 choice
echo

if [[ “$choice” == “1” ]]; then
if usermod -L “$username”; then
info “Account ‘$username’ locked.”
else
err “Failed to lock account.”
fi
elif [[ “$choice” == “2” ]]; then
if usermod -U “$username”; then
info “Account ‘$username’ unlocked.”
else
err “Failed to unlock account.”
fi
else
warn “Invalid choice. Cancelled.”
fi
}

# ── 4. Add to group ───────────────────────────────────────────────────────────

do_addgroup() {
echo
sep
echo -e “${BOLD}  Add User to Group(s)${RESET}”
sep

local username=””
while true; do
echo -n “  Username: “
read -r username
if [[ -z “$username” ]]; then
warn “Username cannot be empty.”
elif ! [[ “$username” =~ $ALLOWED_USERNAME_RE ]]; then
warn “Invalid username.”
elif ! id “$username” &>/dev/null; then
warn “User ‘$username’ does not exist.”
else
break
fi
done

echo
echo “  Available groups:”
local i=1
for g in “${ALLOWED_GROUPS[@]}”; do
echo “    $i) $g”
(( i++ ))
done
echo “  Enter group numbers separated by spaces:”
echo -n “  Selection: “
local group_input=””
read -r group_input

if [[ -z “$group_input” ]]; then
warn “No groups selected. Cancelled.”
return
fi

local g token
for token in $group_input; do
if [[ “$token” =~ ^[0-9]+$ ]] && (( token >= 1 && token <= ${#ALLOWED_GROUPS[@]} )); then
g=”${ALLOWED_GROUPS[$((token-1))]}”
getent group “$g” &>/dev/null || groupadd “$g”
if usermod -aG “$g” “$username”; then
info “Added ‘$username’ to group: $g”
else
err “Failed to add to group: $g”
fi
else
warn “Ignoring invalid selection: $token”
fi
done
}

# ── 5. Password ───────────────────────────────────────────────────────────────

do_passwd() {
echo
sep
echo -e “${BOLD}  Set / Reset Password${RESET}”
sep

local username=””
while true; do
echo -n “  Username: “
read -r username
if [[ -z “$username” ]]; then
warn “Username cannot be empty.”
elif ! [[ “$username” =~ $ALLOWED_USERNAME_RE ]]; then
warn “Invalid username.”
elif ! id “$username” &>/dev/null; then
warn “User ‘$username’ does not exist.”
else
break
fi
done

echo
echo “  What would you like to do?”
echo “    1) Set password interactively”
echo “    2) Force reset on next login (expire password)”
echo -n “  Choice: “
local choice=””
read -r -n 1 choice
echo

if [[ “$choice” == “1” ]]; then
info “You will be prompted to enter the password twice:”
passwd “$username”
info “Password updated for ‘$username’.”
elif [[ “$choice” == “2” ]]; then
if passwd -e “$username”; then
info “Password expired. ‘$username’ must set a new one at next login.”
else
err “Failed to expire password.”
fi
else
warn “Invalid choice. Cancelled.”
fi
}

# ── 6. Delete user ────────────────────────────────────────────────────────────

do_delete() {
echo
sep
echo -e “${BOLD}  Delete User${RESET}”
sep

local username=””
while true; do
echo -n “  Username: “
read -r username
if [[ -z “$username” ]]; then
warn “Username cannot be empty.”
elif ! [[ “$username” =~ $ALLOWED_USERNAME_RE ]]; then
warn “Invalid username.”
elif ! id “$username” &>/dev/null; then
warn “User ‘$username’ does not exist.”
else
local uid
uid=$(id -u “$username”)
if (( uid < 1000 )); then
err “Cannot delete ‘$username’ — only regular user accounts (UID >= 1000) can be deleted.”
else
break
fi
fi
done

echo
echo -e “  ${RED}This will permanently delete ‘$username’ and their home directory.${RESET}”
echo
echo “  Are you sure?”
echo “    1) Yes — delete user and home directory”
echo “    2) No  — cancel”
echo -n “  Choice: “
local confirm=””
read -r -n 1 confirm
echo
if [[ “$confirm” != “1” ]]; then
warn “Cancelled.”
return
fi

if userdel -r “$username” 2>/dev/null; then
info “User ‘$username’ deleted.”
else
err “Failed to delete ‘$username’.”
fi
}

# ── 7. Transfer files ─────────────────────────────────────────────────────────

do_transfer() {
echo
sep
echo -e “${BOLD}  Transfer Files${RESET}”
sep

local username=”$INVOKED_BY”
local dest=”${HOME_BASE}/${username}”

# Sanity checks before showing the user anything

if ! id “$username” &>/dev/null; then
err “Invoking user ‘$username’ does not exist as a system account.”
return
fi

if [[ ! -d “$TRANSFER_SOURCE” ]]; then
err “Source directory does not exist: $TRANSFER_SOURCE”
return
fi

if [[ ! -r “$TRANSFER_SOURCE” ]]; then
err “Source directory is not readable: $TRANSFER_SOURCE”
return
fi

# — confirm

echo “    User        : $username”
echo “    Source      : $TRANSFER_SOURCE”
echo “    Destination : $dest”
echo “    Ownership   : ${username}:${username}”
echo
echo “  Confirm?”
echo “    1) Yes — copy and transfer ownership”
echo “    2) No  — cancel”
echo -n “  Choice: “
local confirm=””
read -r -n 1 confirm
echo
if [[ “$confirm” != “1” ]]; then
warn “Cancelled.”
return
fi

# — copy

if cp -r “$TRANSFER_SOURCE” “$dest”; then
info “Files copied to $dest.”
else
err “Copy failed.”
return
fi

# — transfer ownership

local srcname
srcname=$(basename “$TRANSFER_SOURCE”)
if chown -R “${username}:${username}” “${dest}/${srcname}”; then
info “Ownership transferred to ${username}.”
else
err “Copy succeeded but chown failed. Check ownership manually.”
fi
}

# ── Main menu ─────────────────────────────────────────────────────────────────

# Only run the menu when executed directly — not when sourced by the test suite.

[[ “${BASH_SOURCE[0]}” != “$0” ]] && return

[[ $EUID -eq 0 ]] || { echo “Run as root (use sudo).”; exit 1; }

while true; do
clear
sep
echo -e “${BOLD}   User Management Panel${RESET}”
sep
echo “   1)  List users”
echo “   2)  Create user”
echo “   3)  Lock / Unlock account”
echo “   4)  Add user to group(s)”
echo “   5)  Set / Reset password”
echo “   6)  Delete user”
echo “   7)  Transfer files to user”
sep
echo “   0)  Exit”
sep
echo
echo -n “  Select option: “
read -r -n 1 opt
echo

case “$opt” in
1) do_list;        pause ;;
2) do_create;      pause ;;
3) do_lock_unlock; pause ;;
4) do_addgroup;    pause ;;
5) do_passwd;      pause ;;
6) do_delete;      pause ;;
7) do_transfer;     pause ;;
0) echo; echo “  Bye.”; echo; exit 0 ;;
*) warn “Invalid option. Enter a number from the menu.”; sleep 1 ;;
esac
done