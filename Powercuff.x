#import <notify.h>
#import <Foundation/Foundation.h>

#define kPowercuffModeKey "com.rpetrich.powercuff.mode"
#define kPowercuffNotify "com.rpetrich.powercuff.update"

// Forward declarations - No private headers needed
@interface SBBacklightController : NSObject
+ (id)sharedInstance;
- (BOOL)screenIsOn;
@end

@interface CommonProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)mode;
@end

static id currentTarget = nil;

static void ApplyThermals() {
    int token;
    uint64_t state = 0;
    
    if (notify_register_check(kPowercuffModeKey, &token) == NOTIFY_STATUS_OK) {
        notify_get_state(token, &state);
        notify_cancel(token); 
    }

    NSArray *modes = @[@"off", @"nominal", @"light", @"moderate", @"heavy"];
    
    if (currentTarget && state < [modes count]) {
        NSString *modeStr = modes[state];
        if ([currentTarget respondsToSelector:@selector(putDeviceInThermalSimulationMode:)]) {
            [currentTarget putDeviceInThermalSimulationMode:modeStr];
        }
    }
}

// --- THERMALMONITORD ---
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

// --- SPRINGBOARD ---
%group SpringBoardHooks
%hook SBBacklightController
// Using id and long long to remain SDK-agnostic and pass the linker
- (void)backlight:(id)arg1 didCompleteUpdateToState:(long long)arg2 {
    %orig;
    
    // State 1 = Off, State 2+ = On
    BOOL screenOn = (arg2 > 1);
    
    // Rootless preference path
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.rpetrich.powercuff.plist"];
    uint64_t userMode = [prefs[@"PowerMode"] ?: @3 unsignedLongLongValue];
    
    // Logic: Screen Off = Heavy (4), Screen On = User Choice
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
    } else if ([procName isEqualToString:@"SpringBoard"]) {
        %init(SpringBoardHooks);
    }
}
