#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <stdio.h>
#import <string.h>
#import "InProcess.h"

static double sVirtualUptime = 1000.0;
static NSString *(*sOrigBundleIdentifier)(id, SEL);
static NSArray<NSURL *> *(*sOrigURLsForDirectory)(id, SEL, NSSearchPathDirectory, NSSearchPathDomainMask);

static double TestSystemUptime(id self, SEL _cmd) {
    (void)self;
    (void)_cmd;
    return sVirtualUptime;
}

static void TestSleepForTimeInterval(id self, SEL _cmd, NSTimeInterval ti) {
    (void)self;
    (void)_cmd;
    if (ti > 0) sVirtualUptime += ti;
}

static NSString *TestMainBundleIdentifier(id self, SEL _cmd) {
    if (self == NSBundle.mainBundle) return @"local.poki.inprocess-check";
    return sOrigBundleIdentifier(self, _cmd);
}

static NSArray<NSURL *> *TestURLsForDirectory(id self, SEL _cmd, NSSearchPathDirectory dir, NSSearchPathDomainMask mask) {
    if (dir == NSDocumentDirectory) {
        const char *docs = getenv("POKI_TEST_DOCS");
        if (docs && docs[0]) {
            return @[[NSURL fileURLWithPath:[NSString stringWithUTF8String:docs] isDirectory:YES]];
        }
    }
    return sOrigURLsForDirectory(self, _cmd, dir, mask);
}

static void InstallTestHooks(void) {
    Method sleep = class_getClassMethod(NSThread.class, @selector(sleepForTimeInterval:));
    method_setImplementation(sleep, (IMP)TestSleepForTimeInterval);

    Class processInfoClass = object_getClass(NSProcessInfo.processInfo);
    class_replaceMethod(processInfoClass, @selector(systemUptime), (IMP)TestSystemUptime, "d@:");
    if (processInfoClass != NSProcessInfo.class) {
        class_replaceMethod(NSProcessInfo.class, @selector(systemUptime), (IMP)TestSystemUptime, "d@:");
    }

    double t0 = NSProcessInfo.processInfo.systemUptime;
    [NSThread sleepForTimeInterval:0.5];
    double t1 = NSProcessInfo.processInfo.systemUptime;
    if (fabs((t1 - t0) - 0.5) > 0.001) {
        fprintf(stderr, "virtual clock hook failed: delta=%f class=%s\n", t1 - t0, class_getName(processInfoClass));
        exit(2);
    }
    sVirtualUptime = 1000.0;

    Method bundleID = class_getInstanceMethod(NSBundle.class, @selector(bundleIdentifier));
    sOrigBundleIdentifier = (NSString *(*)(id, SEL))method_setImplementation(bundleID, (IMP)TestMainBundleIdentifier);

    Method urls = class_getInstanceMethod(NSFileManager.class, @selector(URLsForDirectory:inDomains:));
    sOrigURLsForDirectory = (NSArray<NSURL *> *(*)(id, SEL, NSSearchPathDirectory, NSSearchPathDomainMask))method_setImplementation(urls, (IMP)TestURLsForDirectory);
}

static void AppendTrace(NSString *line) {
    const char *path = getenv("POKI_TEST_TRACE");
    if (!path || !path[0]) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    fprintf(f, "%s\n", line.UTF8String);
    fclose(f);
}

static NSData *MinimalPNG(void) {
    static const unsigned char bytes[] = {
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xde, 0x00, 0x00, 0x00,
        0x0c, 0x49, 0x44, 0x41, 0x54, 0x08, 0xd7, 0x63, 0xf8, 0xcf, 0xc0, 0x00,
        0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xdd, 0x8d, 0xb0, 0x00, 0x00, 0x00,
        0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82
    };
    return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}

@implementation PKTouchPoint
@synthesize point = _point, offset = _offset;
+ (instancetype)at:(CGPoint)point offset:(double)offset {
    PKTouchPoint *p = [PKTouchPoint new];
    p->_point = point;
    p->_offset = offset;
    return p;
}
@end

@implementation PKOutcome
@synthesize delivery = _delivery, code = _code, detail = _detail, seconds = _seconds, generation = _generation;
@end

@implementation PKInProcess {
    NSArray<NSString *> *_fronts;
    NSUInteger _frontIndex;
    NSString *_currentFront;
}

+ (instancetype)shared {
    static PKInProcess *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [PKInProcess new];
        const char *env = getenv("POKI_TEST_FRONTS");
        NSString *raw = env ? [NSString stringWithUTF8String:env] : @"";
        instance->_fronts = [raw componentsSeparatedByString:@","];
        instance->_frontIndex = 0;
        instance->_currentFront = @"";
    });
    return instance;
}

- (NSDictionary<NSString *, id> *)prepare {
    return @{@"ok": @YES, @"generation": @1, @"seconds": @0.01};
}

- (NSDictionary<NSString *, id> *)frontApp {
    NSUInteger idx = _frontIndex < _fronts.count ? _frontIndex : (_fronts.count ? _fronts.count - 1 : 0);
    if (_frontIndex + 1 < _fronts.count) _frontIndex++;
    NSString *token = _fronts.count ? _fronts[idx] : @"NIL";
    if ([token isEqualToString:@"NIL"]) {
        _currentFront = @"";
        AppendTrace(@"front:<nil>");
        return @{};
    }
    _currentFront = token;
    AppendTrace([NSString stringWithFormat:@"front:%@", token]);
    return @{@"bundleId": token, @"pid": @(100 + (int)idx)};
}

- (nullable NSString *)sourceXML:(NSDictionary *_Nullable *_Nullable)focused code:(NSString *_Nullable *_Nullable)code {
    if (focused) *focused = @{@"value": @""};
    if (code) *code = nil;
    AppendTrace([NSString stringWithFormat:@"sourceXML:%@", _currentFront]);
    return @"<XCUIElementTypeApplication><XCUIElementTypeWindow x=\"0\" y=\"0\" width=\"390\" height=\"844\"/></XCUIElementTypeApplication>";
}

- (nullable NSData *)screenshot:(NSString *_Nullable *_Nullable)code {
    if (code) *code = nil;
    AppendTrace([NSString stringWithFormat:@"screenshot:%@", _currentFront]);
    return MinimalPNG();
}

- (PKDisplayGeometry)displayGeometry {
    PKDisplayGeometry g = {0};
    g.bounds = CGRectMake(0, 0, 390, 844);
    g.nativeSize = CGSizeMake(1170, 2532);
    return g;
}

- (PKDisplayGeometry)readDisplayGeometry {
    return [self displayGeometry];
}

- (CGRect)viewport {
    return CGRectNull;
}

- (nullable NSString *)app:(NSString *)bundle action:(NSString *)action {
    AppendTrace([NSString stringWithFormat:@"app:%@:%@", action, bundle]);
    return nil;
}

- (NSDictionary<NSString *, id> *)close {
    return @{@"closed": @YES, @"generation": @1};
}

- (uint64_t)generation {
    return 1;
}

- (PKOutcome *)touch:(NSArray<NSArray<PKTouchPoint *> *> *)fingers timeout:(double)timeout {
    (void)fingers;
    (void)timeout;
    return [PKOutcome new];
}

- (PKOutcome *)touch:(NSArray<NSArray<PKTouchPoint *> *> *)fingers timeout:(double)timeout geometry:(PKDisplayGeometry)geometry {
    (void)geometry;
    return [self touch:fingers timeout:timeout];
}

- (PKOutcome *)type:(NSString *)text timeout:(double)timeout {
    (void)text;
    (void)timeout;
    return [PKOutcome new];
}

@end

void dispatch_async(dispatch_queue_t queue, dispatch_block_t block) {
    const char *label = dispatch_queue_get_label(queue);
    if (label && strcmp(label, "check") == 0) {
        block();
        return;
    }
    static void (*real_dispatch_async)(dispatch_queue_t, dispatch_block_t);
    if (!real_dispatch_async) {
        real_dispatch_async = dlsym(RTLD_NEXT, "dispatch_async");
    }
    real_dispatch_async(queue, block);
}

int UIApplicationMain(int argc, char *argv[], NSString *principalClassName, NSString *delegateClassName) {
    (void)argc;
    (void)argv;
    (void)principalClassName;
    InstallTestHooks();
    Class delegateClass = NSClassFromString(delegateClassName);
    if (!delegateClass) {
        fprintf(stderr, "missing delegate class: %s\n", delegateClassName.UTF8String);
        return 2;
    }
    id<UIApplicationDelegate> delegate = [delegateClass new];
    [delegate application:(UIApplication *)[NSNull null] didFinishLaunchingWithOptions:@{}];
    return 0;
}
