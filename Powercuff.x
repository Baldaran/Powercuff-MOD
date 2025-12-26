#import <notify.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// --- ROOTLESS COMPATIBILITY MACRO ---
// This ensures the tweak looks in /var/jb/ on rootless jailbreaks
#ifndef ROOT_PATH_NS
#define ROOT_PATH_NS(path) \
    ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? \
    [@"/var/jb" stringByAppendingPathComponent:path] : path)
#endif
// ------------------------------------

// Forward declarations for the compiler
@interface CommonProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)simulationMode;
@end

@interface Context : NSObject
- (void)setThermalSimulationMode:(int)mode;
@end

// This allows us to check the process name at runtime
extern char ***_NSGetArgv(void);

static id currentTarget; 
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
        // iOS 16 compatibility check
        if ([currentTarget respondsToSelector:@selector(putDeviceInThermalSimulationMode:)]) {
            [currentTarget putDeviceInThermalSimulationMode:stringForThermalMode(thermalMode)];
        } else if ([currentTarget respondsToSelector:@selector(setThermalSimulationMode:)]) {
            [currentTarget setThermalSimulationMode:(int)thermalMode];
        }
    }
}

%group thermalmonitord

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
    // We pass the absolute path through the ROOT_PATH_NS macro
    NSString *basePath = @"/var/mobile/Library/Preferences/com.rpetrich.powercuff.plist";
    NSString *finalPath = ROOT_PATH_NS(basePath);
    
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:finalPath];
    
    uint64_t thermalMode = 0;
    if (prefs[@"PowerMode"]) {
        thermalMode = [prefs[@"PowerMode"] unsignedLongLongValue];
    }
    
    // Check Low Power Mode status via standard Foundation API
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
- (void)_batterySaverModeChanged:(int)arg1 {
    %orig;
    LoadSettings();
}
%end
%end

%ctor {
    notify_register_check("com.rpetrich.powercuff.thermals", &token);
    
    char *argv0 = **_NSGetArgv();
    if (argv0) {
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
}
