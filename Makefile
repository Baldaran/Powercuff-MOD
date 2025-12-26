# Define the target and SDK
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = thermalmonitord SpringBoard

# Architectures for modern rootless jailbreaks
ARCHS = arm64 arm64e

# Build for /var/jb
THEOS_PACKAGE_SCHEME = rootless

TWEAK_NAME = Powercuff

# Powercuff source files
Powercuff_FILES = Powercuff.x
Powercuff_FRAMEWORKS = Foundation UIKit
# BackBoardServices is required for the low-level backlight hooks
Powercuff_PRIVATE_FRAMEWORKS = BackBoardServices
Powercuff_CFLAGS = -fobjc-arc

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
