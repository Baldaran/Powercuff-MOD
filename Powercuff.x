#import <notify.h>
#import <Foundation/Foundation.h>

// --- ROOTLESS COMPATIBILITY MACRO ---
#ifndef ROOT_PATH_NS
#define ROOT_PATH_NS(path) \
    ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? \
    [@"/var/jb" stringByAppendingPathComponent:path] : path)
#endif
// ------------------------------------

#import <UIKit/UIKit.h>

// Forward declarations for the compiler
@interface CommonProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)simulationMode;
@end

@interface Context : NSObject
- (void)setThermalSimulationMode:(int)mode;
@end

extern char ***_NSGetArgv(void);

static id currentTarget; // Renamed to Target to be more generic
static int token;

// Helper to map integers to strings for the legacy CommonProduct method
static NSString *stringForThermalMode(uint64_t thermalMode) {
    switch (thermalMode) {
        case 1: return @"nominal";
        case 2: return @"light";
        case 3: return @"moderate";
        case 4: return @"heavy";
        default: return @"off";
    }
}

static void ApplyThermals(void) {
    uint64_t thermalMode = 0;
    notify_get_state(token, &thermalMode);
    
    if (currentTarget) {
        // iOS 16 check: determine which method the target supports
        if ([currentTarget respondsToSelector:@selector(putDeviceInThermalSimulationMode:)]) {
            [currentTarget putDeviceInThermalSimulationMode:stringForThermalMode(thermalMode)];
        } else if ([currentTarget respondsToSelector:@selector(setThermalSimulationMode:)]) {
            [currentTarget setThermalSimulationMode:(int)thermalMode];
        }
    }
}

%group thermalmonitord

// Hooking both possible classes for 100% compatibility on iOS 16
%hook CommonProduct
- (id)initProduct:(id)data {
    self = %orig;
    if (self) {
        currentTarget = self;
        ApplyThermals();
    }
    return self;
}
%end

%hook Context
- (id)init {
    self = %orig;
    if (self) {
        currentTarget = self;
        ApplyThermals();
    }
    return self;
}
%end

%end

static void LoadSettings(void) {
    // ROOT_PATH_NS is mandatory for Rootless iOS 16
    NSString *path = @"/var/mobile/Library/Preferences/com.rpetrich.powercuff.plist";
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:ROOT_PATH_NS(path)];
    
    uint64_t thermalMode = 0;
    if (prefs[@"PowerMode"]) {
        thermalMode = [prefs[@"PowerMode"] unsignedLongLongValue];
    }
    
    // Check Low Power Mode status
    // Note: On iOS 16, we often use [NSProcessInfo processInfo].isLowPowerModeEnabled
    if ([prefs[@"RequireLowPowerMode"] boolValue]) {
        if (![[NSProcessInfo processInfo] isLowPowerModeEnabled]) {
            thermalMode = 0;
        }
    }

    notify_set_state(token, thermalMode);
    notify_post("com.rpetrich.powercuff.thermals");
}

%group SpringBoard
%hook SpringBoard
- (void)_batterySaverModeChanged:(NSInteger)arg1 {
    %orig;
    LoadSettings();
}
%end
%end

%ctor {
    notify_register_check("com.rpetrich.powercuff.thermals", &token);
    
    char *argv0 = **_NSGetArgv();
    NSString *processName = [[NSString stringWithUTF8String:argv0] lastPathComponent];

    if ([processName isEqualToString:@"thermalmonitord"]) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (void *)ApplyThermals, CFSTR("com.rpetrich.powercuff.thermals"), NULL, CFNotificationSuspensionBehaviorCoalesce);
        %init(thermalmonitord);
    } else if ([processName isEqualToString:@"SpringBoard"]) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (void *)LoadSettings, CFSTR("com.rpetrich.powercuff.settingschanged"), NULL, CFNotificationSuspensionBehaviorCoalesce);
        LoadSettings();
        %init(SpringBoard);
    }
}
