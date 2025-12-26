#import <notify.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/CADisplayLink.h>
#import <UIKit/UIKit.h>

#define kPowercuffModeKey "com.rpetrich.powercuff.mode"
#define kPowercuffNotify "com.rpetrich.powercuff.update"

@interface SBBacklightController : NSObject
- (void)backlight:(id)arg1 didCompleteUpdateToState:(long long)arg2;
@end

@interface CommonProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)mode;
@end

static id currentTarget = nil;

// Helper to get current Powercuff state
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
            // Force aggressive state for Heavy
            if (state == 4) [currentTarget putDeviceInThermalSimulationMode:@"heavy"];
        }
    }
}

// --- 30 FPS LIMITER LOGIC ---
%group FrameLimiter
%hook CADisplayLink
- (void)setPreferredFramesPerSecond:(NSInteger)fps {
    if (GetPowercuffState() == 4 && fps > 30) {
        %orig(30); // Force 30FPS for animations
    } else {
        %orig(fps);
    }
}

// Modern iOS 15+ API for frame rate ranges
- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    if (GetPowercuffState() == 4) {
        // Cap the max and preferred to 30
        CAFrameRateRange cappedRange = CAFrameRateRangeMake(range.minimum, 30, 30);
        %orig(cappedRange);
    } else {
        %orig(range);
    }
}
%end
%end

// --- THERMALMONITORD HOOKS ---
%hook CommonProduct
- (id)init {
    self = %orig;
    currentTarget = self;
    return self;
}
- (void)serviceModeChanged { %orig; ApplyThermals(); }
%end

// --- SPRINGBOARD HOOKS ---
%group SpringBoardHooks
%hook SBBacklightController
- (void)backlight:(id)arg1 didCompleteUpdateToState:(long long)arg2 {
    %orig;
    BOOL screenOn = (arg2 > 1);
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
        // Init SpringBoard hooks and global FrameLimiter for all apps
        %init(SpringBoardHooks);
        %init(FrameLimiter);
    }
}
