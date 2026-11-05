TARGET := iphone:clang:16.5:14.0
ARCHS := arm64e arm64

# RootHide 必须用 roothide 方案（不是 rootless）
THEOS_PACKAGE_SCHEME := roothide

INSTALL_TARGET_PROCESSES := Filza

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := FilzaToFila

FilzaToFila_FILES := Tweak.x
FilzaToFila_CFLAGS := -fobjc-arc -Wno-unused-function -Wno-deprecated-declarations
FilzaToFila_FRAMEWORKS := UIKit Foundation
FilzaToFila_LIBRARIES := substrate

include $(THEOS_MAKE_PATH)/tweak.mk
