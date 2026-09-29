ARCHS = arm64
TARGET := iphone:clang:16.5:14.0
include $(THEOS)/makefiles/common.mk
DEBUG = 1

TWEAK_NAME = BHTwitter

# Compile one coherent v7 core/settings implementation. The archived monolithic
# sources are intentionally NOT linked alongside it (duplicate classes/hooks).
BHTwitter_FILES = IOS26Compatibility.x $(shell find src \( -name '*.x' -o -name '*.m' \) | sort)
BHTwitter_FRAMEWORKS = UIKit Foundation AVFoundation AVKit CoreMotion GameController VideoToolbox Accelerate CoreMedia CoreVideo CoreImage CoreGraphics ImageIO Photos CoreServices SystemConfiguration SafariServices Security QuartzCore WebKit SceneKit UniformTypeIdentifiers
BHTwitter_PRIVATE_FRAMEWORKS = Preferences
BHTwitter_EXTRA_FRAMEWORKS = Cephei CepheiPrefs CepheiUI
BHTwitter_OBJ_FILES = $(shell find lib -name '*.a')
BHTwitter_LIBRARIES = sqlite3 bz2 c++ iconv z
BHTwitter_CFLAGS = -Isrc -Iffmpeg -fobjc-arc -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-unused-function -Wno-unused-property-ivar -Wno-error -DNFB_VERSION_STRING='"NeoFreeBird 11.98 iOS27"' -DNFB_COMMIT_STRING='"$(shell git rev-parse --short HEAD)"'

include $(THEOS_MAKE_PATH)/tweak.mk

ifdef SIDELOADED
SUBPROJECTS += libflex keychainfix
else
SUBPROJECTS += libflex
endif

include $(THEOS_MAKE_PATH)/aggregate.mk
