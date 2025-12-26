#import <notify.h>
#import <Foundation/Foundation.h>

#define kPowercuffModeKey "com.rpetrich.powercuff.mode"
#define kPowercuffNotify "com.rpetrich.powercuff.update"

// Forward declarations for SpringBoard classes
@interface SBBacklightController : NSObject
+ (id)sharedInstance;
- (BOOL)screenIsOn;
@end

@interface CommonProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)mode;
@end

static id currentTarget = nil;

// Function that runs inside thermalmonitord to apply the cap
static void ApplyThermals() {
    int token;
    uint64_t state = 0;
    
    // Register to check the state, then cancel the token immediately to prevent leaks
    if (notify_register_check(kPowercuffModeKey, &token) == NOTIFY_STATUS_OK) {
        notify_get_state(token, &state);
        notify_cancel(token); // THE FIX: notify_cancel instead of notify_close
    }

    NSArray *modes = @[@"off", @"nominal", @"light", @"moderate", @"heavy"];
    
    if (currentTarget && state < [modes count]) {
        NSString *modeStr = modes[state];
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
    
    // state 1 = Off, state 2+ = On for iOS 16
    BOOL screenOn = (state > 1);
    
    // Load preferences for rootless
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.rpetrich.powercuff.plist"];
    uint64_t userMode = [prefs[@"PowerMode"] ?: @3 unsignedLongLongValue];
    
    // If screen is off, force Heavy (index 4). If on, use daily mode.
    uint64_t targetState = screenOn ? userMode : 4; 
    
    int token;
    if (notify_register_check(kPowercuffModeKey, &token) == NOTIFY_STATUS_OK) {
        notify_set_state(token, targetState);
        notify_post(kPowercuffNotify);
        notify_cancel(token); // THE FIX: notify_cancel instead of notify_close
    }
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
