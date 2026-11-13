#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

static UIImage *UnavailableSystemIcon(id receiver, SEL selector, NSString *bundle, NSInteger format, CGFloat scale) {
    return nil;
}

static void IgnoreNotificationCleanup(id receiver, SEL selector, NSArray<NSString *> *identifiers) {}

// IconServices on the iOS 27 simulator can block the host before XCTest starts.
__attribute__((constructor)) static void IsolateSystemIconsForAppResponseTests(void) {
    for (NSString *argument in NSProcessInfo.processInfo.arguments) {
        if ([argument hasPrefix:@"PokiTests.UnresponsiveAppTests/"]) {
            Method method = class_getClassMethod(UIImage.class, NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:"));
            if (method) method_setImplementation(method, (IMP)UnavailableSystemIcon);
            // The simulator notification service also blocks synchronously after a denial.
            for (NSString *selector in @[@"removeDeliveredNotificationsWithIdentifiers:", @"removePendingNotificationRequestsWithIdentifiers:"]) {
                Method cleanup = class_getInstanceMethod(UNUserNotificationCenter.class, NSSelectorFromString(selector));
                if (cleanup) method_setImplementation(cleanup, (IMP)IgnoreNotificationCleanup);
            }
            break;
        }
    }
}
