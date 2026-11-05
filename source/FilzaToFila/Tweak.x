// FilzaToFila: RootHide / iOS 17.2 compatibility adaptation
// Original author: 时间会惩罚我 (based on com.shijian.filzatofila 0.0.1-2).
// This repository version adapts the original tweak for the author's iOS 17.2
// RootHide device and Filza bundle id com.bat.petal. Original behavior and
// fila://view<Filza current path> routing are retained; hooks, menu filtering,
// path discovery, RootHide packaging, and diagnostics were adapted.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <roothide.h>

static NSString *const kActionTitle = @"用 Fila 打开";
static NSString *FTF_LogPath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"filzatofila.log"];
}

static void FTFLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], msg];
    NSString *path = FTF_LogPath();
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [line writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (fh) { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
}

#pragma mark - 路径

static BOOL FTF_IsBV(UIView *v) {
    if (!v) return NO;
    NSString *c = NSStringFromClass([v class]);
    if (c.length == 0) return NO;
    if ([c isEqualToString:@"TIGIBrowserView"]) return YES;
    return ([c containsString:@"Browser"] && [c containsString:@"View"]);
}

static UIView *FTF_FindBV(UIView *root) {
    if (!root) return nil;
    if (FTF_IsBV(root)) return root;
    for (UIView *s in root.subviews) { UIView *f = FTF_FindBV(s); if (f) return f; }
    return nil;
}

static NSString *FTF_StringCandidate(id obj, NSString *owner) {
    if (!obj || obj == [NSNull null]) return nil;
    Class cls = object_getClass(obj);
    NSString *className = NSStringFromClass(cls);
    static NSArray *keys; static dispatch_once_t once;
    dispatch_once(&once, ^{ keys = @[@"_currentPath", @"currentPath", @"_currentDirectory", @"currentDirectory", @"_directoryPath", @"directoryPath", @"_path", @"path"]; });

    for (NSString *key in keys) {
        @try {
            id val = [obj valueForKey:key];
            if ([val isKindOfClass:[NSString class]] && [val length] > 0) {
                FTFLog(@"PATH HIT owner=%@ class=%@ key=%@ value=%@", owner, className, key, val);
                return val;
            }
            if ([val isKindOfClass:[NSURL class]] && [(NSURL *)val path].length > 0) {
                FTFLog(@"PATH HIT owner=%@ class=%@ key=%@ url=%@", owner, className, key, val);
                return [(NSURL *)val path];
            }
        } @catch (NSException *e) {}
    }

    // Inspect ivar names and invoke only conventional zero-argument path getters.
    for (Class c = cls; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(c, &count);
        for (unsigned int i = 0; i < count; i++) {
            const char *rawName = ivar_getName(ivars[i]);
            if (!rawName) continue;
            NSString *name = [NSString stringWithUTF8String:rawName];
            NSString *lower = name.lowercaseString;
            if (![lower containsString:@"path"] && ![lower containsString:@"director"]) continue;
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (!type || type[0] != '@') continue;
            @try {
                id val = object_getIvar(obj, ivars[i]);
                FTFLog(@"IVAR owner=%@ class=%@ %@ -> %@ (%@)", owner, NSStringFromClass(c), name, val, val ? NSStringFromClass([val class]) : @"nil");
                if ([val isKindOfClass:[NSString class]] && [val length] > 0) {
                    free(ivars); FTFLog(@"PATH HIT ivar %@", name); return val;
                }
                if ([val isKindOfClass:[NSURL class]] && [(NSURL *)val path].length > 0) {
                    NSString *path = [(NSURL *)val path]; free(ivars); FTFLog(@"PATH HIT ivar %@", name); return path;
                }
            } @catch (NSException *e) {}
        }
        free(ivars);
    }
    NSArray *getters = @[@"currentPath", @"currentDirectory", @"path", @"directoryPath"];
    for (NSString *g in getters) {
        SEL sel = NSSelectorFromString(g);
        if (![obj respondsToSelector:sel]) continue;
        @try {
            id (*send)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
            id val = send(obj, sel);
            FTFLog(@"GETTER owner=%@ class=%@ %@ -> %@", owner, className, g, val);
            if ([val isKindOfClass:[NSString class]] && [val length] > 0) return val;
            if ([val isKindOfClass:[NSURL class]] && [(NSURL *)val path].length > 0) return [(NSURL *)val path];
        } @catch (NSException *e) {}
    }
    return nil;
}

static NSString *FTF_PathFromBV(UIView *bv) {
    if (!bv) return nil;
    NSMutableArray *objects = [NSMutableArray array];
    NSMutableArray *labels = [NSMutableArray array];
    id cur = bv;
    for (NSInteger i = 0; cur && i < 8; i++) {
        [objects addObject:cur]; [labels addObject:[NSString stringWithFormat:@"responder[%ld]", (long)i]];
        if (![cur respondsToSelector:@selector(nextResponder)]) break;
        cur = [cur nextResponder];
    }
    for (NSString *key in @[@"dataSource", @"delegate", @"browserView", @"viewController"]) {
        @try {
            id val = [bv valueForKey:key];
            if (val && val != bv && ![objects containsObject:val]) { [objects addObject:val]; [labels addObject:key]; }
        } @catch (NSException *e) {}
    }
    for (NSUInteger i = 0; i < objects.count; i++) {
        NSString *p = FTF_StringCandidate(objects[i], labels[i]);
        if (p.length > 0) return p;
    }
    FTFLog(@"BV path unresolved class=%@ candidates=%lu", NSStringFromClass([bv class]), (unsigned long)objects.count);
    return nil;
}

static NSArray *FTF_Wins(void) {
    NSMutableArray *a = [NSMutableArray array];
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows) [a addObject:w];
    }
    return a;
}

static void FTF_CollectBrowserViews(UIView *root, NSMutableArray<UIView *> *out) {
    if (!root) return;
    if (FTF_IsBV(root)) [out addObject:root];
    for (UIView *sub in root.subviews) FTF_CollectBrowserViews(sub, out);
}

static NSString *FTF_PathForViewChain(UIView *bv, NSString **ownerOut) {
    id cur = bv;
    for (NSInteger depth = 0; cur && depth < 8; depth++) {
        NSString *label = [NSString stringWithFormat:@"responder[%ld]:%@", (long)depth, NSStringFromClass([cur class])];
        NSString *p = FTF_StringCandidate(cur, label);
        if (p.length > 0) { if (ownerOut) *ownerOut = label; return p; }
        if (![cur respondsToSelector:@selector(nextResponder)]) break;
        cur = [cur nextResponder];
    }
    for (NSString *key in @[@"dataSource", @"delegate", @"browserView", @"viewController"]) {
        @try {
            id obj = [bv valueForKey:key];
            if (!obj || obj == bv) continue;
            NSString *label = [NSString stringWithFormat:@"%@:%@", key, NSStringFromClass([obj class])];
            NSString *p = FTF_StringCandidate(obj, label);
            if (p.length > 0) { if (ownerOut) *ownerOut = label; return p; }
        } @catch (NSException *e) {}
    }
    return nil;
}

static NSString *FTF_CurPath(void) {
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    for (UIWindow *w in FTF_Wins()) FTF_CollectBrowserViews(w, views);
    FTFLog(@"browser views found=%lu", (unsigned long)views.count);
    NSString *bestPath = nil;
    NSString *bestOwner = nil;
    NSInteger bestScore = -1;
    for (NSUInteger i = 0; i < views.count; i++) {
        UIView *bv = views[i];
        NSString *owner = nil;
        NSString *path = FTF_PathForViewChain(bv, &owner);
        BOOL visible = !bv.hidden && bv.alpha > 0.01 && bv.window != nil;
        BOOL onscreen = visible && CGRectIntersectsRect(bv.bounds, bv.window.bounds);
        NSInteger score = (onscreen ? 1000 : 0) + (visible ? 100 : 0) + (NSInteger)i;
        FTFLog(@"BV[%lu] class=%@ visible=%d onscreen=%d frame=%@ path=%@ owner=%@", (unsigned long)i, NSStringFromClass([bv class]), visible, onscreen, NSStringFromCGRect([bv convertRect:bv.bounds toView:bv.window]), path, owner);
        if (path.length > 0 && score >= bestScore) {
            bestScore = score; bestPath = path; bestOwner = owner;
        }
    }
    FTFLog(@"selected current path=%@ owner=%@ score=%ld", bestPath, bestOwner, (long)bestScore);
    return bestPath;
}

#pragma mark - 识别

static BOOL FTF_Strong(NSString *t) {
    if (t.length == 0) return NO;
    static NSArray *a; static dispatch_once_t o;
    dispatch_once(&o, ^{ a = @[@"重命名", @"属性", @"屬性", @"資訊", @"压缩", @"壓縮",
        @"回收站", @"移动", @"移動", @"解压", @"解壓", @"Rename", @"Properties",
        @"Get Info", @"Compress", @"Decompress", @"Trash", @"Move"]; });
    for (NSString *k in a) if ([t localizedCaseInsensitiveContainsString:k]) return YES;
    return NO;
}

static BOOL FTF_Weak(NSString *t) {
    if (t.length == 0) return NO;
    static NSArray *a; static dispatch_once_t o;
    dispatch_once(&o, ^{ a = @[@"复制", @"拷貝", @"拷贝", @"删除", @"刪除",
        @"Copy", @"Delete", @"Share", @"分享"]; });
    for (NSString *k in a) if ([t localizedCaseInsensitiveContainsString:k]) return YES;
    return NO;
}

static BOOL FTF_HasAction(NSArray *c) {
    for (id it in c)
        if ([it isKindOfClass:[UIAction class]] &&
            [[(UIAction *)it title] isEqualToString:kActionTitle]) return YES;
    return NO;
}

static BOOL FTF_IsFileMenu(NSArray *c) {
    if (c.count == 0) return NO;
    NSInteger s = 0, w = 0;
    BOOL hasRenameAction = NO;
    for (id it in c) {
        // Only inspect actions. Parent/section UIMenu titles such as "回收站"
        // belong to nested groups and must not independently trigger injection.
        if (![it isKindOfClass:[UIAction class]]) continue;
        NSString *t = [(UIAction *)it title];
        if (t.length == 0) continue;
        if ([t localizedCaseInsensitiveContainsString:@"重命名"] ||
            [t localizedCaseInsensitiveContainsString:@"Rename"]) {
            hasRenameAction = YES;
        }
        if (FTF_Strong(t)) s++; else if (FTF_Weak(t)) w++;
    }
    // The file's primary context menu has Rename; nested groups do not.
    if (hasRenameAction && (s >= 1 || w >= 2)) {
        FTFLog(@"命中主文件菜单 s=%ld w=%ld n=%lu", (long)s, (long)w, (unsigned long)c.count);
        return YES;
    }
    return NO;
}

#pragma mark - 注入

static NSArray *FTF_Inject(NSArray *children, NSString *from, NSString *targetName) {
    if (![children isKindOfClass:[NSArray class]] || children.count == 0) return children;
    if (FTF_HasAction(children)) { FTFLog(@"[%@] 已有,跳过", from); return children; }
    if (!FTF_IsFileMenu(children)) return children;

    UIImage *icon = [UIImage systemImageNamed:@"arrow.up.forward.app"];
    UIAction *act = [UIAction actionWithTitle:kActionTitle image:icon identifier:nil
                                      handler:^(UIAction *a) {
        FTFLog(@"=== 点击 ===");
        NSString *p = FTF_CurPath();
        if (p.length == 0) { FTFLog(@"路径空"); return; }

        if (targetName.length == 0) {
            FTFLog(@"菜单标题为空，无法确定被长按项目");
            return;
        }

        // Resolve the selected item in Filza's current directory or in the
        // Fila-visible shared Documents namespace, then always open its parent.
        // Match the original tweak: send Filza's current browser path directly.
        // This is the containing directory for both file and folder selections.
        NSString *targetPath = p;
        FTFLog(@"Original route: current directory=%@ selected=%@", targetPath, targetName);
        if (targetPath.length == 0) {
            FTFLog(@"Filza current path is empty");
            return;
        }
        NSString *enc = [targetPath stringByAddingPercentEncodingWithAllowedCharacters:
                            [NSCharacterSet URLPathAllowedCharacterSet]];
        if (enc.length == 0) enc = targetPath;

        // Match the reverse tweak's view route, but pass the full target path.
        NSString *urlString = [NSString stringWithFormat:@"fila://view%@", enc];
        NSURL *url = [NSURL URLWithString:urlString];
        FTFLog(@"准备打开 scheme=%@ host=%@ path=%@ full=%@",
               url.scheme, url.host, url.path, url.absoluteString);
        if (!url) { FTFLog(@"URL 创建失败"); return; }
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL ok) {
            FTFLog(@"openURL completion=%d", ok);
        }];
    }];

    NSMutableArray *m = [children mutableCopy];
    [m insertObject:act atIndex:0];
    FTFLog(@"[%@] 注入 %lu->%lu", from, (unsigned long)children.count, (unsigned long)m.count);
    return [m copy];
}

@interface FTFInjector : NSObject
+ (NSArray *)inject:(NSArray *)c from:(NSString *)f target:(NSString *)t;
@end
@implementation FTFInjector
+ (NSArray *)inject:(NSArray *)c from:(NSString *)f target:(NSString *)t {
    @try { return FTF_Inject(c, f, t); }
    @catch (NSException *e) { FTFLog(@"异常 %@", e.reason); return c; }
}
@end

#pragma mark - Hook

%hook UIMenu

+ (instancetype)menuWithChildren:(NSArray *)c {
    FTFLog(@"+menuWithChildren n=%lu", (unsigned long)c.count);
    return %orig([FTFInjector inject:c from:@"+menuWithChildren" target:nil]);
}
+ (instancetype)menuWithTitle:(NSString *)t children:(NSArray *)c {
    FTFLog(@"+menuWithTitle:children t=%@ n=%lu", t, (unsigned long)c.count);
    return %orig(t, [FTFInjector inject:c from:@"+menuWithTitle:children" target:t]);
}
+ (instancetype)menuWithTitle:(NSString *)t image:(UIImage *)i identifier:(NSString *)d
                      options:(UIMenuOptions)o children:(NSArray *)c {
    FTFLog(@"+menuWithTitle:image t=%@ n=%lu", t, (unsigned long)c.count);
    return %orig(t, i, d, o, [FTFInjector inject:c from:@"+menuWithTitle:image" target:t]);
}

- (instancetype)initWithChildren:(NSArray *)c {
    FTFLog(@"-initWithChildren n=%lu", (unsigned long)c.count);
    return %orig([FTFInjector inject:c from:@"-initWithChildren" target:nil]);
}
- (instancetype)initWithTitle:(NSString *)t children:(NSArray *)c {
    FTFLog(@"-initWithTitle:children t=%@ n=%lu", t, (unsigned long)c.count);
    return %orig(t, [FTFInjector inject:c from:@"-initWithTitle:children" target:t]);
}
- (instancetype)initWithTitle:(NSString *)t image:(UIImage *)i identifier:(NSString *)d
                      options:(UIMenuOptions)o children:(NSArray *)c {
    FTFLog(@"-initWithTitle:image t=%@ n=%lu", t, (unsigned long)c.count);
    return %orig(t, i, d, o, [FTFInjector inject:c from:@"-initWithTitle:image" target:t]);
}

%end

%ctor { FTFLog(@"===== v5 已加载 ====="); }
