#import <notify.h>
#import <Foundation/Foundation.h>

// Unique keys for Inter-Process Communication (IPC)
#define kPowercuffModeKey "com.rpetrich.powercuff.mode"
#define kPowercuffNotify "com.rpetrich.powercuff.update"

// Forward declarations to keep the compiler happy without private headers
@interface SBBacklightController : NSObject
+ (id)sharedInstance;
- (BOOL)screenIsOn;
@end

@interface CommonProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)mode;
@end

static id currentTarget = nil;

/**
 * ApplyThermals
 * Executed inside 'thermalmonitord'
 * This reads the state set by SpringBoard and tells the A11 chip to throttle.
 */
static void ApplyThermals() {
    int token;
    uint64_t state = 0;
    
    // Check the system register for the target mode
    if (notify_register_check(kPowercuffModeKey, &token) == NOTIFY_STATUS_OK) {
        notify_get_state(token, &state);
        notify_cancel(token); // Correct Darwin API to release token
    }

    // Index mapping for Powercuff/thermalmonitord
    NSArray *modes = @[@"off", @"nominal", @"light", @"moderate", @"heavy"];
    
    if (currentTarget && state < [modes count]) {
        NSString *modeStr = modes[state];
        
        if ([currentTarget respondsToSelector:@selector(putDeviceInThermalSimulationMode:)]) {
            // Apply the thermal simulation to throttle CPU/GPU
            [currentTarget putDeviceInThermalSimulationMode:modeStr];
            
            // Genius Trick: On iPhone X, re-applying 'heavy' can help force GPU downclocking
            if (state == 4) {
                [currentTarget putDeviceInThermalSimulationMode:@"heavy"];
            }
        }
    }
}

// --- HOOKS FOR thermalmonitord ---
%hook CommonProduct
- (id)init {
    self = %orig;
    currentTarget = self; // Capture the hardware controller object
    return self;
}

- (void)serviceModeChanged {
    %orig;
    ApplyThermals();
}
%end

// --- HOOKS FOR SpringBoard ---
%group SpringBoardHooks
%hook SBBacklightController
/**
 * backlight:didCompleteUpdateToState:
 * This is the most reliable screen-state hook for iOS 15/16.
 */
- (void)backlight:(id)arg1 didCompleteUpdateToState:(long long)arg2 {
    %orig;
    
    // arg2: 1 = Off, 2+ = On
    BOOL screenOn = (arg2 > 1);
    
    // Load preference from the rootless path
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.rpetrich.powercuff.plist"];
    uint64_t userMode = [prefs[@"PowerMode"] ?: @3 unsignedLongLongValue];
    
    // IRON CURTAIN: Force Heavy (4) if screen is off, else use user's Daily mode
    uint64_t targetState = screenOn ? userMode : 4; 
    
    // Broadcast the change to thermalmonitord
    int token;
    if (notify_register_check(kPowercuffModeKey, &token) == NOTIFY_STATUS_OK) {
        notify_set_state(token, targetState);
        notify_post(kPowercuffNotify);
        notify_cancel(token);
    }
}
%end
%end

// --- CONSTRUCTOR ---
%ctor {
    NSString *procName = [[NSProcessInfo processInfo] processName];
    
    if ([procName isEqualToString:@"thermalmonitord"]) {
        %init;
        int token;
        // Set up a listener so thermalmonitord reacts instantly to screen changes
        notify_register_dispatch(kPowercuffNotify, &token, dispatch_get_main_queue(), ^(int t) {
            ApplyThermals();
        });
    } else if ([procName isEqualToString:@"SpringBoard"]) {
        %init(SpringBoardHooks);
    }
}
