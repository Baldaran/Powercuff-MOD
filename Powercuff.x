#import <notify.h>
#import <Foundation/Foundation.h>

// Pre-define interfaces for safety
@interface BKSProcessAssertion : NSObject
- (id)initWithBundleIdentifier:(NSString *)bundleID flags:(unsigned int)flags reason:(unsigned int)reason name:(NSString *)name withHandler:(id)handler;
@end

@interface SBBacklightController : NSObject
+ (id)sharedInstance;
- (BOOL)screenIsOn;
@end

@interface CommonProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)mode;
@end

static id currentTarget;
static int token;
static BOOL isScreenOn = YES;
static uint64_t userSelectedMode = 3; 

static void ApplyThermals(void) {
    // Autonomic: 4 (Heavy) when screen is off, otherwise user choice
    uint64_t targetMode = isScreenOn ? userSelectedMode : 4; 
    NSArray *modes = @[@"off", @"nominal", @"light", @"moderate", @"heavy"];
    
    if (currentTarget && targetMode < [modes count]) {
        NSString *modeStr = modes[targetMode];
        
        // GENIUS LOGGING: This will appear in 'oslog' or 'syslog'
        NSLog(@"[Powercuff-r3vamp] Setting Mode: %@ (Screen: %@)", modeStr, isScreenOn ? @"ON" : @"OFF");

        if ([currentTarget respondsToSelector:@selector(putDeviceInThermalSimulationMode:)]) {
            [currentTarget putDeviceInThermalSimulationMode:modeStr];
        }
    }
}

%group SpringBoardHooks
%hook SBBacklightController
- (void)_performDeferredBacklightRampWork {
    %orig;
    BOOL currentlyOn = [self screenIsOn];
    if (currentlyOn != isScreenOn) {
        isScreenOn = currentlyOn;
        ApplyThermals();
        notify_post("com.rpetrich.powercuff.thermals");
    }
}
%end

%hook BKSProcessAssertion
- (id)initWithBundleIdentifier:(NSString *)bundleID flags:(unsigned int)flags reason:(unsigned int)reason name:(NSString *)name withHandler:(id)handler {
    uint64_t currentMode = isScreenOn ? userSelectedMode : 4;
    unsigned int newFlags = flags;
    if (currentMode == 3) newFlags &= ~0x2; // Moderate: Sync Pause
    else if (currentMode >= 4) newFlags = 0; // Heavy: Freeze
    return %orig(bundleID, newFlags, reason, name, handler);
}
%end
%end

// Add the hook to capture the thermal object
%hook CommonProduct
- (id)init {
    self = %orig;
    currentTarget = self;
    return self;
}
%end

%ctor {
    notify_register_check("com.rpetrich.powercuff.thermals", &token);
    NSString *procName = [[NSProcessInfo processInfo] processName];
    
    if ([procName isEqualToString:@"thermalmonitord"]) {
        %init;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (void *)ApplyThermals, CFSTR("com.rpetrich.powercuff.thermals"), NULL, CFNotificationSuspensionBehaviorCoalesce);
    } else if ([procName isEqualToString:@"SpringBoard"]) {
        %init(SpringBoardHooks);
    }
}
