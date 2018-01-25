#!/bin/bash
# Make a release build (build, then release.sh)
# Upload to server as testing
# Install build by forcing job scheduler on device
# Make new release build for ota testing
# Upload to server as next
# Install build again, and make sure installation works
# TODO give a name to the script

set -o nounset

source script/buildids
[[ -f script/serials ]] && source script/serials || error "User error."

ADB="adb -s ${serials[$device]}"
FASTBOOT="fastboot -s ${serials[$device]}"
MAKE="make -j$(grep "^processor" /proc/cpuinfo | wc -l)"

error() {
	echo $@
	exit 1
}

prepare_vendor() {
	vendor/android-prepare-vendor/execute-all.sh -d $device -b $TODO -o vendor/android-prepare-vendor
}

# Basically lunch + make
build() {
	prepare_vendor
	rm -rf out
	source script/copperhead.sh
	lunch aosp_${device}-user
	$MAKE target-files-package
	if [[ $device == "marlin" ]] || [[ $device == "sailfish" ]]; then
		openssl x509 -outform der -in keys/marlin/verity.x509.pem -out kernel/google/marlin/verity_user.der.x509
	fi
	$MAKE brillo_update_payload
}

# release.sh call
release() {
	script/release.sh $device
	script/generate_metadata.py out/release-*/*ota_update*.zip
}

# $1 channel
# scp release.copperhead.co
upload() {
	scp out/release-*/*ota_update*.zip
	scp ${device}-testing $SERVER:${device}-${1}
}

# $1 channel
install_build() {
	$ADB shell setprop sys.update.channel $1
	$ADB shell cmd jobscheduler run co.copperhead.updater 1
}

build
release
upload testing
install_build testing
# If above install succeeds, proceed
build
release
upload next #Maybe set channel to non-testing before upload / upload to different channel
# Maybe wait until the user has finished testing the above original build before flashing the ota test build.
# Build it while waiting so as to not waste time on the build process
install_build next
# Ensure above installation succeeds