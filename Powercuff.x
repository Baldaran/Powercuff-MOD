#import <notify.h>
#import <Foundation/Foundation.h>

// Private Headers for AssertionServices
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

// --- Core Thermal Application ---
static void ApplyThermals(void) {
    uint64_t targetMode = isScreenOn ? userSelectedMode : 4; // Use HEAVY if screen is off

    NSArray *modes = @[@"off", @"nominal", @"light", @"moderate", @"heavy"];
    if (currentTarget && targetMode < [modes count]) {
        NSString *modeStr = modes[targetMode];
        if ([currentTarget respondsToSelector:@selector(putDeviceInThermalSimulationMode:)]) {
            [currentTarget putDeviceInThermalSimulationMode:modeStr];
        }
    }
}

// --- Autonomic Logic ---
static void UpdateScreenState(BOOL on) {
    static int timerGen = 0; // Prevent overlapping delay logic
    int currentGen = ++timerGen;

    if (on) {
        // Screen turned on: Wait 2 seconds before ramping up performance
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (currentGen == timerGen) { // Only execute if screen is still on
                isScreenOn = YES;
                ApplyThermals();
                notify_post("com.rpetrich.powercuff.thermals");
            }
        });
    } else {
        // Screen turned off: Slam the "Iron Curtain" immediately
        isScreenOn = NO;
        ApplyThermals();
        notify_post("com.rpetrich.powercuff.thermals");
    }
}

// --- Background Freezer ---
%group SoftwareThrottling
%hook BKSProcessAssertion
- (id)initWithBundleIdentifier:(NSString *)bundleID flags:(unsigned int)flags reason:(unsigned int)reason name:(NSString *)name withHandler:(id)handler {
    uint64_t currentMode = isScreenOn ? userSelectedMode : 4;

    unsigned int newFlags = flags;
    if (currentMode == 3) {
        newFlags &= ~0x2; // Moderate: Limit background tasks
    } else if (currentMode >= 4) {
        newFlags = 0; // Heavy: Absolute Freeze
    }
    return %orig(bundleID, newFlags, reason, name, handler);
}
%end
%end

// --- Settings Loader ---
static void LoadSettings(void) {
    NSString *path = ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.rpetrich.powercuff.plist");
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
    
    userSelectedMode = [prefs[@"PowerMode"] ?: @3 unsignedLongLongValue]; // Default to Moderate (3)
    
    if ([prefs[@"RequireLowPowerMode"] boolValue] && ![[NSProcessInfo processInfo] isLowPowerModeEnabled]) {
        userSelectedMode = 0; // Forced None if LPM check fails
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
        // iOS 16 specific SpringBoard observers for screen state
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (void *)^{ UpdateScreenState(NO); }, CFSTR("com.apple.springboard.hasBlankedScreen"), NULL, CFNotificationSuspensionBehaviorCoalesce);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (void *)^{ UpdateScreenState(YES); }, CFSTR("com.apple.springboard.screenunblanked"), NULL, CFNotificationSuspensionBehaviorCoalesce);
        
        %init(SoftwareThrottling);
        LoadSettings();
    }
}
