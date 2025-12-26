# Ensure you are targeting rootless
export THEOS_PACKAGE_SCHEME = rootless

# Basic Tweak Info
TWEAK_NAME = Powercuff
Powercuff_FILES = Powercuff.x
Powercuff_CFLAGS = -fobjc-arc

# NO PRIVATE_FRAMEWORKS for AssertionServices needed here anymore!
# Just standard frameworks if needed (like Foundation)
Powercuff_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
