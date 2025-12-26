# Target and SDK
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = thermalmonitord SpringBoard

# Architectures for iPhone X (A11) and newer rootless
ARCHS = arm64 arm64e

# Ensure we are building for the /var/jb rootless prefix
THEOS_PACKAGE_SCHEME = rootless

TWEAK_NAME = Powercuff

# Source files
Powercuff_FILES = Powercuff.x

# Frameworks: 
# UIKit is needed for the backlight controller hooks.
# BackBoardServices is the private framework that handles screen state.
Powercuff_FRAMEWORKS = Foundation UIKit
Powercuff_PRIVATE_FRAMEWORKS = BackBoardServices

# Genius Flags: 
# We use -fobjc-arc for modern memory management.
# We add -Wno-error to prevent small warnings from stopping the build on GitHub Actions.
Powercuff_CFLAGS = -fobjc-arc -Wno-error

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
