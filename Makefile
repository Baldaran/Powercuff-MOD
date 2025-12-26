# Define the target and SDK
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = thermalmonitord SpringBoard

# Architectures for modern rootless jailbreaks
ARCHS = arm64 arm64e

# This tells Theos to build for /var/jb
THEOS_PACKAGE_SCHEME = rootless

TWEAK_NAME = Powercuff

# Powercuff source files
Powercuff_FILES = Powercuff.x
Powercuff_FRAMEWORKS = Foundation
Powercuff_CFLAGS = -fobjc-arc -std=c99

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
