#import "DisplayPowerController.h"
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <math.h>

static NSError *DisplayPowerError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"FocusBreakTimer.DisplayPower" code:code
                          userInfo:@{NSLocalizedDescriptionKey: description}];
}

@implementation DisplaySleepInputStateProvider

- (DisplaySleepInputSnapshot)inputSnapshot {
    CGEventSourceStateID state = kCGEventSourceStateCombinedSessionState;
    BOOL held = NO;
    CGEventFlags modifiers = kCGEventFlagMaskShift | kCGEventFlagMaskControl |
        kCGEventFlagMaskAlternate | kCGEventFlagMaskCommand | kCGEventFlagMaskSecondaryFn;
    held = (CGEventSourceFlagsState(state) & modifiers) != 0;
    for (CGMouseButton button = 0; !held && button < 32; button++) {
        held = CGEventSourceButtonState(state, button);
    }
    for (CGKeyCode key = 0; !held && key < 128; key++) {
        // Caps Lock is a toggle, not a key that must stay released.
        if (key != 57) held = CGEventSourceKeyState(state, key);
    }
    NSTimeInterval idle = CGEventSourceSecondsSinceLastEventType(state, kCGAnyInputEventType);
    return (DisplaySleepInputSnapshot){held, idle};
}

@end

@interface DisplayPowerController ()
@property (nonatomic, strong) NSTask *sleepTask;
@property (nonatomic, strong) id activity;
@property (nonatomic) IOPMAssertionID idleSleepAssertion;
@end

@implementation DisplayPowerController

- (BOOL)beginRestActivityForDuration:(NSTimeInterval)duration error:(NSError **)error {
    [self endRestActivity];
    if (!isfinite(duration) || duration <= 0) {
        if (error) *error = DisplayPowerError(1, @"休息时间已结束。");
        return NO;
    }
    // The timeout also bounds the assertion if a callback cannot run.
    NSDictionary *properties = @{
        (__bridge NSString *)kIOPMAssertionTypeKey: (__bridge NSString *)kIOPMAssertPreventUserIdleSystemSleep,
        (__bridge NSString *)kIOPMAssertionLevelKey: @(kIOPMAssertionLevelOn),
        (__bridge NSString *)kIOPMAssertionNameKey: @"FocusBreakTimer rest display wake",
        (__bridge NSString *)kIOPMAssertionTimeoutKey: @(duration + 5),
        (__bridge NSString *)kIOPMAssertionTimeoutActionKey: (__bridge NSString *)kIOPMAssertionTimeoutActionRelease
    };
    IOPMAssertionID assertion = kIOPMNullAssertionID;
    IOReturn result = IOPMAssertionCreateWithProperties((__bridge CFDictionaryRef)properties, &assertion);
    if (result != kIOReturnSuccess) {
        if (error) *error = DisplayPowerError(result, @"无法保持休息计时运行，请稍后重试。");
        return NO;
    }
    self.idleSleepAssertion = assertion;
    self.activity = [NSProcessInfo.processInfo beginActivityWithOptions:NSActivityUserInitiatedAllowingIdleSystemSleep
                                                               reason:@"Wake displays when the current rest ends"];
    return YES;
}

- (void)requestDisplaySleepWithCompletion:(void (^)(NSError *))completion {
    [self cancelDisplaySleepRequest];
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/pmset"];
    task.arguments = @[@"displaysleepnow"];
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    self.sleepTask = task;
    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *finishedTask) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DisplayPowerController *strongSelf = weakSelf;
            if (strongSelf.sleepTask != finishedTask) return;
            strongSelf.sleepTask = nil;
            completion(finishedTask.terminationStatus == 0 ? nil
                : DisplayPowerError(finishedTask.terminationStatus, @"系统未能关闭显示器，请重试。"));
        });
    };
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        self.sleepTask = nil;
        completion(launchError);
    }
}

- (void)cancelDisplaySleepRequest {
    NSTask *task = self.sleepTask;
    self.sleepTask = nil;
    if (task.isRunning) [task terminate];
}

- (BOOL)wakeDisplaysWithError:(NSError **)error {
    IOPMAssertionID assertion = kIOPMNullAssertionID;
    IOReturn result = IOPMAssertionDeclareUserActivity(CFSTR("FocusBreakTimer rest completed"),
                                                     kIOPMUserActiveLocal, &assertion);
    if (result == kIOReturnSuccess) {
        IOPMAssertionRelease(assertion);
        return YES;
    }
    if (error) *error = DisplayPowerError(result, @"自动亮屏失败，请手动亮屏。");
    return NO;
}

- (void)endRestActivity {
    if (self.activity) {
        [NSProcessInfo.processInfo endActivity:self.activity];
        self.activity = nil;
    }
    if (self.idleSleepAssertion != kIOPMNullAssertionID) {
        IOPMAssertionRelease(self.idleSleepAssertion);
        self.idleSleepAssertion = kIOPMNullAssertionID;
    }
}

- (void)dealloc {
    if (_sleepTask.isRunning) [_sleepTask terminate];
    if (_activity) [NSProcessInfo.processInfo endActivity:_activity];
    if (_idleSleepAssertion != kIOPMNullAssertionID) IOPMAssertionRelease(_idleSleepAssertion);
}

@end
