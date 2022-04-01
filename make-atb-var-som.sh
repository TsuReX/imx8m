#!/bin/bash

uboot_dtb="./imx-uboot/atb-var-som_build/arch/arm/dts/atb-var-som.dtb"
#linux_dtb="./imx-uboot/atb-var-som_build/arch/arm/dts/atb-var-som.dtb"
linux_dtb="/home/user/building_drive/variscite/linux/build_imx8_var/arch/arm64/boot/dts/freescale/imx8mp-var-som-symphony.dtb"
linux="/home/user/building_drive/variscite/linux/build_imx8_var/arch/arm64/boot/Image"
rootfs="./rootfs.cpio.gz"

make_uboot() {
	# $1 - configuration type
	# $2 - final binaries destination directory
	# $3 - 
	echo "---> Building uboot"
	
	if ! [[ $# -eq 2 ]]
	then
		return -1
	fi
	
	cd imx-uboot/
	
	local binaries_dest_dir=$2
	local buildig_directory="./atb_building"
	
	local uboot_defconfig="atb_var_som_defconfig"
	#local uboot_defconfig="imx8mq_evk_defconfig"
	
	if [[ $1 == "defconfig" ]]
	then
		CROSS_COMPILE=aarch64-none-elf- make mrproper
		rm -r $buildig_directory

		CROSS_COMPILE=aarch64-none-elf- make O=$buildig_directory $uboot_defconfig
	
	elif [[ $1 == "menuconfig" ]]
	then
		CROSS_COMPILE=aarch64-none-elf- make O=./atb-var-som_build/ menuconfig
		cp atb-var-som_build/.config atb_var_som.config
	
	elif [[ $1 == "config" ]]
	then
		cp atb_var_som.config atb-var-som_build/.config
	
	else
		echo "Unknown mode"
		exit
	fi
	
	CROSS_COMPILE=aarch64-none-elf- make O=$buildig_directory -j16
	
	if ! [[ $? -eq 0 ]]
	then
		return -2
	fi
		
	cp "$buildig_directory/u-boot-nodtb.bin"                 $binaries_dest_dir
	cp "$buildig_directory/spl/u-boot-spl.bin"               $binaries_dest_dir
	cp "$buildig_directory/arch/arm/dts/atb-var-som.dtb"     $binaries_dest_dir
	#cp "$buildig_directory/arch/arm/dts/imx8mq-evk.dtb"	    "$binaries_dest_dir/atb-smarc.dtb"
	cp "$buildig_directory/tools/mkimage"                    "$binaries_dest_dir/mkimage_uboot"
	cd ..
	
	return 0
}

make_atf() {
	echo "---> Building ATF"
	
	if ! [[ $# -eq 1 ]]
	then
		return -1
	fi
	
	local binaries_dest_dir=$1
	local target_binary="bl31"
	local target_soc="imx8mp"
	#local target_soc="imx8mq"
	local debug_enable=0
	
	cd imx-atf/
	
	make distclean
	CROSS_COMPILE=aarch64-none-elf- make $target_binary PLAT=$target_soc DEBUG=$debug_enable
	if ! [[ $? -eq 0 ]]
	then
		return -2
	fi
	
	cp "build/$target_soc/release/$target_binary.bin" $binaries_dest_dir
	if ! [[ $? -eq 0 ]]
	then
		return -3
	fi

	cd ..
	
	return 0
}

make_aux_binaries() {
	echo "---> Preparing auxilary binaries"
	
	cp ./firmware-imx-8.9/firmware/ddr/synopsys/lpddr4_pmu_train_1d_dmem.bin 	./imx-mkimage/iMX8M/
	cp ./firmware-imx-8.9/firmware/ddr/synopsys/lpddr4_pmu_train_1d_imem.bin 	./imx-mkimage/iMX8M/
	cp ./firmware-imx-8.9/firmware/ddr/synopsys/lpddr4_pmu_train_2d_dmem.bin 	./imx-mkimage/iMX8M/
	cp ./firmware-imx-8.9/firmware/ddr/synopsys/lpddr4_pmu_train_2d_imem.bin 	./imx-mkimage/iMX8M/
	cp ./firmware-imx-8.9/firmware/hdmi/cadence/signed_hdmi_imx8m.bin 			./imx-mkimage/iMX8M/
	
	return 0
}

prepare_storage() {
	echo "---> Preparing storage"
	
	if ! [[ $# -eq 1 ]]
	then
		return -1
	fi
	
	local device=$1
	
	echo 1
	sudo dd if=/dev/zero of=$device bs=1M count=8
	sleep 1
	echo 2
	sudo parted $device mklabel msdos -s
	sleep 1
	echo 3
	sudo parted $device mkpart primary 8M 520M -s
	sleep 1
	echo 4
	sudo parted $device mkpart primary 528M 1G -s
	sleep 1
	echo 5
	sudo mkfs.fat -F32 $device"1"
	sleep 1
	echo 6
	echo y | sudo mkfs.ext4 $device"2"
	sleep 1
	sudo parted $device print
	
	return 0
}

make_image() {
	echo "---> Preparing image"	

	cd imx-mkimage

	make clean
	make SOC=iMX8MP BOARD=atb-var-som OUTIMG=usd_flash.bin flash_img
	#make SOC=iMX8MQ BOARD=atb-smarc OUTIMG=usd_flash.bin flash_img
	sha256sum ./iMX8M/usd_flash.bin
	
	sudo dd if=./iMX8M/usd_flash.bin of=/dev/sdc bs=1k seek=32 conv=fsync
	#sudo dd if=./iMX8M/usd_flash.bin of=/dev/sdc bs=1k seek=33 conv=fsync
	
	cd ..
	
	return 0
}

prepare_os_images_strorage() {
	echo "---> Preparing kernel, dtb and rootfs files on the bootable storage"

	sudo rm -rf ./target_flash_p1
	mkdir ./target_flash_p1
	sudo mount /dev/sdc1 ./target_flash_p1
	sudo rm -rf ./target_flash_p1/*
	
	find ./rootfs | cpio -H newc -o | gzip -9 > _rootfs.cpio.gz ; ./imx-mkimage/iMX8M/mkimage_uboot -A arm -T ramdisk -C gzip -d _rootfs.cpio.gz rootfs.cpio.gz; rm _rootfs.cpio.gz
	
	sudo cp $linux_dtb ./target_flash_p1/dtb
	sha256sum $linux_dtb ./target_flash_p1/dtb
	
	sudo cp $linux ./target_flash_p1/linux
	sha256sum $linux ./target_flash_p1/linux
	
	if [ ! -z $rootfs ]
	then
		sudo cp $rootfs ./target_flash_p1/rootfs
		sha256sum $rootfs ./target_flash_p1/rootfs
	fi
	sleep 1
	ls -l ./target_flash_p1
	sudo umount ./target_flash_p1
	sudo rm -rf ./target_flash_p1
	sudo rm -rf rootfs.cpio.gz
	
	return 0
	
}

prepare_rootfs() {
	echo "---> Preparing root fs on the bootable storage"

	sudo rm -rf ./target_flash_p2
	mkdir ./target_flash_p2
	sudo mount /dev/sdc2 ./target_flash_p2
	sudo rm -rf ./target_flash_p2/*
	sudo cp -r ./rootfs/* ./target_flash_p2
	sleep 1
	sudo umount ./target_flash_p2
	
	return 0

}

# 1
make_uboot $1 "../imx-mkimage/iMX8M/"
ret_val=$?
if ! [[ $ret_val -eq 0 ]]
then
	echo FAILED
	exit -1
else
	echo SUCCESS
fi

# 2
make_atf "../imx-mkimage/iMX8M/"
ret_val=$?
if ! [[ $ret_val -eq 0 ]]
then
	echo FAILED
	exit -2
else
	echo SUCCESS
fi

# 3
make_aux_binaries
ret_val=$?
if ! [[ $ret_val -eq 0 ]]
then
	echo FAILED
	exit -4
else
	echo SUCCESS
fi

# 3.5
prepare_storage /dev/sdc
ret_val=$?
if ! [[ $ret_val -eq 0 ]]
then
	echo FAILED
	exit -5
else
	echo SUCCESS
fi

# 4
make_image
ret_val=$?
if ! [[ $ret_val -eq 0 ]]
then
	echo FAILED
	exit -6
else
	echo SUCCESS
fi

#5
prepare_os_images_strorage
ret_val=$?
if ! [[ $ret_val -eq 0 ]]
then
	echo FAILED
	exit -6
else
	echo SUCCESS
fi

#6
prepare_rootfs
ret_val=$?
if ! [[ $ret_val -eq 0 ]]
then
	echo FAILED
	exit -7
else
	echo SUCCESS
fi
