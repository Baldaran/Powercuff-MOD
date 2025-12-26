#import <notify.h>
#import <Foundation/Foundation.h>

#define kPowercuffModeKey "com.rpetrich.powercuff.mode"
#define kPowercuffNotify "com.rpetrich.powercuff.update"

@interface SBBacklightController : NSObject
+ (id)sharedInstance;
- (BOOL)screenIsOn;
@end

@interface CommonProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)mode;
@end

static id currentTarget = nil;

// EXECUTED INSIDE thermalmonitord
static void ApplyThermals() {
    int token;
    uint64_t state;
    notify_register_check(kPowercuffModeKey, &token);
    notify_get_state(token, &state);
    notify_close(token);

    NSArray *modes = @[@"off", @"nominal", @"light", @"moderate", @"heavy"];
    
    if (currentTarget && state < [modes count]) {
        NSString *modeStr = modes[state];
        // This is the call that actually limits the A11 hardware
        if ([currentTarget respondsToSelector:@selector(putDeviceInThermalSimulationMode:)]) {
            [currentTarget putDeviceInThermalSimulationMode:modeStr];
        }
    }
}

// --- THERMALMONITORD HOOKS ---
%hook CommonProduct
- (id)init {
    self = %orig;
    currentTarget = self;
    return self;
}

- (void)serviceModeChanged {
    %orig;
    ApplyThermals();
}
%end

// --- SPRINGBOARD HOOKS ---
%group SpringBoardHooks
%hook SBBacklightController
- (void)backlight:(id)backlight didCompleteUpdateToState:(long long)state {
    %orig;
    
    // state 1 = Off, state 2+ = On
    BOOL screenOn = (state > 1);
    
    // Path for rootless preferences
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.rpetrich.powercuff.plist"];
    uint64_t userMode = [prefs[@"PowerMode"] ?: @3 unsignedLongLongValue];
    
    // SMART LOGIC: If screen is off, force index 4 (Heavy/30% Cap). 
    // Otherwise use user selected mode.
    uint64_t target = screenOn ? userMode : 4; 
    
    // Write state to system register
    int token;
    notify_register_check(kPowercuffModeKey, &token);
    notify_set_state(token, target);
    notify_post(kPowercuffNotify);
    notify_close(token);
}
%end
%end

%ctor {
    NSString *procName = [[NSProcessInfo processInfo] processName];
    
    if ([procName isEqualToString:@"thermalmonitord"]) {
        %init;
        int token;
        // Listen for the cross-process trigger from SpringBoard
        notify_register_dispatch(kPowercuffNotify, &token, dispatch_get_main_queue(), ^(int t) {
            ApplyThermals();
        });
    } else if ([procName isEqualToString:@"SpringBoard"]) {
        %init(SpringBoardHooks);
    }
}
