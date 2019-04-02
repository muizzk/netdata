# #No shebang needed, its a library
#
# This is a common functions utility library for kickstart
#
# Copyright: SPDX-License-Identifier: GPL-3.0-or-later
#
# Author: Pavlos Emm. Katsoulakis <paul@netdata.cloud>

# shellcheck disable=SC2039,SC2059,SC2086

setup_terminal() {
	TPUT_RESET=""
	TPUT_YELLOW=""
	TPUT_WHITE=""
	TPUT_BGRED=""
	TPUT_BGGREEN=""
	TPUT_BOLD=""
	TPUT_DIM=""

	# Is stderr on the terminal? If not, then fail
	test -t 2 || return 1

	if command -v tput >/dev/null 2>&1; then
		if [ $(($(tput colors 2>/dev/null))) -ge 8 ]; then
			# Enable colors
			TPUT_RESET="$(tput sgr 0)"
			TPUT_YELLOW="$(tput setaf 3)"
			TPUT_WHITE="$(tput setaf 7)"
			TPUT_BGRED="$(tput setab 1)"
			TPUT_BGGREEN="$(tput setab 2)"
			TPUT_BOLD="$(tput bold)"
			TPUT_DIM="$(tput dim)"
		fi
	fi

	return 0
}

progress() {
	echo >&2 " --- ${TPUT_DIM}${TPUT_BOLD}${*}${TPUT_RESET} --- "
}

escaped_print() {
	if printf "%q " test >/dev/null 2>&1; then
		printf "%q " "${@}"
	else
		printf "%s" "${*}"
	fi
	return 0
}

run() {
	local dir="${PWD}" info_console

	if [ "${UID}" = "0" ]; then
		info_console="[${TPUT_DIM}${dir}${TPUT_RESET}]# "
	else
		info_console="[${TPUT_DIM}${dir}${TPUT_RESET}]$ "
	fi

	escaped_print "${info_console}${TPUT_BOLD}${TPUT_YELLOW}" "${@}" "${TPUT_RESET}\n" >&2

	${@}

	local ret=$?
	if [ ${ret} -ne 0 ]; then
		printf >&2 "${TPUT_BGRED}${TPUT_WHITE}${TPUT_BOLD} FAILED ${TPUT_RESET} ${*} \n\n"
	else
		printf >&2 "${TPUT_BGGREEN}${TPUT_WHITE}${TPUT_BOLD} OK ${TPUT_RESET} ${*} \n\n"
	fi

	return ${ret}
}

fatal() {
	printf >&2 "${TPUT_BGRED}${TPUT_WHITE}${TPUT_BOLD} ABORTED ${TPUT_RESET} ${*} \n\n"
	exit 1
}

warning() {
	printf >&2 "${TPUT_BGRED}${TPUT_WHITE}${TPUT_BOLD} WARNING ${TPUT_RESET} ${*} \n\n"
	if [ "${INTERACTIVE}" = "0" ]; then
		fatal "Stopping due to non-interactive mode. Fix the issue or retry installation in an interactive mode."
	else
		read -r -p "Press ENTER to attempt netdata installation > "
		progress "OK, let's give it a try..."
	fi
}

create_tmp_directory() {
	# Check if tmp is mounted as noexec
	if grep -Eq '^[^ ]+ /tmp [^ ]+ ([^ ]*,)?noexec[, ]' /proc/mounts; then
		pattern="$(pwd)/netdata-kickstart-XXXXXX"
	else
		pattern="/tmp/netdata-kickstart-XXXXXX"
	fi

	mktemp -d $pattern
}

download() {
	url="${1}"
	dest="${2}"
	if command -v curl >/dev/null 2>&1; then
		run curl -sSL --connect-timeout 10 --retry 3 "${url}" >"${dest}" || fatal "Cannot download ${url}"
	elif command -v wget >/dev/null 2>&1; then
		run wget -T 15 -O - "${url}" >"${dest}" || fatal "Cannot download ${url}"
	else
		fatal "I need curl or wget to proceed, but neither is available on this system."
	fi
}

detect_bash4() {
	bash="${1}"
	if [ -z "${BASH_VERSION}" ]; then
		# we don't run under bash
		if [ -n "${bash}" ] && [ -x "${bash}" ]; then
			# shellcheck disable=SC2016
			BASH_MAJOR_VERSION=$(${bash} -c 'echo "${BASH_VERSINFO[0]}"')
		fi
	else
		# we run under bash
		BASH_MAJOR_VERSION="${BASH_VERSINFO[0]}"
	fi

	if [ -z "${BASH_MAJOR_VERSION}" ]; then
		echo >&2 "No BASH is available on this system"
		return 1
	elif [ $((BASH_MAJOR_VERSION)) -lt 4 ]; then
		echo >&2 "No BASH v4+ is available on this system (installed bash is v${BASH_MAJOR_VERSION}"
		return 1
	fi
	return 0
}

dependencies() {
	SYSTEM="$(uname -s)"
	OS="$(uname -o)"
	MACHINE="$(uname -m)"

	echo "System            : ${SYSTEM}"
	echo "Operating System  : ${OS}"
	echo "Machine           : ${MACHINE}"
	echo "BASH major version: ${BASH_MAJOR_VERSION}"

	if [ "${OS}" != "GNU/Linux" ] && [ "${SYSTEM}" != "Linux" ]; then
		warning "Cannot detect the packages to be installed on a ${SYSTEM} - ${OS} system."
	else
		bash="$(command -v bash 2>/dev/null)"
		if ! detect_bash4 "${bash}"; then
			warning "Cannot detect packages to be installed in this system, without BASH v4+."
		else
			progress "Downloading script to detect required packages..."
			download "${PACKAGES_SCRIPT}" "${TMPDIR}/install-required-packages.sh"
			if [ ! -s "${TMPDIR}/install-required-packages.sh" ]; then
				warning "Downloaded dependency installation script is empty."
			else
				progress "Running downloaded script to detect required packages..."
				run ${sudo} "${bash}" "${TMPDIR}/install-required-packages.sh" ${PACKAGES_INSTALLER_OPTIONS}
				# shellcheck disable=SC2181
				if [ $? -ne 0 ] ; then
					warning "It failed to install all the required packages, but installation might still be possible."
				fi
			fi

		fi
	fi
}

function safe_sha256sum() {
	# Within the contexct of the installer, we only use -c option that is common between the two commands
	# We will have to reconsider if we start non-common options
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum $@
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 $@
	else
		fatal "I could not find a suitable checksum binary to use"
	fi
}
