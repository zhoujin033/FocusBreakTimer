#import <Cocoa/Cocoa.h>
#define FOCUS_BREAK_TIMER_DISABLE_APP_MAIN 1
#import "../Sources/main.m"

static int integrationExitCode = 1;

static void RenderPreview(NSString *folder, NSSize size, BOOL snoozed, BOOL decision, BOOL preparing) {
    CountdownView *view = [[CountdownView alloc] initWithFrame:(NSRect){NSZeroPoint, size}];
    view.remainingSeconds = 152;
    view.progress = 152.0 / 300;
    view.skipUnlockRemainingSeconds = 0;
    view.snoozeAvailable = !snoozed;
    view.restEndsAt = [NSDate dateWithTimeIntervalSinceNow:152];
    view.displaySleepPending = preparing;
    view.displaySleepPreparing = preparing;
    if (decision) {
        view.mode = CountdownScreenModeDecision;
        view.remainingSeconds = 0;
        view.progress = 0;
    }
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)size.width pixelsHigh:(NSInteger)size.height
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    bitmap.size = size;
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [view drawRect:view.bounds];
    [NSGraphicsContext restoreGraphicsState];
    NSString *name = [NSString stringWithFormat:@"%.0fx%.0f-%@.png", size.width, size.height,
                      decision ? @"decision" : (preparing ? @"preparing" : (snoozed ? @"snoozed" : @"rest"))];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
        writeToFile:[folder stringByAppendingPathComponent:name] atomically:YES];
}

@interface DisplaySleepIntegrationDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) BreakTimerController *controller;
@property (nonatomic, strong) NSTimer *checkTimer;
@property (nonatomic, copy) NSString *suiteName;
@property (nonatomic, copy) NSString *resultPath;
@property (nonatomic) NSTimeInterval startedAt;
@property (nonatomic) BOOL observedDisplaysAsleep;
@property (nonatomic, copy) NSString *inputMode;
@property (nonatomic) NSTimeInterval displaySleepStartedAt;
@property (nonatomic) NSTimeInterval continuousDisplaySleepDuration;
@property (nonatomic) BOOL wokeBeforeRestCompleted;
@property (nonatomic) BOOL usedSystemInputEvents;
@end

@implementation DisplaySleepIntegrationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.suiteName = [@"io.github.zhoujin033.FocusBreakTimer.integration." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:self.suiteName];
    [defaults setBool:NO forKey:@"meetingScheduleEnabled"];
    NSURL *historyURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".json"]];
    self.controller = [[BreakTimerController alloc] initWithUserDefaults:defaults
                                                          historyStore:[[StudyHistoryStore alloc] initWithStorageURL:historyURL]];
    [self.controller configureKeepAliveWindow];
    [self.controller registerSystemNotifications];
    self.startedAt = BreakTimerContinuousTime();
    [self.controller startRestCycleWithDuration:20 activateObligation:YES skipLockDuration:30];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self triggerRestDisplaySleep];
    });
    self.checkTimer = [NSTimer scheduledTimerWithTimeInterval:0.2 target:self
                                                    selector:@selector(check:) userInfo:nil repeats:YES];
}

- (void)triggerRestDisplaySleep {
    BreakWindow *window = self.controller.breakWindows.lastObject;
    CountdownView *view = (CountdownView *)window.contentView;
    self.usedSystemInputEvents = CGPreflightPostEventAccess();
    if ([self.inputMode isEqualToString:@"button"]) {
        NSRect rect = view.displaySleepButtonRect;
        NSPoint point = NSMakePoint(NSMidX(rect), NSMidY(rect));
        if (self.usedSystemInputEvents) {
            NSPoint screenPoint = [window convertPointToScreen:point];
            CGFloat primaryHeight = CGDisplayBounds(CGMainDisplayID()).size.height;
            CGPoint quartzPoint = CGPointMake(screenPoint.x, primaryHeight - screenPoint.y);
            CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, quartzPoint, kCGMouseButtonLeft);
            CGEventPost(kCGHIDEventTap, down);
            CFRelease(down);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, quartzPoint, kCGMouseButtonLeft);
                CGEventPost(kCGHIDEventTap, up);
                CFRelease(up);
            });
        } else {
            NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0
                timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil
                eventNumber:0 clickCount:1 pressure:1];
            [NSApp postEvent:down atStart:NO];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:0
                    timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil
                    eventNumber:1 clickCount:1 pressure:0];
                [NSApp postEvent:up atStart:NO];
            });
        }
    } else if ([self.inputMode isEqualToString:@"shortcut"]) {
        if (self.usedSystemInputEvents) {
            for (NSNumber *key in @[@55, @56, @2]) {
                CGEventRef down = CGEventCreateKeyboardEvent(NULL, key.unsignedShortValue, true);
                CGEventSetFlags(down, kCGEventFlagMaskCommand | kCGEventFlagMaskShift);
                CGEventPost(kCGHIDEventTap, down);
                CFRelease(down);
            }
            for (NSInteger i = 0; i < 3; i++) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((0.3 + i * 0.2) * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    CGKeyCode key = (CGKeyCode[]){2, 56, 55}[i];
                    CGEventRef up = CGEventCreateKeyboardEvent(NULL, key, false);
                    CGEventSetFlags(up, i == 0 ? kCGEventFlagMaskCommand | kCGEventFlagMaskShift :
                        (i == 1 ? kCGEventFlagMaskCommand : 0));
                    CGEventPost(kCGHIDEventTap, up);
                    CFRelease(up);
                });
            }
        } else {
            NSEvent *key = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
                modifierFlags:NSEventModifierFlagCommand | NSEventModifierFlagShift
                timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil
                characters:@"D" charactersIgnoringModifiers:@"d" isARepeat:NO keyCode:2];
            [NSApp postEvent:key atStart:NO];
        }
    } else {
        [self.controller requestRestDisplaySleep];
    }
}

- (void)check:(NSTimer *)timer {
    self.observedDisplaysAsleep |= self.controller.restDisplaySleepConfirmed;
    NSTimeInterval now = BreakTimerContinuousTime();
    if ([self.controller allOnlineDisplaysAreAsleep]) {
        if (self.displaySleepStartedAt == 0) self.displaySleepStartedAt = now;
        self.continuousDisplaySleepDuration = MAX(self.continuousDisplaySleepDuration, now - self.displaySleepStartedAt);
    } else if (self.displaySleepStartedAt > 0) {
        self.continuousDisplaySleepDuration = MAX(self.continuousDisplaySleepDuration, now - self.displaySleepStartedAt);
        self.displaySleepStartedAt = 0;
        if (self.controller.phase == TimerPhaseResting && [self.controller currentPhaseRemaining] > 0.3) {
            self.wokeBeforeRestCompleted = YES;
        }
    }
    if (self.controller.phase == TimerPhaseRestComplete &&
        !self.controller.waitingForRestCompletionDisplayWake &&
        [self.controller anyOnlineDisplayIsAwake]) {
        BOOL passed = self.observedDisplaysAsleep && self.continuousDisplaySleepDuration >= 10 &&
            !self.wokeBeforeRestCompleted && !self.controller.restObligationActive &&
            self.controller.historyStore.activeSessionStartDate == nil;
        [self finish:passed];
    } else if (now - self.startedAt >= 30) {
        [self finish:NO];
    }
}

- (void)finish:(BOOL)passed {
    [self.checkTimer invalidate];
    self.checkTimer = nil;
    NSDictionary *result = @{
        @"passed": @(passed),
        @"observedAllDisplaysAsleep": @(self.observedDisplaysAsleep),
        @"displaysAwake": @([self.controller anyOnlineDisplayIsAwake]),
        @"phaseIsRestComplete": @(self.controller.phase == TimerPhaseRestComplete),
        @"restObligationCleared": @(!self.controller.restObligationActive),
        @"learningNotStarted": @(self.controller.historyStore.activeSessionStartDate == nil),
        @"elapsedSeconds": @(BreakTimerContinuousTime() - self.startedAt),
        @"continuousDisplaySleepSeconds": @(self.continuousDisplaySleepDuration),
        @"wokeBeforeRestCompleted": @(self.wokeBeforeRestCompleted),
        @"inputMode": self.inputMode ?: @"direct",
        @"usedSystemInputEvents": @(self.usedSystemInputEvents)
    };
    [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil]
        writeToFile:self.resultPath atomically:YES];
    [self.controller cancelRestDisplaySleep];
    [self.controller.timer invalidate];
    [self.controller dismissBreakWindows];
    [[NSFileManager defaultManager] removeItemAtURL:self.controller.historyStore.storageURL error:nil];
    // Always restore display power, including when its state query is stale.
    [self.controller.displayPowerController wakeDisplaysWithError:nil];
    [self.controller.userDefaults removePersistentDomainForName:self.suiteName];
    integrationExitCode = passed ? 0 : 1;
    [NSApp terminate:nil];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) return 2;
        NSApplication *app = NSApplication.sharedApplication;
        NSString *mode = [NSString stringWithUTF8String:argv[1]];
        NSString *path = [NSString stringWithUTF8String:argv[2]];
        if ([mode isEqualToString:@"--render"]) {
            [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
            RenderPreview(path, NSMakeSize(1280, 720), NO, NO, NO);
            RenderPreview(path, NSMakeSize(960, 540), YES, NO, NO);
            RenderPreview(path, NSMakeSize(960, 540), YES, NO, YES);
            RenderPreview(path, NSMakeSize(1080, 1920), NO, NO, NO);
            RenderPreview(path, NSMakeSize(1280, 720), NO, YES, NO);
            RenderPreview(path, NSMakeSize(960, 540), NO, YES, NO);
            RenderPreview(path, NSMakeSize(1512, 982), NO, YES, NO);
            RenderPreview(path, NSMakeSize(1920, 1080), NO, YES, NO);
            RenderPreview(path, NSMakeSize(1080, 1920), NO, YES, NO);
            return 0;
        }
        if (![@[@"--live", @"--live-button", @"--live-shortcut"] containsObject:mode]) return 2;
        DisplaySleepIntegrationDelegate *delegate = [[DisplaySleepIntegrationDelegate alloc] init];
        delegate.resultPath = path;
        delegate.inputMode = [mode isEqualToString:@"--live-button"] ? @"button" :
            ([mode isEqualToString:@"--live-shortcut"] ? @"shortcut" : @"direct");
        app.delegate = delegate;
        [app run];
    }
    return integrationExitCode;
}
