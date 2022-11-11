# Target
TARGET = awboot

# Build revision
BUILD_REVISION_H = "build_revision.h"
BUILD_REVISION_D = "BUILD_REVISION"

SRCS =  main.c board.c lib/debug.c lib/xformat.c lib/div.c lib/fdt.c lib/string.c

INCLUDE_DIRS :=-I . -I include -I lib
LIB_DIR := -L ./
LIBS := -lm -lgcc

include	arch/arch.mk
include	lib/fatfs/fatfs.mk
include lib/lfs/build.mk

CFLAGS += -march=armv7-a -mtune=cortex-a7 -mthumb-interwork -mno-unaligned-access -mabi=aapcs-linux
CFLAGS += -Os -std=gnu99 -Wall -g $(INCLUDES) -flto -fPIC -DAWBOOT

ASFLAGS += -march=armv7-a -mtune=cortex-a7 -mthumb-interwork -mno-unaligned-access -mabi=aapcs-linux
ASFLAGS += -Os -std=gnu99 -Wall -g $(INCLUDES) -flto -fPIC

LDFLAGS += -march=armv7-a -mtune=cortex-a7 -mthumb-interwork -mno-unaligned-access -mabi=aapcs-linux -flto -fPIC

STRIP=arm-none-eabi-strip
CC=arm-none-eabi-gcc
SIZE=arm-none-eabi-size
OBJCOPY=arm-none-eabi-objcopy
HOSTCC=gcc
HOSTSTRIP=strip
DATE=/bin/date
CAT=/bin/cat
ECHO=/bin/echo
WORKDIR=$(/bin/pwd)
MAKE=make
OPENOCD = openocd

# Objects
EXT_OBJS =
OBJ_DIR = build
BUILD_OBJS = $(SRCS:%.c=$(OBJ_DIR)/%.o)
BUILD_OBJSA = $(ASRCS:%.S=$(OBJ_DIR)/%.o)
OBJS = $(BUILD_OBJSA) $(BUILD_OBJS) $(EXT_OBJS)


LBC_VERSION = $(shell grep LBC_APP_VERSION main.h | cut -d '"' -f 2)"-"$(shell /bin/cat .build_revision)

all: begin build_revision build mkboot

begin:
	@echo "---------------------------------------------------------------"
	@echo -n "Compiler version: "
	@$(CC) -v 2>&1 | tail -1

build_revision:
	@/bin/expr `/bin/cat .build_revision` + 1 > .build_revision
	@echo "// Generated by make, DO NOT EDIT" > $(BUILD_REVISION_H)
	@echo "#ifndef __$(BUILD_REVISION_D)_H__" >> $(BUILD_REVISION_H)
	@echo "#define $(BUILD_REVISION_D)" `/bin/cat .build_revision` >> $(BUILD_REVISION_H)
	@echo "#endif" >> $(BUILD_REVISION_H)
	@echo "Build revision:" `/bin/cat .build_revision`
	@echo "---------------------------------------------------------------"


.PHONY: tools boot.img
.SILENT:

build: $(TARGET)-boot.elf $(TARGET)-boot.bin $(TARGET)-fel.elf $(TARGET)-fel.bin
#$(STRIP) $(TARGET)

.SECONDARY : $(TARGET)
.PRECIOUS : $(OBJS)
$(TARGET)-fel.elf: $(OBJS)
	echo "  LD    $@"
	$(CC) $^ -o $@ $(LIB_DIR) $(LIBS) $(LDFLAGS) -T ./arch/arm32/mach-t113s3/link-fel.ld -nostdlib -Wl,-Map,$(TARGET).map

$(TARGET)-boot.elf: $(OBJS)
	echo "  LD    $@"
	$(CC) $^ -o $@ $(LIB_DIR) $(LIBS) $(LDFLAGS) -T ./arch/arm32/mach-t113s3/link-boot.ld -nostdlib -Wl,-Map,$(TARGET).map

$(TARGET)-fel.bin: $(TARGET)-fel.elf
	@echo OBJCOPY $@
	$(OBJCOPY) -O binary $< $@
	$(SIZE) $(TARGET)-fel.elf

$(TARGET)-boot.bin: $(TARGET)-boot.elf
	@echo OBJCOPY $@
	$(OBJCOPY) -O binary $< $@
	$(SIZE) $(TARGET)-boot.elf

$(OBJ_DIR)/%.o : %.c
	echo "  CC    $<"
	mkdir -p $(@D)
	$(CC) $(CFLAGS) $(INCLUDE_DIRS) -c $< -o $@

$(OBJ_DIR)/%.o : %.S
	echo "  CC    $<"
	mkdir -p $(@D)
	$(CC) $(ASFLAGS) $(INCLUDE_DIRS) -c $< -o $@

clean:
	rm -rf $(OBJ_DIR)
	rm -f $(TARGET)
	rm -f $(TARGET)-*.bin
	rm -f $(TARGET)-*.map
	rm -f $(TARGET)-*.elf
	$(MAKE) -C tools clean

tools:
	$(MAKE) -C tools all

mkboot: build tools
	tools/mksunxi $(TARGET)-fel.bin
	tools/mksunxi $(TARGET)-boot.bin

boot.img:
	dd if=/dev/zero of=boot.img bs=1M count=16
	parted -s boot.img mklabel msdos
	parted -s boot.img mkpart primary 1M 15M
	cd linux && ../tools/mklfs boot ./boot.img 16777216
	dd if=$(TARGET)-boot.bin of=boot.img bs=1k seek=8
	dd if=spi-boot.lfs of=boot.img bs=1k seek=1024
