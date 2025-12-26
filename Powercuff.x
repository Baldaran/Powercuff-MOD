#import <notify.h>
#import <Foundation/Foundation.h>

// Genius Fix: Declare the interface so the compiler is happy.
// We do NOT #import <AssertionServices/BKSProcessAssertion.h>
@interface BKSProcessAssertion : NSObject
- (id)initWithBundleIdentifier:(NSString *)bundleID flags:(unsigned int)flags reason:(unsigned int)reason name:(NSString *)name withHandler:(id)handler;
@end

#ifndef ROOT_PATH_NS
#define ROOT_PATH_NS(path) \
    ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? \
    [@"/var/jb" stringByAppendingPathComponent:path] : path)
#endif

@interface CommonProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)mode;
@end

static id currentTarget;
static int token;
static BOOL isScreenOn = YES;
static uint64_t userSelectedMode = 3; // Default to Moderate

static void ApplyThermals(void) {
    uint64_t targetMode = isScreenOn ? userSelectedMode : 4; 
    NSArray *modes = @[@"off", @"nominal", @"light", @"moderate", @"heavy"];
    if (currentTarget && targetMode < [modes count]) {
        NSString *modeStr = modes[targetMode];
        if ([currentTarget respondsToSelector:@selector(putDeviceInThermalSimulationMode:)]) {
            [currentTarget putDeviceInThermalSimulationMode:modeStr];
        }
    }
}

static void UpdateScreenState(BOOL on) {
    static int timerGen = 0;
    int currentGen = ++timerGen;
    if (on) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (currentGen == timerGen) {
                isScreenOn = YES;
                ApplyThermals();
                notify_post("com.rpetrich.powercuff.thermals");
            }
        });
    } else {
        isScreenOn = NO;
        ApplyThermals();
        notify_post("com.rpetrich.powercuff.thermals");
    }
}

%group SoftwareThrottling
%hook BKSProcessAssertion
- (id)initWithBundleIdentifier:(NSString *)bundleID flags:(unsigned int)flags reason:(unsigned int)reason name:(NSString *)name withHandler:(id)handler {
    uint64_t currentMode = isScreenOn ? userSelectedMode : 4;
    unsigned int newFlags = flags;
    if (currentMode == 3) {
        newFlags &= ~0x2; 
    } else if (currentMode >= 4) {
        newFlags = 0; 
    }
    return %orig(bundleID, newFlags, reason, name, handler);
}
%end
%end

static void LoadSettings(void) {
    NSString *path = ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.rpetrich.powercuff.plist");
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
    userSelectedMode = [prefs[@"PowerMode"] ?: @3 unsignedLongLongValue];
    if ([prefs[@"RequireLowPowerMode"] boolValue] && ![[NSProcessInfo processInfo] isLowPowerModeEnabled]) {
        userSelectedMode = 0;
    }
    notify_set_state(token, userSelectedMode);
    ApplyThermals();
}

%ctor {
    notify_register_check("com.rpetrich.powercuff.thermals", &token);
    NSString *procName = [[NSProcessInfo processInfo] processName];
    if ([procName isEqualToString:@"thermalmonitord"]) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (void *)ApplyThermals, CFSTR("com.rpetrich.powercuff.thermals"), NULL, CFNotificationSuspensionBehaviorCoalesce);
        %init(); 
    } else if ([procName isEqualToString:@"SpringBoard"]) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (void *)^{ UpdateScreenState(NO); }, CFSTR("com.apple.springboard.hasBlankedScreen"), NULL, CFNotificationSuspensionBehaviorCoalesce);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (void *)^{ UpdateScreenState(YES); }, CFSTR("com.apple.springboard.screenunblanked"), NULL, CFNotificationSuspensionBehaviorCoalesce);
        %init(SoftwareThrottling);
        LoadSettings();
    }
}
