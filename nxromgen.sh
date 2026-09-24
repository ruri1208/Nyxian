#!/bin/sh

# Takes in the current Nyxian Source and bakes a new ROM template for you

set -eu

GEN_ROM_REV="2026-09-24-NXROMGEN"

SRC="${1:?usage: nxromgen.sh <nyxian-root> <out-dir>}"
OUT="${2:?usage: nxromgen.sh <nyxian-root> <out-dir>}"

# Check if ROM template generator is capable of creating a ROM template
# From the Nyxian Source you pointed to
if [ -d "$SRC/Nyxian/LindChain/ProcEnvironment" ]; then
    REPO="$(cd "$SRC" && pwd)"
elif [ -d "$SRC/LindChain/ProcEnvironment" ]; then
    REPO="$(cd "$SRC/.." && pwd)"
else
    echo "error: could not locate LindChain/ProcEnvironment under $SRC" >&2
    exit 1
fi

# Convinience
ROOT="$REPO/Nyxian"
PE="$ROOT/LindChain/ProcEnvironment"

# Another check
[ -d "$PE" ] || { echo "error: $PE not found" >&2; exit 1; }

echo ">> generator revision: $GEN_ROM_REV"
echo ">> output: $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/rom/src" "$OUT/rom/stubs" "$OUT/rom/include" "$OUT/rom/frameworks"

echo ">> copying ProcEnvironment"
mkdir -p "$OUT/rom/src/LindChain"
cp -R "$PE" "$OUT/rom/src/LindChain/ProcEnvironment"

# Guest stuff shall not be inside the ROM
GUEST_SHIMS="$OUT/rom/src/LindChain/ProcEnvironment/Shims"
GUEST_TWEAKS="$OUT/rom/src/LindChain/ProcEnvironment/LiveContainer/Tweaks"
GUEST_LCBOOTSTRAP="$OUT/rom/src/LindChain/ProcEnvironment/LiveContainer/LCBootstrap.m"

for guest_dir in "$GUEST_SHIMS" "$GUEST_TWEAKS"; do
    if [ -d "$guest_dir" ]; then
        find "$guest_dir" -type f \( -name '*.m' -o -name '*.mm' -o -name '*.c' -o -name '*.cpp' \) -delete
    fi
done
rm -f "$GUEST_LCBOOTSTRAP"

echo ">> excluding guest sources: ProcEnvironment/Shims, LiveContainer/Tweaks, LiveContainer/LCBootstrap.m"

# Compilation infra is not part of the ROM too
PEPROCESS="$OUT/rom/src/LindChain/ProcEnvironment/PEProcess.m"
if [ -f "$PEPROCESS" ]; then
    python3 - "$PEPROCESS" <<'PY_PATCH_MDK_IMPORT'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
s = s.replace('#import <MobileDevelopmentKit/MDKThreadPool.h>\n', '')
p.write_text(s)
PY_PATCH_MDK_IMPORT
fi

# Shimcache needs MDK.. so we replace it with a stub
SHIMCACHE_M="$OUT/rom/src/LindChain/ProcEnvironment/Surface/cache/shimcache.m"
if [ -f "$SHIMCACHE_M" ]; then
    cat > "$SHIMCACHE_M" <<'EOF'
/*
 * you shall reimplement this.
 */
#include <LindChain/ProcEnvironment/Surface/cache/shimcache.h>
#include <LindChain/ProcEnvironment/Surface/libkern/patch.h>
#include <LindChain/ProcEnvironment/Surface/libkern/klog.h>

LIBKERN_DEFINE_PATCHABLE(kern_return_t, ksurface_shimcache_append_code,
                         (CCFileType fileType, const char *code))
{
    (void)fileType;
    (void)code;
    klog_log("shimcache", "guest shim source ignored by ROM host");
    return KERN_SUCCESS;
}

LIBKERN_DEFINE_PATCHABLE(kern_return_t, ksurface_shimcache_build, (void))
{
    klog_log("shimcache", "no host-side compiler; shimcache build skipped");
    return KERN_SUCCESS;
}
EOF
fi

echo ">> excluding MobileDevelopmentKit and MDK backed host shim compiler"

# WindowServer is part of the ROM too
if [ -d "$ROOT/LindChain/WindowServer" ]; then
    cp -R "$ROOT/LindChain/WindowServer" "$OUT/rom/src/LindChain/WindowServer"

    # But not the Terminal Session
    rm -f "$OUT/rom/src/LindChain/WindowServer/Session/NXWindowSessionTerminal.m" "$OUT/rom/src/LindChain/WindowServer/Session/NXWindowSessionTerminal.h"
fi

# Important
for h in ksurface_abi.h ksurface_config.h; do
    if [ -f "$REPO/$h" ]; then
        cp "$REPO/$h" "$OUT/rom/include/$h"
    fi
done

for host_objc in \
    "$OUT/rom/src/LindChain/ProcEnvironment/PEProcessManager.m" \
    "$OUT/rom/src/LindChain/ProcEnvironment/PEUserspaceManager.m"
do
    if [ -f "$host_objc" ]; then
        python3 - "$host_objc" <<'PY_PATCH_SWIFT'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
s = s.replace('#import <Nyxian-Swift.h>\n', '')
p.write_text(s)
PY_PATCH_SWIFT
    fi
done
rm -f "$OUT/rom/include/Nyxian-Swift.h"

PEUM="$OUT/rom/src/LindChain/ProcEnvironment/PEUserspaceManager.m"
if [ -f "$PEUM" ]; then
    python3 - "$PEUM" <<'PY_PATCH_PEUM'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
anchor = '#import <LindChain/IDEFoundation/NXBootstrap.h>\n'
extra = (
    '#import <LindChain/IDEFoundation/NXAlertDiagnosticPresenter.h>\n'
    '#import <LindChain/ProcEnvironment/Utils/misc.h>\n'
)
if extra not in s:
    s = s.replace(anchor, anchor + extra)
p.write_text(s)
PY_PATCH_PEUM
fi

# NXAlertDiagnosticPresenter is host UI glue (not guest payload code), and is
# small enough to carry directly with WindowServer.
if [ -f "$ROOT/LindChain/IDEFoundation/NXAlertDiagnosticPresenter.h" ] && \
   [ -f "$ROOT/LindChain/IDEFoundation/NXAlertDiagnosticPresenter.m" ]; then
    mkdir -p "$OUT/rom/src/LindChain/IDEFoundation"
    cp "$ROOT/LindChain/IDEFoundation/NXAlertDiagnosticPresenter.h" \
       "$OUT/rom/src/LindChain/IDEFoundation/NXAlertDiagnosticPresenter.h"
    cp "$ROOT/LindChain/IDEFoundation/NXAlertDiagnosticPresenter.m" \
       "$OUT/rom/src/LindChain/IDEFoundation/NXAlertDiagnosticPresenter.m"
fi

# OpenSSL is needed to do anything meaningful really
OPENSSL_FRAMEWORK="$ROOT/LindChain/OpenSSL.xcframework/ios-arm64/OpenSSL.framework"
if [ -d "$PE/LiveContainer/ZSign" ]; then
    if [ ! -d "$OPENSSL_FRAMEWORK" ]; then
        echo "error: ZSign is present but iOS arm64 OpenSSL.framework was not found:" >&2
        echo "       $OPENSSL_FRAMEWORK" >&2
        exit 1
    fi

    echo ">> copying OpenSSL iOS arm64 framework"
    rm -rf "$OUT/rom/frameworks/OpenSSL.framework"
    cp -R "$OPENSSL_FRAMEWORK" "$OUT/rom/frameworks/OpenSSL.framework"

    rm -rf "$OUT/rom/include/openssl" "$OUT/rom/include/OpenSSL"
    mkdir -p "$OUT/rom/include/openssl"
    cp -R "$OPENSSL_FRAMEWORK/Headers/." "$OUT/rom/include/openssl/"
    ln -s openssl "$OUT/rom/include/OpenSSL"

    [ -f "$OUT/rom/include/openssl/ocsp.h" ] || {
        echo "error: OpenSSL header staging failed (ocsp.h missing)" >&2
        exit 1
    }
fi

# We need those to do any type of subprocessing
FRONTBOARD_FRAMEWORK="$ROOT/LindChain/Private/Frameworks/FrontBoard.framework"
if [ -d "$FRONTBOARD_FRAMEWORK" ]; then
    echo ">> staging FrontBoard link stub"
    rm -rf "$OUT/rom/frameworks/FrontBoard.framework"
    cp -R "$FRONTBOARD_FRAMEWORK" "$OUT/rom/frameworks/FrontBoard.framework"
else
    echo "error: FrontBoard.framework link stub not found: $FRONTBOARD_FRAMEWORK" >&2
    exit 1
fi

# Now the include graph
echo ">> resolving include graph"
python3 - "$REPO" "$OUT" <<'PY'
import os
import re
import shutil
import sys
from collections import defaultdict

REPO, OUT = map(os.path.realpath, sys.argv[1:3])
ROOT = os.path.join(REPO, "Nyxian")
SRCDIR = os.path.join(OUT, "rom", "src")
STUBDIR = os.path.join(OUT, "rom", "stubs")

SOURCE_ROOTS = [
    os.path.join(REPO, "LiveProcess"),
    os.path.join(REPO, "Nyxian"),
]
SOURCE_ROOTS = [r for r in SOURCE_ROOTS if os.path.isdir(r)]

FRAMEWORKS = {
    "LiveShim": os.path.join(REPO, "Frameworks", "LiveShim"),
}
FRAMEWORKS = {k: v for k, v in FRAMEWORKS.items() if os.path.isdir(v)}

inc_re = re.compile(r'#\s*(?:include|import)\s*([<"])([^>"]+)[>"]')
SOURCE_PREFIXES = ("LindChain/", "UI/", "Nyxian/")
FRAMEWORK_PREFIXES = tuple(name + "/" for name in FRAMEWORKS)
IN_TREE_PREFIXES = SOURCE_PREFIXES + FRAMEWORK_PREFIXES

framework_index = {}
for name, root in FRAMEWORKS.items():
    exact = {}
    by_base = defaultdict(list)
    by_suffix = defaultdict(list)
    for dp, _, fns in os.walk(root):
        for fn in fns:
            if not fn.endswith((".h", ".hpp")):
                continue
            full = os.path.realpath(os.path.join(dp, fn))
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            exact[rel] = full
            by_base[fn].append(full)
            parts = rel.split("/")
            for i in range(len(parts)):
                by_suffix["/".join(parts[i:])].append(full)
    framework_index[name] = (exact, by_base, by_suffix)

seen_real = set()
copied_virtual = set()
stubbed = set()
ambiguous = set()


def under(path, root):
    try:
        return os.path.commonpath([os.path.realpath(path), os.path.realpath(root)]) == os.path.realpath(root)
    except ValueError:
        return False


def source_virtual_path(real):
    real = os.path.realpath(real)
    for root in SOURCE_ROOTS:
        if under(real, root):
            return os.path.relpath(real, root).replace(os.sep, "/")
    return None


def framework_hit(inc):
    if "/" not in inc:
        return None
    fw, tail = inc.split("/", 1)
    if fw not in framework_index:
        return None
    exact, by_base, by_suffix = framework_index[fw]

    if tail in exact:
        return exact[tail]

    suffix_hits = list(dict.fromkeys(by_suffix.get(tail, [])))
    if len(suffix_hits) == 1:
        return suffix_hits[0]
    if len(suffix_hits) > 1:
        ambiguous.add(inc)
        return None

    base_hits = list(dict.fromkeys(by_base.get(os.path.basename(tail), [])))
    if len(base_hits) == 1:
        return base_hits[0]
    if len(base_hits) > 1:
        ambiguous.add(inc)
    return None


def resolve(inc, delim, including_real, including_virtual):
    cur_real_dir = os.path.dirname(including_real)
    cur_virtual_dir = os.path.dirname(including_virtual)

    if delim == '"':
        sib = os.path.realpath(os.path.join(cur_real_dir, inc))
        if os.path.isfile(sib) and sib != os.path.realpath(including_real):
            virt = os.path.normpath(os.path.join(cur_virtual_dir, inc)).replace(os.sep, "/")
            return sib, virt

    hit = framework_hit(inc)
    if hit:
        return hit, inc

    for root in SOURCE_ROOTS:
        candidate = os.path.realpath(os.path.join(root, inc))
        if os.path.isfile(candidate):
            return candidate, inc

    return None


def copy_and_walk(real, virtual):
    real = os.path.realpath(real)
    virtual = os.path.normpath(virtual).replace(os.sep, "/")
    if virtual.startswith("../") or virtual == "..":
        return

    dest = os.path.join(SRCDIR, *virtual.split("/"))
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if virtual not in copied_virtual:
        if not os.path.exists(dest):
            shutil.copy2(real, dest)
        copied_virtual.add(virtual)

    walk(real, virtual)


def make_stub(inc):
    if inc in stubbed or not inc.endswith((".h", ".hpp")):
        return
    stubbed.add(inc)
    dest = os.path.join(STUBDIR, *inc.split("/"))
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    guard = re.sub(r"[^A-Za-z0-9]", "_", inc).upper()
    with open(dest, "w") as f:
        f.write(
            f"/* AUTO-STUB for {inc}\n"
            "   No matching header exists in Nyxian/LiveProcess/Frameworks.\n"
            "   Fill in only the ABI surface this ROM actually needs. */\n"
            f"#ifndef {guard}\n#define {guard}\n#endif\n"
        )

def walk(real, virtual):
    real = os.path.realpath(real)
    key = (real, virtual)
    if key in seen_real or not os.path.isfile(real):
        return
    seen_real.add(key)

    try:
        text = open(real, "r", errors="ignore").read()
    except OSError:
        return

    for delim, inc in inc_re.findall(text):
        inc = inc.strip()

        is_prefixed = inc.startswith(IN_TREE_PREFIXES)
        resolved = resolve(inc, delim, real, virtual)

        if resolved:
            hit_real, hit_virtual = resolved
            copy_and_walk(hit_real, hit_virtual)
        elif is_prefixed:
            make_stub(inc)

seed_pairs = []
for component in ("LindChain/ProcEnvironment", "LindChain/WindowServer"):
    original = os.path.join(ROOT, component)
    if not os.path.isdir(original):
        continue
    for dp, _, fns in os.walk(original):
        for fn in fns:
            if not fn.endswith((".h", ".hpp", ".c", ".m", ".mm", ".cpp")):
                continue
            real = os.path.join(dp, fn)
            virtual = os.path.relpath(real, ROOT).replace(os.sep, "/")

            if (
                virtual.startswith("LindChain/ProcEnvironment/Shims/")
                or virtual.startswith("LindChain/ProcEnvironment/LiveContainer/Tweaks/")
            ):
                continue
            if virtual == "LindChain/ProcEnvironment/LiveContainer/LCBootstrap.m":
                continue

            if virtual == "LindChain/ProcEnvironment/Surface/cache/shimcache.m":
                continue

            if virtual in (
                "LindChain/WindowServer/Session/NXWindowSessionTerminal.m",
                "LindChain/WindowServer/Session/NXWindowSessionTerminal.h",
            ):
                continue

            seed_pairs.append((real, virtual))
            copied_virtual.add(virtual)

for real, virtual in seed_pairs:
    walk(real, virtual)

print(f"   visited {len(seen_real)} source/header nodes")
print(f"   materialized {len(copied_virtual)} in-tree files")
print(f"   stubbed {len(stubbed)} genuinely unresolved headers -> rom/stubs/")
for s in sorted(stubbed):
    print(f"     stub: {s}")
if ambiguous:
    print("   warning: ambiguous framework header names were not guessed:")
    for s in sorted(ambiguous):
        print(f"     ambiguous: {s}")
PY

mkdir -p "$OUT/rom/src/LindChain/IDEFoundation" "$OUT/rom/src/LindChain/Utils" \
         "$OUT/rom/src/LindChain/Services/bootstrapd" "$OUT/rom/src/ROMCompat"

if [ -f "$ROOT/LindChain/IDEFoundation/NXPlist.m" ]; then
    cp "$ROOT/LindChain/IDEFoundation/NXPlist.m" "$OUT/rom/src/LindChain/IDEFoundation/NXPlist.m"
    python3 - "$OUT/rom/src/LindChain/IDEFoundation/NXPlist.m" <<'PY_PATCH_NXPLIST'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
s = p.read_text()
s = s.replace('#import <CommonCrypto/CommonDigest.h>\n', '')
s = s.replace('#import <LindChain/Utils/Swizzle.h>\n', '')
replacement = '''- (NSString *)currentHash
{
    NSData *fileData = [NSData dataWithContentsOfFile:_plistPath];
    if(fileData == nil) return nil;
    const uint8_t *bytes = fileData.bytes;
    uint64_t hash = 1469598103934665603ULL;
    for(NSUInteger i = 0; i < fileData.length; i++) {
        hash ^= bytes[i];
        hash *= 1099511628211ULL;
    }
    return [NSString stringWithFormat:@"%016llx", (unsigned long long)hash];
}

- (BOOL)reloadIfNeeded'''
s, n = re.subn(r'- \(NSString \*\)currentHash\s*\{.*?\n\}\s*\n- \(BOOL\)reloadIfNeeded', replacement, s, count=1, flags=re.S)
if n != 1: raise SystemExit('could not patch NXPlist currentHash')
p.write_text(s)
PY_PATCH_NXPLIST
fi

if [ -f "$ROOT/LindChain/Utils/Zip.m" ]; then
    cp "$ROOT/LindChain/Utils/Zip.m" "$OUT/rom/src/LindChain/Utils/Zip.m"
fi

LDE_WS_SRC="$REPO/LiveProcess/LindChain/Services/bootstrapd/LDEApplicationWorkspace.m"
LDE_WS_DST="$OUT/rom/src/LindChain/Services/bootstrapd/LDEApplicationWorkspace.m"
if [ -f "$LDE_WS_SRC" ]; then
    cp "$LDE_WS_SRC" "$LDE_WS_DST"
    python3 - "$LDE_WS_DST" <<'PY_PATCH_LDE_WS'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
s = p.read_text()
s = s.replace('#import <LindChain/Private/FoundationPrivate.h>\n', '')
pattern = re.compile(r'#if __has_include\(<Nyxian-Swift\.h>\).*?#endif /\* __has_include\(<Nyxian-Swift\.h>\) \*/', re.S)
replacement = '#define LIVEPROCESS 0\n#import <LindChain/ProcEnvironment/PELaunchServiceManager.h>\n#import <LindChain/ProcEnvironment/PEProcessManager.h>'
s, n = pattern.subn(replacement, s, count=1)
if n != 1: raise SystemExit('could not force host branch in LDEApplicationWorkspace.m')
if '#import <LindChain/ProcEnvironment/PEFileHandle.h>' not in s:
    s = s.replace('#import <LindChain/ProcEnvironment/PEArchiveHandle.h>\n', '#import <LindChain/ProcEnvironment/PEArchiveHandle.h>\n#import <LindChain/ProcEnvironment/PEFileHandle.h>\n')
p.write_text(s)
PY_PATCH_LDE_WS

    python3 - "$LDE_WS_DST" <<'PY_PATCH_LDE_WS_CANONICAL_RETRY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
start = s.index('- (LDEApplicationObject*)applicationObjectForExecutablePath:(NSString*)executablePath')
end = s.index('\n- (NSString*)utilityHomePath', start)
new = r'''- (LDEApplicationObject*)applicationObjectForExecutablePath:(NSString*)executablePath
{
    if(executablePath.length == 0) return nil;

    NSMutableArray<NSString*> *candidates = [NSMutableArray arrayWithObject:executablePath];
    char canonicalPath[PATH_MAX];
    if(realpath(executablePath.fileSystemRepresentation, canonicalPath) != NULL)
    {
        NSString *canonical = [NSString stringWithUTF8String:canonicalPath];
        if(canonical.length && ![canonical isEqualToString:executablePath])
        {
            [candidates addObject:canonical];
        }
    }

    for(NSString *candidate in candidates)
    {
        [self connect];
        if(_connection == nil) continue;

        __block LDEApplicationObject *application = nil;
        __block BOOL failed = NO;
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        id proxy = [_connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
            failed = YES;
            dispatch_semaphore_signal(sema);
        }];
        if(proxy == nil)
        {
            failed = YES;
            dispatch_semaphore_signal(sema);
        }
        else
        {
            [proxy applicationObjectForExecutablePath:candidate withReply:^(LDEApplicationObject *applicationReply) {
                application = applicationReply;
                dispatch_semaphore_signal(sema);
            }];
        }

        long waited = dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));
        if(waited == 0 && !failed && application != nil)
        {
            return application;
        }
        if(failed) [self disconnect];
    }
    return nil;
}
'''
s = s[:start] + new + s[end:]
if '#include <limits.h>\n' not in s:
    s = s.replace('#import <os/lock.h>\n', '#import <os/lock.h>\n#include <limits.h>\n#include <stdlib.h>\n')
p.write_text(s)
PY_PATCH_LDE_WS_CANONICAL_RETRY
fi

cat > "$OUT/rom/src/LindChain/Services/bootstrapd/LDEApplicationObject.m" <<'EOF'
#import <LindChain/Services/bootstrapd/LDEApplicationObject.h>

@implementation LDEApplicationObject

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithNSBundle:(NSBundle *)bundle
{
    self = [super init];
    if(self && bundle)
    {
        self.bundleIdentifier = bundle.bundleIdentifier;
        self.localizedName = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [bundle objectForInfoDictionaryKey:@"CFBundleName"] ?: bundle.bundleIdentifier;
        self.bundlePath = bundle.bundlePath;
        self.executablePath = bundle.executablePath;
        self.iconDictionary = [bundle objectForInfoDictionaryKey:@"CFBundleIcons"];
        self.bundleVersion = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
        self.shortVersionString = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: self.bundleVersion;
        self.sdkVersion = [bundle objectForInfoDictionaryKey:@"DTPlatformVersion"];
        self.minimumSystemVersion = [bundle objectForInfoDictionaryKey:@"MinimumOSVersion"];
        self.entitlements = @{};
        self.isLaunchAllowed = YES;
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.bundleIdentifier forKey:@"bundleIdentifier"];
    [coder encodeObject:self.bundlePath forKey:@"bundlePath"];
    [coder encodeObject:self.executablePath forKey:@"executablePath"];
    [coder encodeObject:self.localizedName forKey:@"localizedName"];
    [coder encodeObject:self.containerPath forKey:@"containerPath"];
    [coder encodeObject:self.icon forKey:@"icon"];
    [coder encodeObject:self.darkIcon forKey:@"darkIcon"];
    [coder encodeObject:self.iconDictionary forKey:@"iconDictionary"];
    [coder encodeObject:self.bundleVersion forKey:@"bundleVersion"];
    [coder encodeObject:self.shortVersionString forKey:@"shortVersionString"];
    [coder encodeObject:self.sdkVersion forKey:@"sdkVersion"];
    [coder encodeObject:self.minimumSystemVersion forKey:@"minimumSystemVersion"];
    [coder encodeObject:self.entitlements forKey:@"entitlements"];
    [coder encodeObject:@(self.supportedInterfaceOrientations) forKey:@"supportedInterfaceOrientations"];
    [coder encodeObject:@(self.isLaunchAllowed) forKey:@"isLaunchAllowed"];
    [coder encodeObject:@(self.isFullscreenRequired) forKey:@"isFullscreenRequired"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if(self)
    {
        _bundleIdentifier = [coder decodeObjectOfClass:NSString.class forKey:@"bundleIdentifier"];
        _bundlePath = [coder decodeObjectOfClass:NSString.class forKey:@"bundlePath"];
        _executablePath = [coder decodeObjectOfClass:NSString.class forKey:@"executablePath"];
        _localizedName = [coder decodeObjectOfClass:NSString.class forKey:@"localizedName"];
        _containerPath = [coder decodeObjectOfClass:NSString.class forKey:@"containerPath"];
        _icon = [coder decodeObjectOfClass:UIImage.class forKey:@"icon"];
        _darkIcon = [coder decodeObjectOfClass:UIImage.class forKey:@"darkIcon"];
        NSSet *plist = [NSSet setWithArray:@[NSDictionary.class, NSArray.class, NSString.class, NSNumber.class, NSData.class]];
        _iconDictionary = [coder decodeObjectOfClasses:plist forKey:@"iconDictionary"];
        _bundleVersion = [coder decodeObjectOfClass:NSString.class forKey:@"bundleVersion"];
        _shortVersionString = [coder decodeObjectOfClass:NSString.class forKey:@"shortVersionString"];
        _sdkVersion = [coder decodeObjectOfClass:NSString.class forKey:@"sdkVersion"];
        _minimumSystemVersion = [coder decodeObjectOfClass:NSString.class forKey:@"minimumSystemVersion"];
        _entitlements = [coder decodeObjectOfClasses:plist forKey:@"entitlements"];
        _supportedInterfaceOrientations = [[coder decodeObjectOfClass:NSNumber.class forKey:@"supportedInterfaceOrientations"] unsignedLongLongValue];
        _isLaunchAllowed = [[coder decodeObjectOfClass:NSNumber.class forKey:@"isLaunchAllowed"] boolValue];
        _isFullscreenRequired = [[coder decodeObjectOfClass:NSNumber.class forKey:@"isFullscreenRequired"] boolValue];
    }
    return self;
}

- (BOOL)isEqual:(id)object
{
    if(self == object)
    {
        return YES;
    }
    if(![object isKindOfClass:LDEApplicationObject.class])
    {
        return NO;
    }
    return [self.bundleIdentifier isEqualToString:((LDEApplicationObject *)object).bundleIdentifier];
}

- (NSUInteger)hash
{
    return self.bundleIdentifier.hash;
}

@end

EOF

# Need CC function for syscall workers
cat > "$OUT/rom/src/ROMCompat/CCCompat.c" <<'EOF'

#include <sys/types.h>
#include <sys/sysctl.h>
#include <stddef.h>

int CCGetMaximumPerformanceCores(void)
{
    int count = 0; size_t size = sizeof(count);
    if(sysctlbyname("hw.perflevel0.physicalcpu", &count, &size, NULL, 0) == 0 && count > 0)
    {
        return count;
    }
    count = 0; size = sizeof(count);
    if(sysctlbyname("hw.physicalcpu", &count, &size, NULL, 0) == 0 && count > 0)
    {
        return count;
    }
    return 1;
}

EOF

# The flashed ROM can carry guest apps beside `main` in Slot/A/Application
FS_M="$OUT/rom/src/LindChain/ProcEnvironment/Surface/fs/fs.m"
if [ -f "$FS_M" ]; then
    python3 - "$FS_M" <<'PY_PATCH_ROM_APPLICATION_MOUNT'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()

if '#include <dlfcn.h>\n' not in s:
    s = s.replace('#include <string.h>\n', '#include <string.h>\n#include <dlfcn.h>\n')

helper = r'''static NSString *NXROMApplicationSourcePath(void)
{
    Dl_info info = {0};
    if(dladdr((const void *)&ksurface_fs_init, &info) == 0 || info.dli_fname == NULL)
    {
        return nil;
    }
    NSString *mainPath = [NSString stringWithUTF8String:info.dli_fname];
    if(mainPath.length == 0)
    {
        return nil;
    }
    return [[[mainPath stringByDeletingLastPathComponent]
             stringByAppendingPathComponent:@"Application"] stringByStandardizingPath];
}

'''
if 'NXROMApplicationSourcePath' not in s:
    marker = 'kern_return_t ksurface_fs_init(void)\n'
    if marker not in s:
        raise SystemExit('ksurface_fs_init marker not found')
    s = s.replace(marker, helper + marker, 1)

sandbox_anchor = '''    kern_return_t kr = ksurface_fs_sandbox_init();
    if(kr != KERN_SUCCESS)
    {
        kpanic("failed to initialize fs sandbox");
    }
'''
sandbox_extra = sandbox_anchor + '''
    NSString *romApplicationSource = NXROMApplicationSourcePath();
    NSString *rootApplicationMount = [NSString stringWithFormat:@"%s/Documents/rootfs/Application", home];
    if(romApplicationSource.length == 0 ||
       ![[NSFileManager defaultManager] fileExistsAtPath:romApplicationSource])
    {
        klog_log("ksurface:fs", "ROM Application source missing: %s",
                 romApplicationSource ? romApplicationSource.fileSystemRepresentation : "(null)");
        return KERN_NOT_FOUND;
    }

    /* The bind mount is read-only. Register the physical source as a read-only
     * sandbox backing region as well, because realpath() canonicalizes the
     * logical rootfs mount to Slot/A/Application before token issuance. */
    kr = ksurface_fs_sandbox_registry_add(kFSMountPermissionRead,
                                          kFSNodeTypeDirectory,
                                          romApplicationSource.fileSystemRepresentation,
                                          NULL);
    if(kr != KERN_SUCCESS)
    {
        klog_log("ksurface:fs", "failed to register ROM Application source sandbox region");
        return kr;
    }
'''
if 'rootApplicationMount' not in s:
    if sandbox_anchor not in s:
        raise SystemExit('sandbox init anchor not found')
    s = s.replace(sandbox_anchor, sandbox_extra, 1)

mount_entry = '''        /* ROM guest applications: immutable payload mounted into rootfs. */
        {
            kFSMountAttrRead,
            romApplicationSource.fileSystemRepresentation,
            rootApplicationMount.fileSystemRepresentation,
        },
        
'''
if 'ROM guest applications: immutable payload mounted into rootfs.' not in s:
    marker = '        /* root mounts */\n'
    if marker not in s:
        raise SystemExit('root mounts marker not found')
    s = s.replace(marker, mount_entry + marker, 1)

p.write_text(s)
PY_PATCH_ROM_APPLICATION_MOUNT
fi

# bootstrapd resolves application metadata over XPC before PEProcess launches a
# graphical guest. Grant that daemon read-only access to the logical /Application
# mount; the filesystem registry above maps the token to the physical ROM slot.
PRESETS_M="$OUT/rom/src/LindChain/ProcEnvironment/Surface/trust/presets.m"
if [ -f "$PRESETS_M" ]; then
    python3 - "$PRESETS_M" <<'PY_PATCH_BOOTSTRAPD_APPLICATION_READ'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
needle = '''        /* sandbox */
        (__bridge NSString*)kNXT2EntitlementSandboxFileReadWrite: @[
'''
replacement = '''        /* sandbox */
        (__bridge NSString*)kNXT2EntitlementSandboxFileRead: @[
            @"$(NXROOT)/Application",           /* read only ROM application payloads */
        ],
        (__bridge NSString*)kNXT2EntitlementSandboxFileReadWrite: @[
'''
if '@"$(NXROOT)/Application"' not in s:
    if needle not in s:
        raise SystemExit('bootstrapd sandbox preset anchor not found')
    s = s.replace(needle, replacement, 1)
p.write_text(s)
PY_PATCH_BOOTSTRAPD_APPLICATION_READ
fi

TRUST_M="$OUT/rom/src/LindChain/ProcEnvironment/Surface/trust/trust.m"
if [ -f "$TRUST_M" ]; then
    python3 - "$TRUST_M" <<'PY_PATCH_MOUNTED_APP_BUNDLE_PERMISSION'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = r'''        LDEApplicationObject *applicationObject = [[LDEApplicationWorkspace shared] applicationObjectForExecutablePath:(__bridge NSString*)executableString];
        if(applicationObject != nil && applicationObject.bundlePath != nil && applicationObject.containerPath != nil)
        {
            /* is a application bundle */
            vars[@"CONTAINER"] = applicationObject.containerPath;
            vars[@"BUNDLE"] = applicationObject.bundlePath;
        }
'''
new = r'''        NSString *executablePath = (__bridge NSString*)executableString;
        LDEApplicationObject *applicationObject = [[LDEApplicationWorkspace shared] applicationObjectForExecutablePath:executablePath];
        if(applicationObject.bundlePath.length > 0)
        {
            vars[@"BUNDLE"] = applicationObject.bundlePath;
        }
        if(applicationObject.containerPath.length > 0)
        {
            vars[@"CONTAINER"] = applicationObject.containerPath;
        }

        /* Mounted ROM applications are immutable bundles, not installed apps.
         * Infer their .app root so dyld/Foundation get read access without a
         * writable application container. */
        if(vars[@"BUNDLE"] == nil)
        {
            NSString *candidateBundle = [executablePath stringByDeletingLastPathComponent];
            if([[candidateBundle pathExtension] isEqualToString:@"app"])
            {
                vars[@"BUNDLE"] = candidateBundle;
            }
        }
'''
if old not in s: raise SystemExit('trust bundle anchor not found')
s=s.replace(old,new,1)
p.write_text(s)
PY_PATCH_MOUNTED_APP_BUNDLE_PERMISSION
fi

# Last fix
if grep -R -q '@protocol[[:space:]]\+PEServiceProtocol' "$OUT/rom/src/LiveShim" 2>/dev/null; then
    :
else
    echo "error: PEServiceProtocol was not resolved from Frameworks/LiveShim" >&2
    echo "       expected Frameworks/LiveShim/ServiceKit/ServiceProtocol.h" >&2
    exit 1
fi

# NXBootstrap template
mkdir -p "$OUT/rom/src/LindChain/IDEFoundation"
cat > "$OUT/rom/src/LindChain/IDEFoundation/NXBootstrap.h" <<'EOF'
#ifndef NXBOOTSTRAP_H
#define NXBOOTSTRAP_H

#import <Foundation/Foundation.h>

#define NXBOOTSTRAP_NEWEST_VERSION 1

@interface NXBootstrap : NSObject

@property (nonatomic, readonly, strong, nonnull) NSURL *rootURL;
@property (nonatomic, readonly, strong, nonnull) NSURL *sdkURL;
@property (nonatomic, readonly, strong, nonnull) NSURL *includeURL;
@property (nonatomic, readonly, strong, nonnull) NSURL *projectsURL;
@property (nonatomic, readonly, strong, nonnull) NSURL *cacheURL;
@property (nonatomic, readonly, strong, nonnull) NSURL *bootstrapPlistURL;
@property (nonatomic, readonly, strong, nonnull) NSURL *swiftURL;
@property (nonatomic, readonly, strong, nonnull) NSURL *swiftModuleCacheURL;
@property (nonatomic, readonly, strong, nonnull) NSURL *rootfsURL;
@property (atomic, readonly) UInt64 version;
@property (atomic, readonly) BOOL isInstalled;

+ (instancetype _Nonnull)shared;
- (void)bootstrap;
- (NSString * _Nullable)relativeToBootstrapWithAbsolutePath:(NSString * _Nonnull)path;
- (void)clearURL:(NSURL * _Nonnull)url;
- (void)waitTillDone;
- (void)waitTillDoneNoButton;
- (BOOL)isNewest;

@end

#endif /* NXBOOTSTRAP_H */
EOF

cat > "$OUT/rom/src/LindChain/IDEFoundation/NXBootstrap.m" <<'EOF'
#import <LindChain/IDEFoundation/NXBootstrap.h>

@implementation NXBootstrap {
    dispatch_group_t _bootstrapGroup;
    dispatch_once_t _bootstrapOnce;
    BOOL _bootstrapSucceeded;
}

+ (instancetype)shared
{
    static NXBootstrap *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[NXBootstrap alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if(self)
    {
        _bootstrapGroup = dispatch_group_create();
        dispatch_group_enter(_bootstrapGroup);
    }
    return self;
}

- (NSURL *)rootURL
{
    static NSURL *url;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *home = NSHomeDirectory();
        if(![home hasPrefix:@"/private/"])
        {
            home = [@"/private" stringByAppendingPathComponent:home];
        }
        url = [NSURL fileURLWithPath:[home stringByAppendingPathComponent:@"Documents"] isDirectory:YES];
    });
    return url;
}

- (NSURL *)rootfsURL { return [self.rootURL URLByAppendingPathComponent:@"rootfs" isDirectory:YES]; }
- (NSURL *)sdkURL { return [self.rootURL URLByAppendingPathComponent:@"SDK" isDirectory:YES]; }
- (NSURL *)includeURL { return [self.rootURL URLByAppendingPathComponent:@"Include" isDirectory:YES]; }
- (NSURL *)projectsURL { return [self.rootURL URLByAppendingPathComponent:@"Projects" isDirectory:YES]; }
- (NSURL *)cacheURL { return [self.rootURL URLByAppendingPathComponent:@"Cache" isDirectory:YES]; }
- (NSURL *)bootstrapPlistURL { return [self.rootURL URLByAppendingPathComponent:@"bootstrap.plist"]; }
- (NSURL *)swiftURL { return [self.rootURL URLByAppendingPathComponent:@"swift" isDirectory:YES]; }
- (NSURL *)swiftModuleCacheURL { return [self.rootURL URLByAppendingPathComponent:@"ModuleCache" isDirectory:YES]; }

- (UInt64)version
{
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfURL:self.bootstrapPlistURL];
    NSNumber *n = plist[@"BootstrapVersion"];
    return [n isKindOfClass:NSNumber.class] ? n.unsignedLongLongValue : 0;
}

- (BOOL)isInstalled { return self.version > 0; }
- (BOOL)isNewest { return self.version >= NXBOOTSTRAP_NEWEST_VERSION; }

- (void)bootstrap
{
    dispatch_once(&_bootstrapOnce, ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSError *error = nil;
        NSArray<NSURL *> *directories = @[
            self.rootURL,
            self.rootfsURL,
            [self.rootfsURL URLByAppendingPathComponent:@"tmp" isDirectory:YES],
            [self.rootURL URLByAppendingPathComponent:@"mntfs/bootfs" isDirectory:YES],
            [self.rootURL URLByAppendingPathComponent:@"mntfs/lsfs" isDirectory:YES],
            [self.rootURL URLByAppendingPathComponent:@"RootCAs" isDirectory:YES],
        ];
        
        BOOL ok = YES;
        for (NSURL *url in directories) {
            if (![fm createDirectoryAtURL:url
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&error]) {
                NSLog(@"NXBootstrap: failed to create %@: %@", url.path, error);
                ok = NO;
                break;
            }
        }
        
        if(ok)
        {
            NSDictionary *plist = @{ @"BootstrapVersion": @(NXBOOTSTRAP_NEWEST_VERSION) };
            ok = [plist writeToURL:self.bootstrapPlistURL atomically:YES];
        }
        _bootstrapSucceeded = ok;
        dispatch_group_leave(_bootstrapGroup);
    });
}

- (void)waitTillDone
{
    dispatch_group_wait(_bootstrapGroup, DISPATCH_TIME_FOREVER);
}

- (void)waitTillDoneNoButton
{
    [self waitTillDone];
}

- (void)clearURL:(NSURL *)url
{
    if(url)
    {
        [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    }
}

- (NSString *)relativeToBootstrapWithAbsolutePath:(NSString *)path
{
    if(!path)
    {
        return nil;
    }
    NSString *root = self.rootURL.path.stringByStandardizingPath;
    NSString *candidate = path.stringByStandardizingPath;
    if([candidate isEqualToString:root])
    {
        return @"";
    }
    NSString *prefix = [root stringByAppendingString:@"/"];
    return [candidate hasPrefix:prefix] ? [candidate substringFromIndex:prefix.length] : nil;
}

@end
EOF

# The application PoC
mkdir -p "$OUT/appsrc/Hello"
cat > "$OUT/appsrc/Hello/main.m" <<'EOF'
#import <UIKit/UIKit.h>

@interface HelloViewController : UIViewController

@property (nonatomic, strong) UILabel *statusLabel;

@end

@implementation HelloViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"sparkles"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = UIColor.systemIndigoColor;
    [icon.widthAnchor constraintEqualToConstant:72.0].active = YES;
    [icon.heightAnchor constraintEqualToConstant:72.0].active = YES;
    
    UILabel *title = [UILabel new];
    title.text = @"Hello!";
    title.font = [UIFont systemFontOfSize:34.0 weight:UIFontWeightBold];
    title.textAlignment = NSTextAlignmentCenter;
    
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 18.0;
    [self.view addSubview:stack];
    
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:24.0],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-24.0],
        [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

@end

@interface HelloSceneDelegate : UIResponder <UIWindowSceneDelegate>

@property (nonatomic, strong) UIWindow *window;

@end

@implementation HelloSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions
{
    if(![scene isKindOfClass:UIWindowScene.class])
    {
        return;
    }
    
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    window.rootViewController = [HelloViewController new];
    self.window = window;
    [window makeKeyAndVisible];
}

@end

@interface HelloAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation HelloAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options
{
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
    configuration.delegateClass = HelloSceneDelegate.class;
    return configuration;
}

@end

__attribute__((visibility("default")))
int main(int argc, char *argv[])
{
    @autoreleasepool
    {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(HelloAppDelegate.class));
    }
}

EOF

cat > "$OUT/appsrc/Hello/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>Hello</string>
    <key>CFBundleExecutable</key><string>Hello</string>
    <key>CFBundleIdentifier</key><string>org.emexlabs.rom.hello</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Hello</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSRequiresIPhoneOS</key><true/>
    <key>MinimumOSVersion</key><string>18.0</string>
    <key>UIRequiresFullScreen</key><false/>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key><false/>
        <key>UISceneConfigurations</key>
        <dict>
            <key>UIWindowSceneSessionRoleApplication</key>
            <array>
                <dict>
                    <key>UISceneConfigurationName</key><string>Default Configuration</string>
                    <key>UISceneDelegateClassName</key><string>HelloSceneDelegate</string>
                </dict>
            </array>
        </dict>
    </dict>
</dict>
</plist>
EOF

# Now the slot boot helper shit
cat > "$OUT/rom/src/NXMainSlot.m" <<'EOF'
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <errno.h>
#import <string.h>
#include <limits.h>
#include <stdlib.h>
#import <LindChain/IDEFoundation/NXBootstrap.h>
#import <LindChain/ProcEnvironment/PEUserspaceManager.h>
#import <LindChain/ProcEnvironment/PEProcessManager.h>
#import <LindChain/Services/bootstrapd/LDEApplicationObject.h>
#import <LindChain/ProcEnvironment/Surface/trust/trust.h>
#import <LindChain/ProcEnvironment/Surface/libkern/klog.h>
#import <LindChain/WindowServer/NXWindowServer.h>
#import <LindChain/WindowServer/Session/NXWindowSessionApplication.h>

static BOOL NXROMDefaultBool(NSString *key, BOOL fallback)
{
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return value ? [value boolValue] : fallback;
}

static LDEApplicationObject *NXROMLocalApplicationObject(NSString *helloPath)
{
    NSString *bundlePath = [helloPath stringByDeletingLastPathComponent];
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    
    if(bundle == nil || bundle.bundleIdentifier.length == 0)
    {
        char resolvedBundle[PATH_MAX];
        if(realpath(bundlePath.fileSystemRepresentation, resolvedBundle) != NULL)
        {
            NSString *physicalBundlePath = [NSString stringWithUTF8String:resolvedBundle];
            bundle = [NSBundle bundleWithPath:physicalBundlePath];
        }
    }
    
    if(bundle == nil || bundle.bundleIdentifier.length == 0)
    {
        return nil;
    }
    return [[LDEApplicationObject alloc] initWithNSBundle:bundle];
}

static void NXROMLaunchHelloPoC(void)
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *helloPath = [NXBootstrap.shared.rootfsURL.path stringByAppendingPathComponent:@"Application/Hello.app/Hello"];
        if(![NSFileManager.defaultManager isReadableFileAtPath:helloPath])
        {
            return;
        }
        
        LDEApplicationObject *application = NXROMLocalApplicationObject(helloPath);
        if(application == nil || application.bundleIdentifier.length == 0)
        {
            return;
        }
        
        NSDictionary *items = @{
            @"PEExecutablePath": helloPath,
            @"PEArguments": @[ helloPath ],
            @"PEWorkingDirectory": NXBootstrap.shared.rootfsURL.path,
            @"PEEnvironment": @{},
        };
        
        pid_t pid = [[PEProcessManager shared] spawnProcessWithItems:items withKernelSurfaceProcess:NULL];
        if(pid < 0)
        {
            return;
        }
        
        PEProcess *process = [[PEProcessManager shared] processForProcessIdentifier:pid];
        if(process != nil)
        {
            process.applicationObject = application;
            process.bundleIdentifier = application.bundleIdentifier;
            process.displayName = application.localizedName.length > 0 ? application.localizedName : @"Hello";
        }
    });
}

@interface NXROMRootViewController : UIViewController
@end

@implementation NXROMRootViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    
    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"ROM";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    title.textAlignment = NSTextAlignmentCenter;
    
    UIButton *launch = [UIButton buttonWithType:UIButtonTypeSystem];
    launch.translatesAutoresizingMaskIntoConstraints = NO;
    [launch setTitle:@"Launch Hello.app" forState:UIControlStateNormal];
    launch.titleLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
    launch.contentEdgeInsets = UIEdgeInsetsMake(12.0, 22.0, 12.0, 22.0);
    [launch addTarget:self action:@selector(launchHelloTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIButton *showAppSwitcher = [UIButton buttonWithType:UIButtonTypeSystem];
    showAppSwitcher.translatesAutoresizingMaskIntoConstraints = NO;
    [showAppSwitcher setTitle:@"Show App Switcher" forState:UIControlStateNormal];
    showAppSwitcher.titleLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
    showAppSwitcher.contentEdgeInsets = UIEdgeInsetsMake(12.0, 22.0, 12.0, 22.0);
    [showAppSwitcher addTarget:self action:@selector(showAppSwitcher:) forControlEvents:UIControlEventTouchUpInside];
    [showAppSwitcher setEnabled:(UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone)];
    
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, launch, showAppSwitcher]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 18.0;
    [self.view addSubview:stack];
    
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:24.0],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-24.0],
        [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (void)launchHelloTapped:(UIButton *)sender
{
    NXROMLaunchHelloPoC();
}

- (void)showAppSwitcher:(UIButton *)sender
{
    [[NXWindowServer shared] showAppSwitcherExternal];
}

@end

UIViewController *NXMainSlot(void)
{
    NSString *mode = [NSUserDefaults.standardUserDefaults stringForKey:@"nyxian.boot.entitlements.mode"];
    PEEnforcementMode enforcement = kPEEnforcementModeEnforcing;
    if([mode isEqualToString:@"permissive"])
    {
        enforcement = kPEEnforcementModePermissive;
    }
    else if ([mode isEqualToString:@"disabled"])
    {
        enforcement = kPEEnforcementModeDisabled;
    }
    
    trust_enforcement_set_mode(enforcement);
    klog_set_obfuscation(NXROMDefaultBool(@"nyxian.boot.log.obfuscated", YES));
    
    [[NXBootstrap shared] bootstrap];
    [[NXBootstrap shared] waitTillDoneNoButton];
    
    BOOL loadKexts = NXROMDefaultBool(@"nyxian.boot.kextLoading", YES);
    [[PEUserspaceManager shared] bootWithKextLoadingEnabled:loadKexts];
    
    return [NXROMRootViewController new];
}

__attribute__((visibility("default")))
void *NXSlotMain(void)
{
    UIViewController *root = NXMainSlot();
    return (__bridge_retained void *)root;
}

__attribute__((visibility("default")))
void *NXSlotCreateWindow(void *scenePtr)
{
    if(scenePtr == NULL)
    {
        return NULL;
    }
    UIWindowScene *scene = (__bridge UIWindowScene *)scenePtr;
    NXWindowServer *window = [NXWindowServer sharedWithWindowScene:scene];
    return window ? (__bridge_retained void *)window : NULL;
}

__attribute__((visibility("default")))
void NXSlotDidAppear(void)
{
    [[NXWindowServer shared] makeKeyAndVisible];
}
EOF

# MAKEFILE ^^
cat > "$OUT/Makefile" <<'EOF'
# Makefile

SDK         := iphoneos
ARCH        := arm64
MIN_IOS     := 18.0
NAME        := main
SRCDIR      := rom/src
ZSIGNDIR    := $(SRCDIR)/LindChain/ProcEnvironment/LiveContainer/ZSign
INCDIRS     := -Irom/src -Irom/stubs -Irom/include -I$(ZSIGNDIR) -I$(ZSIGNDIR)/common
FWFLAGS     := -From/frameworks
CC          := $(shell xcrun -sdk $(SDK) -f clang)
LD          := $(shell xcrun -sdk $(SDK) -f clang++)
SYSROOT     := $(shell xcrun -sdk $(SDK) --show-sdk-path)

HELLO_SRC   := appsrc/Hello/main.m
HELLO_PLIST := appsrc/Hello/Info.plist
HELLO_APP   := Application/Hello.app
HELLO_BIN   := $(HELLO_APP)/Hello

SRCS_ALL    := $(shell find $(SRCDIR) \( -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp' \))
SRCS        := $(filter-out \
               $(SRCDIR)/LindChain/ProcEnvironment/Shims/% \
               $(SRCDIR)/LindChain/ProcEnvironment/LiveContainer/Tweaks/% \
               $(SRCDIR)/LindChain/ProcEnvironment/LiveContainer/LCBootstrap.m, \
               $(SRCS_ALL))
OBJS        := $(SRCS:%=build/%.o)

CFLAGS      := -arch $(ARCH) -isysroot $(SYSROOT) -miphoneos-version-min=$(MIN_IOS) \
               -fobjc-arc -O2 -g -DHOST_ENV=1 -Wno-nonportable-include-path $(INCDIRS)
LDFLAGS     := -arch $(ARCH) -isysroot $(SYSROOT) -miphoneos-version-min=$(MIN_IOS) \
               -dynamiclib -install_name @rpath/$(NAME) \
               -rpath @executable_path/Frameworks $(FWFLAGS) \
               -framework Foundation -framework UIKit -framework CoreFoundation \
               -framework CoreGraphics -framework QuartzCore -framework Security \
               -framework FrontBoard -framework OpenSSL -larchive
HELLO_FLAGS := -arch $(ARCH) -isysroot $(SYSROOT) -miphoneos-version-min=$(MIN_IOS) \
               -fobjc-arc -Os -framework Foundation -framework UIKit

all: rom.zip

build/%.o: %
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(NAME): $(OBJS)
	$(LD) $(LDFLAGS) $(OBJS) -o $(NAME)

$(HELLO_BIN): $(HELLO_SRC) $(HELLO_PLIST)
	rm -rf $(HELLO_APP)
	mkdir -p $(HELLO_APP)
	cp $(HELLO_PLIST) $(HELLO_APP)/Info.plist
	$(CC) $(HELLO_FLAGS) -dynamiclib -Wl,-install_name,@rpath/Hello $(HELLO_SRC) -o $(HELLO_BIN)

manifest.sign: $(NAME) $(HELLO_BIN)
	printf '%s\n' '$(NAME)' '$(HELLO_BIN)' > manifest.sign

rom.zip: $(NAME) $(HELLO_BIN) manifest.sign
	rm -rf .rompkg rom.zip
	mkdir -p .rompkg/ROM
	cp $(NAME) manifest.sign .rompkg/ROM/
	cp -R Application .rompkg/ROM/Application
	cd .rompkg && zip -r ../rom.zip ROM
	rm -rf .rompkg

clean:
	rm -rf build .rompkg Application $(NAME) manifest.sign rom.zip

.PHONY: all clean
EOF

cat > "$OUT/README.md" <<'EOF'
# Nyxian ROM skeleton

Generated by `gen-rom.sh` from a Nyxian checkout.

## Build

    make
    make clean

`make`

EOF

chmod +x "$OUT/rom/src/NXMainSlot.m" 2>/dev/null || true

echo ">> done. Next: cd $OUT && make clean && make"
