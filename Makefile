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
Powercuff_FRAMEWORKS = Foundation
Powercuff_CFLAGS = -fobjc-arc

# --- GENIUS FIX START ---
# We removed AssertionServices from PRIVATE_FRAMEWORKS to prevent the "Framework not found" error.
# The tweak will still hook AssertionServices at runtime via SpringBoard.
# If you are NOT using Activator, I have commented it out to prevent further linker errors.
# Powercuff_LDFLAGS += -lactivator 
# --- GENIUS FIX END ---

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
