#!/bin/bash

uboot_src=$(pwd)"/imx-uboot"
atf_src=$(pwd)"/imx-atf"
img_dest=$(pwd)"/imx-mkimage/iMX8M"
img_utils=$(pwd)"/imx-mkimage"
aux_binaries=$(pwd)"/firmware-imx-8.9/firmware"
usd_device="/dev/sdc"

# 
# Function configures (if it's needed) and makes uboot binaries
# and copies it to specified directory.
make_uboot() {
	# $1 - u-boot sources directory
	# $2 - configuration type {defconfig | menuconfig | config}
	# $3 - final binaries destination directory
	# $4 - board {atb-var-som | atb-imx8m-smarc | atb-imx8mp-som-symphony | atb-imx8mp-som-voskhod1}

	echo "---> Building uboot"

	if ! [[ $# -eq 4 ]]
	then
		return -1
	fi

#	cd imx-uboot/
	cd $1

	local binaries_dest_dir=$3

	case $4 in
		"atb-var-som")
			local board="atb_var_som"
			local dtb="atb-var-som.dtb"
		;;

		"atb-imx8mp-som-symphony")
			local board="atb_imx8mp_som_symphony"
			local dtb="atb-imx8mp-som-symphony.dtb"
		;;

		"atb-imx8mp-som-voskhod1")
			local board="atb_imx8mp_som_voskhod1"
			local dtb="atb-imx8mp-som-voskhod1.dtb"
		;;

		"atb-imx8m-smarc")
			local board="atb_imx8m_smarc"
			local dtb="atb-imx8m-smarc.dtb"
		;;

		*)
			return -2
		;;
	esac 

	echo "---> Board: "${board}

	local uboot_defconfig="${board}_defconfig"
	local buildig_directory="./build-${board}"

	if [[ $2 == "defconfig" ]]
	then
		CROSS_COMPILE=aarch64-none-elf- make mrproper
		rm -r $buildig_directory

		CROSS_COMPILE=aarch64-none-elf- make O=$buildig_directory $uboot_defconfig

	elif [[ $2 == "menuconfig" ]]
	then
		CROSS_COMPILE=aarch64-none-elf- make distclean
		CROSS_COMPILE=aarch64-none-elf- make O=$buildig_directory menuconfig
		cp $buildig_directory/.config $buildig_directory.config

	elif [[ $2 == "config" ]]
	then
		CROSS_COMPILE=aarch64-none-elf- make distclean
		cp "${board}.config" $buildig_directory/.config

	else
		echo "Unknown mode"
		exit
	fi

	CROSS_COMPILE=aarch64-none-elf- make O=$buildig_directory -j16

	if ! [[ $? -eq 0 ]]
	then
		return -3
	fi

	cp "$buildig_directory/u-boot-nodtb.bin"		$binaries_dest_dir
	cp "$buildig_directory/spl/u-boot-spl.bin"		$binaries_dest_dir
	cp "$buildig_directory/arch/arm/dts/${dtb}"		$binaries_dest_dir
	cp "$buildig_directory/tools/mkimage"			$binaries_dest_dir/mkimage_uboot
	cd ..

	return 0
}

#
# Function makes ARM Trusted Firmware binaries for specified platform
# and cpies it to specified directory
make_atf() {
	# $1 - ATF sources directory
	# $2 - final binaries destination directory
	# $3 - board {atb-var-som | atb-imx8m-smarc | atb-imx8mp-som-symphony | atb-imx8mp-som-voskhod1}

	echo "---> Building ATF"

	if ! [[ $# -eq 3 ]]
	then
		return -1
	fi

	case $3 in
		"atb-var-som" |	"atb-imx8mp-som-symphony" | "atb-imx8mp-som-voskhod1")
			local target_soc="imx8mp"
		;;

		"atb-imx8m-smarc")
			local target_soc="imx8mq"
		;;

		*)
			return -2
		;;
	esac

	local binaries_dest_dir=$2
	local target_binary="bl31"
	local debug_enable=0

	cd $1

	make distclean
	CROSS_COMPILE=aarch64-none-elf- make $target_binary PLAT=$target_soc DEBUG=$debug_enable -j16
	if ! [[ $? -eq 0 ]]
	then
		return -3
	fi

	cp "build/$target_soc/release/$target_binary.bin" $binaries_dest_dir
	if ! [[ $? -eq 0 ]]
	then
		return -4
	fi

	cd ..

	return 0
}

#
# Function copies needed for soc booting biraies.
#
# TODO: Implement error generation.
make_aux_binaries() {
	# $1 - aux binaries directory
	# $2 - final binaries destination directory

	echo "---> Preparing auxilary binaries"

	if ! [[ $# -eq 2 ]]
	then
		return -1
	fi

	cp ${1}/ddr/synopsys/lpddr4_pmu_train_1d_dmem.bin 	$2
	cp ${1}/ddr/synopsys/lpddr4_pmu_train_1d_imem.bin 	$2
	cp ${1}/ddr/synopsys/lpddr4_pmu_train_2d_dmem.bin 	$2
	cp ${1}/ddr/synopsys/lpddr4_pmu_train_2d_imem.bin 	$2
	cp ${1}/hdmi/cadence/signed_hdmi_imx8m.bin 			$2

	return 0
}

#
# Function formates specified block device
# and creates partiotions with file systems where OS's files will be copied to.
#
# TODO: Implement error generation.
prepare_storage() {
	# $1 - path to a block device that will be formated and prepared for file systems

	echo "---> Preparing storage"

	if ! [[ $# -eq 1 ]]
	then
		return -1
	fi

	local device=$1

	echo "Fill the device ${1} with zeroes"
	sudo dd if=/dev/zero of=$device bs=1M count=8
	sleep 1
	echo "Create MSDOS partition table on the device ${1}"
	sudo parted $device mklabel msdos -s
	sleep 1
	echo "Create first partition"
	sudo parted $device mkpart primary 8M 520M -s
	sleep 1
	echo "Create second partition"
	sudo parted $device mkpart primary 528M 1G -s
	sleep 1
	echo "Create fat32 file system on the patition ${device}1"
	sudo mkfs.fat -F32 $device"1"
	sleep 1
	echo "Create ext4 file system on the patition ${device}2"
	echo y | sudo mkfs.ext4 $device"2"
	sleep 1
	sudo parted $device print

	return 0
}

#
# Functions places prepared bootloader binary to specified block device. 
#
# TODO: Implement error generation.
make_image() {
	# $1 - board final image buildig utilities directory
	# $2 - board {atb-var-som | atb-imx8m-smarc}

	echo "---> Preparing image"	

	if ! [[ $# -eq 2 ]]
	then
		return -1
	fi

	local board=$2
	case $2 in
		"atb-var-som" | "atb-imx8mp-som-symphony" | "atb-imx8mp-som-voskhod1")
			local soc="iMX8MP"
			local seek=32
		;;

		"atb-imx8m-smarc")
			local soc="iMX8MQ"
			local seek=33
		;;

		*)
			return -2
		;;
	esac

	cd $1

	make clean

	make SOC=${soc} BOARD=${board} OUTIMG=usd_flash.bin flash_img
	sudo dd if=./iMX8M/usd_flash.bin of=/dev/sdc bs=1k seek=${seek} conv=fsync

	sha256sum ./iMX8M/usd_flash.bin

	cd ..

	return 0
}

#
# Function copies to target storage device binaries needed for OS booting: linux kernel, dtb, root file system image.
#
# TODO: Make paremeters to be obtained from arguments
# TODO: Implement error generation.
prepare_os_images_storage() {
	echo "---> Preparing kernel, dtb and rootfs files on the bootable storage"
	sleep 5
	sudo rm -rf ./target_flash_p1
	mkdir ./target_flash_p1
	sudo mount /dev/sdc1 ./target_flash_p1
	sudo rm -rf ./target_flash_p1/*

	linux_dtb="/home/user/building_drive/buildroot/output/images/atb-imx8mp-som-symphony.dtb"
	#linux_dtb="/home/user/building_drive/buildroot/output/build/linux-custom/arch/arm64/boot/dts/freescale/imx8mp-var-som-symphony.dtb"
	linux="/home/user/building_drive/buildroot/output/images/Image"
	rootfs="/home/user/building_drive/buildroot/output/images/rootfs.cpio.gz"

	echo "Copy dtb"
#	find ./rootfs | cpio -H newc -o | gzip -9 > _rootfs.cpio.gz ; ./imx-mkimage/iMX8M/mkimage_uboot -A arm -T ramdisk -C gzip -d _rootfs.cpio.gz rootfs.cpio.gz; rm _rootfs.cpio.gz
	sudo cp $linux_dtb ./target_flash_p1/dtb
	sha256sum $linux_dtb ./target_flash_p1/dtb

	echo "Copy linux"
	sudo cp $linux ./target_flash_p1/linux
	sha256sum $linux ./target_flash_p1/linux

	echo "Copy rootfs"
	sudo ./imx-mkimage/iMX8M/mkimage_uboot -A arm -T ramdisk -C gzip -d $rootfs ./target_flash_p1/rootfs
#	sudo cp $rootfs ./target_flash_p1/rootfs
	sha256sum $rootfs ./target_flash_p1/rootfs

	sleep 1

	ls -l ./target_flash_p1
	sudo umount ./target_flash_p1
	sudo rm -rf ./target_flash_p1
	sudo rm -rf rootfs.cpio.gz

	return 0
}

#
# Function copies to target storage device 
#
# TODO: Make paremeters to be obtained from arguments
prepare_rootfs() {
	echo "---> Preparing root fs on the bootable storage"

	sudo rm -rf ./target_flash_p2
	mkdir ./target_flash_p2
	sudo mount /dev/sdc2 ./target_flash_p2
	sudo rm -rf ./target_flash_p2/*
	sudo cp -r /home/user/building_drive/buildroot/output/target/* ./target_flash_p2
	sleep 1
	sudo umount ./target_flash_p2
	sudo rm -rf ./target_flash_p2

	return 0
}

# The script entry point is here.
# The script's arguments are:
# $1 - configuration type {defconfig | menuconfig | config}
# $2 - board {atb-var-som | atb-imx8mp-som | atb-imx8m-smarc}

if ! [[ $# -eq 2 ]]
then
	echo FAILED
	exit -1
fi

config_type=$1
board=$2

# 0
# TODO: Wrapp the code into function
firmware=firmware-imx-8.9
if ! [[ -d ./${firmware} ]]
then
	wget "http://sources.buildroot.net/firmware-imx/${firmware}.bin"
	chmod 777 "${firmware}.bin"
	./${firmware}.bin
	rm -f "${firmware}.bin"
#	rm -rf "${firmware}"
fi
exit
# 1
make_uboot ${uboot_src} ${config_type} ${img_dest} ${board}
ret_val=$?
if ! [[ $ret_val -eq 0 ]]
then
	echo FAILED: $ret_val
	exit -11
else
	echo SUCCESS
fi

# 2
make_atf ${atf_src} ${img_dest} ${board}
ret_val=$?
if ! [[ $ret_val -eq 0 ]]
then
	echo FAILED
	exit -12
else
	echo SUCCESS
fi

# 3
make_aux_binaries ${aux_binaries} ${img_dest}
ret_val=$?
if ! [[ $ret_val -eq 0 ]]
then
	echo FAILED
	exit -14
else
	echo SUCCESS
fi

# 3.5
prepare_storage ${usd_device}
ret_val=$?
if ! [[ $ret_val -eq 0 ]]
then
	echo FAILED
	exit -15
else
	echo SUCCESS
fi

# 4
make_image ${img_utils} ${board}
ret_val=$?
if ! [[ $ret_val -eq 0 ]]
then
	echo FAILED
	exit -16
else
	echo SUCCESS
fi

#echo "---> WARNING! The script is intentionally shorted. Bootloader is prepared and placed only."
#exit

#5
prepare_os_images_storage
ret_val=$?
if ! [[ $ret_val -eq 0 ]]
then
	echo FAILED
	exit -16
else
	echo SUCCESS
fi

#6
prepare_rootfs
ret_val=$?
if ! [[ $ret_val -eq 0 ]]
then
	echo FAILED
	exit -17
else
	echo SUCCESS
fi
