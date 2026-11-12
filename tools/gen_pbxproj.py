#!/usr/bin/env python3
"""ThumbSet.xcodeproj/project.pbxproj を生成する（FX Survival の実績構造が雛形）。
ID は連番の 24 桁 hex で衝突しないようにする。"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_counter = [0]

def nid():
    _counter[0] += 1
    return "%024X" % _counter[0]

# (表示名, パス, 種別) 種別: swift / plist / assets / png
sources = [
    ("ThumbSetApp.swift", "Sources/ThumbSet/ThumbSetApp.swift"),
    ("ContentView.swift", "Sources/ThumbSet/ContentView.swift"),
    ("AppModel.swift", "Sources/ThumbSet/AppModel.swift"),
    ("VideoService.swift", "Sources/ThumbSet/VideoService.swift"),
    ("CoverInjector.swift", "Sources/ThumbSet/CoverInjector.swift"),
    ("IntroComposer.swift", "Sources/ThumbSet/IntroComposer.swift"),
]
info_plist = ("Info.plist", "Sources/ThumbSet/Info.plist")
assets = ("Assets.xcassets", "ThumbSet/Assets.xcassets")
loose_icons = [
    ("AppIcon60x60@2x.png", "ThumbSet/AppIcon60x60@2x.png"),
    ("AppIcon60x60@3x.png", "ThumbSet/AppIcon60x60@3x.png"),
    ("AppIcon76x76@2x.png", "ThumbSet/AppIcon76x76@2x.png"),
    ("AppIcon83.5x83.5@2x.png", "ThumbSet/AppIcon83.5x83.5@2x.png"),
]

file_refs = {}   # name -> id
build_files = {} # name -> build id
for name, path in sources:
    file_refs[name] = nid()
    build_files[name] = nid()
info_ref = nid()
assets_ref = nid(); assets_build = nid()
icon_refs = {}
icon_builds = {}
for name, path in loose_icons:
    icon_refs[name] = nid()
    icon_builds[name] = nid()
product_ref = nid()
group_main = nid(); group_products = nid(); group_root = nid()
target_id = nid()
phase_frameworks = nid(); phase_sources = nid(); phase_resources = nid()
proj_config_list = nid(); target_config_list = nid()
proj_debug = nid(); proj_release = nid(); tgt_debug = nid(); tgt_release = nid()

L = []
L.append("// !$*UTF8*$!")
L.append("{")
L.append("\tarchiveVersion = 1;")
L.append("\tclasses = {\n\t};")
L.append("\tobjectVersion = 56;")
L.append("\tobjects = {")
L.append("")
L.append("/* Begin PBXBuildFile section */")
for name, path in sources:
    L.append(f'\t\t{build_files[name]} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[name]} /* {name} */; }};')
L.append(f'\t\t{assets_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_ref} /* Assets.xcassets */; }};')
for name, path in loose_icons:
    L.append(f'\t\t{icon_builds[name]} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {icon_refs[name]} /* {name} */; }};')
L.append("/* End PBXBuildFile section */")
L.append("")
L.append("/* Begin PBXFileReference section */")
for name, path in sources:
    L.append(f'\t\t{file_refs[name]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = "<group>"; }};')
L.append(f'\t\t{product_ref} /* ThumbSet.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ThumbSet.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
L.append(f'\t\t{info_ref} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "{info_plist[1]}"; sourceTree = "<group>"; }};')
L.append(f'\t\t{assets_ref} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "{assets[1]}"; sourceTree = "<group>"; }};')
for name, path in loose_icons:
    L.append(f'\t\t{icon_refs[name]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = image.png; path = "{path}"; sourceTree = "<group>"; }};')
L.append("/* End PBXFileReference section */")
L.append("")
L.append("/* Begin PBXFrameworksBuildPhase section */")
L.append(f'\t\t{phase_frameworks} /* Frameworks */ = {{')
L.append("\t\t\tisa = PBXFrameworksBuildPhase;")
L.append("\t\t\tbuildActionMask = 2147483647;")
L.append("\t\t\tfiles = (\n\t\t\t);")
L.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
L.append("\t\t};")
L.append("/* End PBXFrameworksBuildPhase section */")
L.append("")
L.append("/* Begin PBXGroup section */")
L.append(f'\t\t{group_main} = {{')
L.append("\t\t\tisa = PBXGroup;")
L.append("\t\t\tchildren = (")
L.append(f'\t\t\t\t{group_root} /* ThumbSet */,')
L.append(f'\t\t\t\t{group_products} /* Products */,')
L.append("\t\t\t);")
L.append('\t\t\tsourceTree = "<group>";')
L.append("\t\t};")
L.append(f'\t\t{group_products} /* Products */ = {{')
L.append("\t\t\tisa = PBXGroup;")
L.append("\t\t\tchildren = (")
L.append(f'\t\t\t\t{product_ref} /* ThumbSet.app */,')
L.append("\t\t\t);")
L.append("\t\t\tname = Products;")
L.append('\t\t\tsourceTree = "<group>";')
L.append("\t\t};")
L.append(f'\t\t{group_root} /* ThumbSet */ = {{')
L.append("\t\t\tisa = PBXGroup;")
L.append("\t\t\tchildren = (")
for name, path in sources:
    L.append(f'\t\t\t\t{file_refs[name]} /* {name} */,')
L.append(f'\t\t\t\t{info_ref} /* Info.plist */,')
L.append(f'\t\t\t\t{assets_ref} /* Assets.xcassets */,')
for name, path in loose_icons:
    L.append(f'\t\t\t\t{icon_refs[name]} /* {name} */,')
L.append("\t\t\t);")
L.append("\t\t\tname = ThumbSet;")
L.append('\t\t\tsourceTree = "<group>";')
L.append("\t\t};")
L.append("/* End PBXGroup section */")
L.append("")
L.append("/* Begin PBXNativeTarget section */")
L.append(f'\t\t{target_id} /* ThumbSet */ = {{')
L.append("\t\t\tisa = PBXNativeTarget;")
L.append(f'\t\t\tbuildConfigurationList = {target_config_list} /* Build configuration list for PBXNativeTarget "ThumbSet" */;')
L.append("\t\t\tbuildPhases = (")
L.append(f'\t\t\t\t{phase_sources} /* Sources */,')
L.append(f'\t\t\t\t{phase_frameworks} /* Frameworks */,')
L.append(f'\t\t\t\t{phase_resources} /* Resources */,')
L.append("\t\t\t);")
L.append("\t\t\tbuildRules = (\n\t\t\t);")
L.append("\t\t\tdependencies = (\n\t\t\t);")
L.append("\t\t\tname = ThumbSet;")
L.append("\t\t\tproductName = ThumbSet;")
L.append(f'\t\t\tproductReference = {product_ref} /* ThumbSet.app */;')
L.append("\t\t\tproductType = \"com.apple.product-type.application\";")
L.append("\t\t};")
L.append("/* End PBXNativeTarget section */")
L.append("")
L.append("/* Begin PBXProject section */")
proj_id = nid()
L.append(f'\t\t{proj_id} /* Project object */ = {{')
L.append("\t\t\tisa = PBXProject;")
L.append("\t\t\tattributes = {")
L.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
L.append("\t\t\t\tLastSwiftUpdateCheck = 1600;")
L.append("\t\t\t\tLastUpgradeCheck = 1600;")
L.append("\t\t\t\tTargetAttributes = {")
L.append(f'\t\t\t\t\t{target_id} = {{')
L.append("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
L.append("\t\t\t\t\t};")
L.append("\t\t\t\t};")
L.append("\t\t\t};")
L.append(f'\t\t\tbuildConfigurationList = {proj_config_list} /* Build configuration list for PBXProject "ThumbSet" */;')
L.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
L.append("\t\t\tdevelopmentRegion = en;")
L.append("\t\t\thasScannedForEncodings = 0;")
L.append("\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);")
L.append(f'\t\t\tmainGroup = {group_main};')
L.append(f'\t\t\tproductRefGroup = {group_products} /* Products */;')
L.append("\t\t\tprojectDirPath = \"\";")
L.append("\t\t\tprojectRoot = \"\";")
L.append("\t\t\ttargets = (")
L.append(f'\t\t\t\t{target_id} /* ThumbSet */,')
L.append("\t\t\t);")
L.append("\t\t};")
L.append("/* End PBXProject section */")
L.append("")
L.append("/* Begin PBXResourcesBuildPhase section */")
L.append(f'\t\t{phase_resources} /* Resources */ = {{')
L.append("\t\t\tisa = PBXResourcesBuildPhase;")
L.append("\t\t\tbuildActionMask = 2147483647;")
L.append("\t\t\tfiles = (")
L.append(f'\t\t\t\t{assets_build} /* Assets.xcassets in Resources */,')
for name, path in loose_icons:
    L.append(f'\t\t\t\t{icon_builds[name]} /* {name} in Resources */,')
L.append("\t\t\t);")
L.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
L.append("\t\t};")
L.append("/* End PBXResourcesBuildPhase section */")
L.append("")
L.append("/* Begin PBXSourcesBuildPhase section */")
L.append(f'\t\t{phase_sources} /* Sources */ = {{')
L.append("\t\t\tisa = PBXSourcesBuildPhase;")
L.append("\t\t\tbuildActionMask = 2147483647;")
L.append("\t\t\tfiles = (")
for name, path in sources:
    L.append(f'\t\t\t\t{build_files[name]} /* {name} in Sources */,')
L.append("\t\t\t);")
L.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
L.append("\t\t};")
L.append("/* End PBXSourcesBuildPhase section */")
L.append("")
L.append("/* Begin XCBuildConfiguration section */")

def proj_config(cid, name, debug):
    out = [f'\t\t{cid} /* {name} */ = {{', "\t\t\tisa = XCBuildConfiguration;", "\t\t\tbuildSettings = {"]
    out.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    out.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
    out.append("\t\t\t\tLOCALIZATION_PREFERS_STRING_CATALOGS = YES;")
    if debug:
        out.append("\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;")
        out.append("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
        out.append('\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";')
    else:
        out.append("\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;")
        out.append("\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
    out.append("\t\t\t};")
    out.append(f'\t\t\tname = {name};')
    out.append("\t\t};")
    return out

def tgt_config(cid, name):
    out = [f'\t\t{cid} /* {name} */ = {{', "\t\t\tisa = XCBuildConfiguration;", "\t\t\tbuildSettings = {"]
    out.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    out.append("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
    out.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    out.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    out.append("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    out.append("\t\t\t\tINFOPLIST_FILE = Sources/ThumbSet/Info.plist;")
    out.append("\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;")
    out.append("\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = \"サムネ変更\";")
    out.append("\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;")
    out.append('\t\t\t\tINFOPLIST_KEY_UILaunchStoryboardName = "";')
    out.append("\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = \"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight\";")
    out.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
    out.append('\t\t\t\t\t"$(inherited)",')
    out.append('\t\t\t\t\t"@executable_path/Frameworks",')
    out.append("\t\t\t\t);")
    out.append("\t\t\t\tMARKETING_VERSION = 0.1.0;")
    out.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.aqua5624.ThumbSet;")
    out.append('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
    out.append("\t\t\t\tSDKROOT = iphoneos;")
    out.append("\t\t\t\tSUPPORTED_PLATFORMS = iphoneos;")
    out.append("\t\t\t\tSWIFT_EMBED_LIBRARIES = YES;")
    out.append("\t\t\t\tSWIFT_VERSION = 5.0;")
    out.append("\t\t\t\tTARGETED_DEVICE_FAMILY = 1;")
    out.append("\t\t\t};")
    out.append(f'\t\t\tname = {name};')
    out.append("\t\t};")
    return out

L += proj_config(proj_debug, "Debug", True)
L += proj_config(proj_release, "Release", False)
L += tgt_config(tgt_debug, "Debug")
L += tgt_config(tgt_release, "Release")
L.append("/* End XCBuildConfiguration section */")
L.append("")
L.append("/* Begin XCConfigurationList section */")
L.append(f'\t\t{proj_config_list} /* Build configuration list for PBXProject "ThumbSet" */ = {{')
L.append("\t\t\tisa = XCConfigurationList;")
L.append("\t\t\tbuildConfigurations = (")
L.append(f'\t\t\t\t{proj_debug} /* Debug */,')
L.append(f'\t\t\t\t{proj_release} /* Release */,')
L.append("\t\t\t);")
L.append("\t\t\tdefaultConfigurationIsVisible = 0;")
L.append("\t\t\tdefaultConfigurationName = Release;")
L.append("\t\t};")
L.append(f'\t\t{target_config_list} /* Build configuration list for PBXNativeTarget "ThumbSet" */ = {{')
L.append("\t\t\tisa = XCConfigurationList;")
L.append("\t\t\tbuildConfigurations = (")
L.append(f'\t\t\t\t{tgt_debug} /* Debug */,')
L.append(f'\t\t\t\t{tgt_release} /* Release */,')
L.append("\t\t\t);")
L.append("\t\t\tdefaultConfigurationIsVisible = 0;")
L.append("\t\t\tdefaultConfigurationName = Release;")
L.append("\t\t};")
L.append("/* End XCConfigurationList section */")
L.append("\t};")
L.append(f'\trootObject = {proj_id} /* Project object */;')
L.append("}")

os.makedirs(os.path.join(ROOT, "ThumbSet.xcodeproj"), exist_ok=True)
with open(os.path.join(ROOT, "ThumbSet.xcodeproj", "project.pbxproj"), "w") as f:
    f.write("\n".join(L) + "\n")

# スキームの BlueprintIdentifier をターゲット ID に合わせる
import re
scheme_path = os.path.join(ROOT, "ThumbSet.xcodeproj", "xcshareddata", "xcschemes", "ThumbSet.xcscheme")
if os.path.exists(scheme_path):
    with open(scheme_path) as f:
        scheme = f.read()
    scheme = re.sub(r'BlueprintIdentifier = "[0-9A-F]*"', f'BlueprintIdentifier = "{target_id}"', scheme)
    with open(scheme_path, "w") as f:
        f.write(scheme)
print("pbxproj generated:", _counter[0], "objects, target:", target_id)
