#!/bin/bash
cd uboot-imx

CROSS_COMPILE=aarch64-none-elf- make mrproper
rm -r ./atb-var-som_build

#CROSS_COMPILE=aarch64-none-elf- make O=./atb-var-som_build/ atb_var_som_defconfig

mkdir ./atb-var-som_build
cp atb_var_som.config atb-var-som_build/.config

#CROSS_COMPILE=aarch64-none-elf- make O=./atb-var-som_build/ menuconfig
#cp atb-var-som_build/.config atb_var_som.config

CROSS_COMPILE=aarch64-none-elf- make O=./atb-var-som_build/ -j8
cp ~/workspace/imx8/uboot-imx/atb-var-som_build/u-boot-nodtb.bin ~/workspace/imx8/imx-mkimage/iMX8M/
cp ~/workspace/imx8/uboot-imx/atb-var-som_build/spl/u-boot-spl.bin ~/workspace/imx8/imx-mkimage/iMX8M/

cp ~/workspace/imx8/uboot-imx/atb-var-som_build/arch/arm/dts/atb-var-som.dtb ~/workspace/imx8/imx-mkimage/iMX8M/
#cp ~/workspace/imx8/uboot-imx/atb-var-som_build/arch/arm/dts/imx8mp-evk.dtb ~/workspace/imx8/imx-mkimage/iMX8M/

cd ../imx-atf/
make distclean
CROSS_COMPILE=aarch64-none-elf- make PLAT=imx8mp bl31
cp build/imx8mp/release/bl31.bin ../imx-mkimage/iMX8M/


cd ../imx-mkimage
make clean
make SOC=iMX8MP flash_evk 
sudo dd if=./iMX8M/flash.bin of=/dev/sdc bs=1k seek=32 conv=fsync

cd ..
