#import <notify.h>
#import <Foundation/Foundation.h>

// Definitions
#define kPowercuffModeKey "com.rpetrich.powercuff.mode"
#define kPowercuffNotify "com.rpetrich.powercuff.update"

@interface SBBacklightController : NSObject
+ (id)sharedInstance;
@end

@interface CommonProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)mode;
@end

static id currentTarget = nil;

static void ApplyThermals() {
    int token;
    uint64_t state;
    notify_register_check(kPowercuffModeKey, &token);
    notify_get_state(token, &state);
    notify_close(token);

    // GENIUS LOGIC: 0-4 scale. We add +1 intensity if screen is off.
    // If Unlocked Moderate (3) -> use 3. If Locked -> use 4 (Heavy).
    NSArray *modes = @[@"off", @"nominal", @"light", @"moderate", @"heavy"];
    
    if (currentTarget && state < [modes count]) {
        [currentTarget putDeviceInThermalSimulationMode:modes[state]];
    }
}

// --- THERMALMONITORD SIDE ---
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

// --- SPRINGBOARD SIDE ---
%group SpringBoardHooks
%hook SBBacklightController
- (void)backlight:(id)backlight didCompleteUpdateToState:(long long)state {
    %orig;
    
    // state 1 = Off, state 2 = On (usually)
    BOOL screenOn = (state > 1);
    
    // Load User Choice
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.rpetrich.powercuff.plist"];
    uint64_t userMode = [prefs[@"PowerMode"] ?: @3 unsignedLongLongValue];
    
    // THE SMART SWITCH
    uint64_t target = screenOn ? userMode : 4; // 4 = HEAVY
    
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
        notify_register_dispatch(kPowercuffNotify, &token, dispatch_get_main_queue(), ^(int t) {
            ApplyThermals();
        });
    } else if ([procName isEqualToString:@"SpringBoard"]) {
        %init(SpringBoardHooks);
    }
}
