#!/usr/bin/env python3
"""Generate the Xcode project without third-party tools. No credentials are read."""
import hashlib
import json
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
objects = {}

def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def ref(name):
    return uid(name)

def add(key, isa, **values):
    objects[uid(key)] = dict(isa=isa, **values)
    return uid(key)

def value(item):
    if isinstance(item, dict):
        return '{ ' + ' '.join(f'{key} = {value(val)};' for key, val in item.items()) + ' }'
    if isinstance(item, list):
        return '( ' + ', '.join(value(val) for val in item) + ' )'
    return json.dumps(str(item))

shared = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'CodexMonitor/Shared').glob('*.swift'))
services = sorted(str(p.relative_to(ROOT)) for folder in ['Auth', 'Networking', 'Sync'] for p in (ROOT/f'CodexMonitor/{folder}').glob('*.swift'))
app = shared + services + sorted(str(p.relative_to(ROOT)) for p in (ROOT/'CodexMonitor/App').glob('*.swift'))
widget = shared + services + ['CodexMonitor/Widgets/CodexWidgets.swift']
all_files = sorted(set(app + widget))
for path in all_files:
    add(path, 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=path, sourceTree='<group>')
add('assets', 'PBXFileReference', lastKnownFileType='folder.assetcatalog', path='CodexMonitor/Assets.xcassets', sourceTree='<group>')
icons = ['CodexMonitor/Resources/AppIcon60@2x.png', 'CodexMonitor/Resources/AppIcon60@3x.png']
for path in icons:
    add(path, 'PBXFileReference', lastKnownFileType='image.png', path=path, sourceTree='<group>')
add('app-product', 'PBXFileReference', explicitFileType='wrapper.application', path='CodexMonitor.app', sourceTree='BUILT_PRODUCTS_DIR')
add('widget-product', 'PBXFileReference', explicitFileType='wrapper.app-extension', path='CodexMonitorWidgets.appex', sourceTree='BUILT_PRODUCTS_DIR')
add('products', 'PBXGroup', children=[ref('app-product'), ref('widget-product')], name='Products', sourceTree='<group>')
add('main-group', 'PBXGroup', children=[ref(p) for p in all_files+icons] + [ref('assets'), ref('products')], sourceTree='<group>')

for target, files in [('app', app), ('widget', widget)]:
    builds = [add(f'{target}:{path}', 'PBXBuildFile', fileRef=ref(path)) for path in files]
    add(f'{target}-sources', 'PBXSourcesBuildPhase', buildActionMask='2147483647', files=builds, runOnlyForDeploymentPostprocessing='0')
    assets = []
    if target == 'app':
        assets.extend(add(f'icon:{path}', 'PBXBuildFile', fileRef=ref(path)) for path in icons)
    add(f'{target}-resources', 'PBXResourcesBuildPhase', buildActionMask='2147483647', files=assets, runOnlyForDeploymentPostprocessing='0')
    add(f'{target}-frameworks', 'PBXFrameworksBuildPhase', buildActionMask='2147483647', files=[], runOnlyForDeploymentPostprocessing='0')

add('embed-widget-build', 'PBXBuildFile', fileRef=ref('widget-product'), settings={'ATTRIBUTES': ['RemoveHeadersOnCopy']})
add('embed-widget', 'PBXCopyFilesBuildPhase', buildActionMask='2147483647', dstPath='', dstSubfolderSpec='13', files=[ref('embed-widget-build')], name='Embed App Extensions', runOnlyForDeploymentPostprocessing='0')
add('widget-proxy', 'PBXContainerItemProxy', containerPortal=ref('project'), proxyType='1', remoteGlobalIDString=ref('widget-target'), remoteInfo='CodexMonitorWidgets')
add('widget-dependency', 'PBXTargetDependency', target=ref('widget-target'), targetProxy=ref('widget-proxy'))

common = {
    'CLANG_ENABLE_MODULES': 'YES', 'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '26.0',
    'SWIFT_VERSION': '5.0', 'TARGETED_DEVICE_FAMILY': '1', 'CODE_SIGN_STYLE': 'Automatic',
    'DEVELOPMENT_TEAM': 'HA9DK5S5U3', 'MARKETING_VERSION': '0.2.0', 'CURRENT_PROJECT_VERSION': '3',
    'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'SUPPORTS_MACCATALYST': 'NO',
    'ENABLE_USER_SCRIPT_SANDBOXING': 'YES', 'SWIFT_EMIT_LOC_STRINGS': 'YES',
}
for scope in ['project', 'app', 'widget']:
    configs = []
    for configuration in ['Debug', 'Release']:
        settings = dict(common)
        settings.update({'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if configuration == 'Debug' else '-O',
                         'DEBUG_INFORMATION_FORMAT': 'dwarf' if configuration == 'Debug' else 'dwarf-with-dsym'})
        if scope != 'project':
            is_widget = scope == 'widget'
            settings.update({
                'PRODUCT_NAME': 'CodexMonitorWidgets' if is_widget else 'CodexMonitor',
                'PRODUCT_BUNDLE_IDENTIFIER': 'com.andremotta.codexmonitor' + ('.widgets' if is_widget else ''),
                'INFOPLIST_FILE': 'CodexMonitor/Widget-Info.plist' if is_widget else 'CodexMonitor/App-Info.plist',
                'CODE_SIGN_ENTITLEMENTS': 'CodexMonitor/Monitor.entitlements',
                'GENERATE_INFOPLIST_FILE': 'NO',
                'LD_RUNPATH_SEARCH_PATHS': ['$(inherited)', '@executable_path/Frameworks'] + (['@executable_path/../../Frameworks'] if is_widget else []),
                'SWIFT_ACTIVE_COMPILATION_CONDITIONS': '$(inherited)' + (' DEBUG' if configuration == 'Debug' else '') + (' WIDGET_EXTENSION' if is_widget else ''),
            })
            if is_widget: settings.update({'APPLICATION_EXTENSION_API_ONLY': 'YES', 'SKIP_INSTALL': 'YES'})
        configs.append(add(f'{scope}-{configuration}', 'XCBuildConfiguration', buildSettings=settings, name=configuration))
    add(f'{scope}-configs', 'XCConfigurationList', buildConfigurations=configs, defaultConfigurationIsVisible='0', defaultConfigurationName='Debug')

for target in ['app', 'widget']:
    is_widget = target == 'widget'
    add(f'{target}-target', 'PBXNativeTarget', buildConfigurationList=ref(f'{target}-configs'),
        buildPhases=[ref(f'{target}-sources'), ref(f'{target}-frameworks'), ref(f'{target}-resources')] + ([] if is_widget else [ref('embed-widget')]),
        buildRules=[], dependencies=[] if is_widget else [ref('widget-dependency')],
        name='CodexMonitorWidgets' if is_widget else 'CodexMonitor', productName='CodexMonitorWidgets' if is_widget else 'CodexMonitor',
        productReference=ref('widget-product' if is_widget else 'app-product'),
        productType='com.apple.product-type.app-extension' if is_widget else 'com.apple.product-type.application')

capability = {'com.apple.ApplicationGroups.iOS': {'enabled': '1'}}
add('project', 'PBXProject', attributes={'BuildIndependentTargetsInParallel': 'YES', 'LastUpgradeCheck': '2630',
    'TargetAttributes': {ref(f'{target}-target'): {'CreatedOnToolsVersion': '26.3', 'DevelopmentTeam': 'HA9DK5S5U3', 'SystemCapabilities': capability} for target in ['app','widget']}},
    buildConfigurationList=ref('project-configs'), compatibilityVersion='Xcode 14.0', developmentRegion='pt-BR',
    hasScannedForEncodings='0', knownRegions=['pt-BR', 'en', 'Base'], mainGroup=ref('main-group'), productRefGroup=ref('products'),
    projectDirPath='', projectRoot='', targets=[ref('app-target'),ref('widget-target')])
project = ROOT/'CodexMonitor.xcodeproj'
project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n' + value({'archiveVersion':'1', 'classes':{}, 'objectVersion':'56', 'objects':objects, 'rootObject':ref('project')}) + '\n')

info = {'CFBundleDevelopmentRegion':'pt_BR', 'CFBundleExecutable':'$(EXECUTABLE_NAME)',
        'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleInfoDictionaryVersion':'6.0',
        'CFBundleName':'$(PRODUCT_NAME)', 'CFBundleShortVersionString':'$(MARKETING_VERSION)',
        'CFBundleVersion':'$(CURRENT_PROJECT_VERSION)', 'LegacyKeychainAccessGroup':'$(AppIdentifierPrefix)com.andremotta.codexmonitor'}
app_info = dict(info, CFBundleDisplayName='Codex Monitor', CFBundlePackageType='APPL',
    LSRequiresIPhoneOS=True, UILaunchScreen={}, UIApplicationSceneManifest={'UIApplicationSupportsMultipleScenes':False},
    UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait'],
    CFBundleURLTypes=[{'CFBundleURLName':'com.andremotta.codexmonitor','CFBundleURLSchemes':['codexmonitor']}])
app_info['CFBundleIcons'] = {'CFBundlePrimaryIcon': {'CFBundleIconFiles': ['AppIcon60'], 'UIPrerenderedIcon': True}}
widget_info = dict(info, CFBundleDisplayName='Cota do Codex', CFBundlePackageType='XPC!',
    NSExtension={'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'})
for name, plist in [('App-Info.plist',app_info), ('Widget-Info.plist',widget_info),
                     ('Monitor.entitlements',{'com.apple.security.application-groups':['group.com.andremotta.codexmonitor']})]:
    (ROOT/'CodexMonitor'/name).write_bytes(plistlib.dumps(plist))

scheme_dir = project/'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True,exist_ok=True)
buildable = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref("app-target")}" BuildableName="CodexMonitor.app" BlueprintName="CodexMonitor" ReferencedContainer="container:CodexMonitor.xcodeproj"/>'
(scheme_dir/'CodexMonitor.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2630" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')

assets = ROOT/'CodexMonitor/Assets.xcassets'
(assets/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
(assets/'AccentColor.colorset/Contents.json').write_text(json.dumps({'colors':[{'idiom':'universal','color':{'color-space':'srgb','components':{'red':'0.10','green':'0.64','blue':'0.49','alpha':'1.0'}}}], 'info':{'author':'xcode','version':1}}))
print('Generated CodexMonitor.xcodeproj')
