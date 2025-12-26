TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = thermalmonitord SpringBoard

ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

TWEAK_NAME = Powercuff
Powercuff_FILES = Powercuff.x
Powercuff_FRAMEWORKS = Foundation UIKit
# We removed BackBoardServices to fix the linker error
Powercuff_CFLAGS = -fobjc-arc -Wno-error

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
