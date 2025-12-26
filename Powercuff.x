#import <notify.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/CADisplayLink.h>
#import <UIKit/UIKit.h>

#define kPowercuffModeKey "com.rpetrich.powercuff.mode"
#define kPowercuffNotify "com.rpetrich.powercuff.update"

// --- ADDED INTERFACES FOR DEEPER HARDWARE CONTROL ---
@interface SBBacklightController : NSObject
- (void)backlight:(id)arg1 didCompleteUpdateToState:(long long)arg2;
@end

@interface CommonProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)mode;
- (void)setThermalLevel:(int)level; // NEW: Direct level control
- (int)lowBatteryLevel; // NEW: Spoof battery state to force parking
@end

static id currentTarget = nil;

static uint64_t GetPowercuffState() {
    int token;
    uint64_t state = 0;
    if (notify_register_check(kPowercuffModeKey, &token) == NOTIFY_STATUS_OK) {
        notify_get_state(token, &state);
        notify_cancel(token);
    }
    return state;
}

static void ApplyThermals() {
    uint64_t state = GetPowercuffState();
    NSArray *modes = @[@"off", @"nominal", @"light", @"moderate", @"heavy"];
    
    if (currentTarget && state < [modes count]) {
        NSString *modeStr = modes[state];
        if ([currentTarget respondsToSelector:@selector(putDeviceInThermalSimulationMode:)]) {
            [currentTarget putDeviceInThermalSimulationMode:modeStr];
            
            // --- NEW GENIUS LOGIC: FORCE CORE PARKING ---
            if (state == 4) {
                // On A11, Thermal Level 3+ triggers severe CPU frequency scaling
                if ([currentTarget respondsToSelector:@selector(setThermalLevel:)]) {
                    [currentTarget setThermalLevel:3]; 
                }
            }
        }
    }
}

%group FrameLimiter
%hook CADisplayLink
- (void)setPreferredFramesPerSecond:(NSInteger)fps {
    if (GetPowercuffState() == 4 && fps > 30) {
        %orig(30); 
    } else {
        %orig(fps);
    }
}

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    if (GetPowercuffState() == 4) {
        // --- NEW: Force the range to lock at 30 to prevent Antutu spikes ---
        CAFrameRateRange cappedRange = CAFrameRateRangeMake(10, 30, 30);
        %orig(cappedRange);
    } else {
        %orig(range);
    }
}
%end
%end

%hook CommonProduct
- (id)init {
    self = %orig;
    currentTarget = self;
    return self;
}

// --- NEW GENIUS HOOK: Forced Throttling ---
- (int)lowBatteryLevel {
    // If state is Heavy, return 100% to trick the OS into maximum energy saving
    if (GetPowercuffState() == 4) return 100;
    return %orig;
}

- (void)serviceModeChanged { %orig; ApplyThermals(); }
%end

%group SpringBoardHooks
%hook SBBacklightController
- (void)backlight:(id)arg1 didCompleteUpdateToState:(long long)arg2 {
    %orig;
    BOOL screenOn = (arg2 > 1);
    
    // Ensure we look in the correct rootless path for iOS 16
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.rpetrich.powercuff.plist"];
    uint64_t userMode = [prefs[@"PowerMode"] ?: @3 unsignedLongLongValue];
    uint64_t targetState = screenOn ? userMode : 4; 
    
    int token;
    if (notify_register_check(kPowercuffModeKey, &token) == NOTIFY_STATUS_OK) {
        notify_set_state(token, targetState);
        notify_post(kPowercuffNotify);
        notify_cancel(token);
    }
}
%end
%end

%ctor {
    NSString *procName = [[NSProcessInfo processInfo] processName];
    if ([procName isEqualToString:@"thermalmonitord"]) {
        %init;
        int token;
        notify_register_dispatch(kPowercuffNotify, &token, dispatch_get_main_queue(), ^(int t) {
            ApplyThermals();
        });
    } else {
        %init(SpringBoardHooks);
        %init(FrameLimiter);
    }
}
