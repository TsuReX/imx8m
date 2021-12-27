#!/bin/bash

uboot_dtb="./imx-uboot/atb-var-som_build/arch/arm/dts/atb-var-som.dtb"
#linux_dtb="./imx-uboot/atb-var-som_build/arch/arm/dts/atb-var-som.dtb"
linux_dtb="/home/vasily/workspace/variscite/linux/arch/arm64/boot/dts/freescale/imx8mp-var-som-symphony.dtb"
#linux="./imx_Image"
linux="/home/vasily/workspace/variscite/linux/arch/arm64/boot/Image"
rootfs=

# 1
cd imx-uboot/

if [[ $1 == "defconfig" ]]
then
	CROSS_COMPILE=aarch64-none-elf- make mrproper
	rm -r ./atb-var-som_build
	CROSS_COMPILE=aarch64-none-elf- make O=./atb-var-som_build/ atb_var_som_defconfig

elif [[ $1 == "menuconfig" ]]
then
	CROSS_COMPILE=aarch64-none-elf- make O=./atb-var-som_build/ menuconfig
#	cp atb-var-som_build/.config atb_var_som.config

else
	echo "Unknown mode"
	exit
fi

CROSS_COMPILE=aarch64-none-elf- make O=./atb-var-som_build/ -j16

cp ./atb-var-som_build/u-boot-nodtb.bin                 ../imx-mkimage/iMX8M/
cp ./atb-var-som_build/spl/u-boot-spl.bin               ../imx-mkimage/iMX8M/
cp ./atb-var-som_build/arch/arm/dts/atb-var-som.dtb     ../imx-mkimage/iMX8M/
cp ./atb-var-som_build/tools/mkimage                    ../imx-mkimage/iMX8M/mkimage_uboot
cd ..

# 2
cd imx-atf/

make distclean
CROSS_COMPILE=aarch64-none-elf- make PLAT=imx8mp bl31

cp build/imx8mp/release/bl31.bin ../imx-mkimage/iMX8M/

cd ..

# 3
cp ./firmware-imx-8.9/firmware/ddr/synopsys/lpddr4_pmu_train_1d_dmem.bin ./imx-mkimage/iMX8M/
cp ./firmware-imx-8.9/firmware/ddr/synopsys/lpddr4_pmu_train_1d_imem.bin ./imx-mkimage/iMX8M/
cp ./firmware-imx-8.9/firmware/ddr/synopsys/lpddr4_pmu_train_2d_dmem.bin ./imx-mkimage/iMX8M/
cp ./firmware-imx-8.9/firmware/ddr/synopsys/lpddr4_pmu_train_2d_imem.bin ./imx-mkimage/iMX8M/

# 4
cd imx-mkimage/

make clean
make SOC=iMX8MP BOARD=atb-var-som OUTIMG=atb-var-som.bin flash_img

sudo dd if=./iMX8M/atb-var-som.bin of=/dev/sdc bs=1k seek=32 conv=fsync

cd ..

#5
sudo umount -f ./target_flash
sudo rm -rf ./target_flash
mkdir ./target_flash
sudo mount /dev/sdc1 ./target_flash

sudo cp $linux_dtb ./target_flash/dtb
sudo cp $linux ./target_flash/linux
if [ ! -z $rootfs ]
then
	sudo cp $rootfs ./target_flash
fi
sleep 5
ls -l ./target_flash
sudo umount ./target_flash
sudo rm -rf ./target_flash
