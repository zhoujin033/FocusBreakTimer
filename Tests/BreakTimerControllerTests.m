#import <Cocoa/Cocoa.h>
#define FOCUS_BREAK_TIMER_DISABLE_APP_MAIN 1
#import "../Sources/main.m"

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

@interface TestBreakTimerController : BreakTimerController
@property (nonatomic) BOOL testAllDisplaysAsleep;
@property (nonatomic) BOOL testAnyDisplayAwake;
@property (nonatomic) CountdownScreenMode testLastShownMode;
@property (nonatomic) NSInteger testShownCount;
@property (nonatomic, copy) NSString *testDefaultsSuite;
@end

@interface TestDisplaySleepInputStateProvider : NSObject <DisplaySleepInputStateProviding>
@property (nonatomic) DisplaySleepInputSnapshot snapshot;
@end

@implementation TestDisplaySleepInputStateProvider
- (DisplaySleepInputSnapshot)inputSnapshot { return self.snapshot; }
@end

@interface TestDisplayPowerController : NSObject <DisplayPowerControlling>
@property (nonatomic) NSInteger sleepRequests;
@property (nonatomic) NSInteger wakeRequests;
@property (nonatomic) NSInteger activityEnds;
@property (nonatomic) NSTimeInterval requestedDuration;
@property (nonatomic) BOOL activityActive;
@property (nonatomic) BOOL failActivity;
@property (nonatomic) BOOL failWake;
@property (nonatomic, copy) void (^completion)(NSError *);
@end

@implementation TestDisplayPowerController
- (BOOL)beginRestActivityForDuration:(NSTimeInterval)duration error:(NSError **)error {
    self.requestedDuration = duration;
    self.activityActive = !self.failActivity;
    if (self.failActivity && error) *error = [NSError errorWithDomain:@"test" code:1 userInfo:nil];
    return !self.failActivity;
}
- (void)requestDisplaySleepWithCompletion:(void (^)(NSError *))completion {
    self.sleepRequests++;
    self.completion = completion;
}
- (void)cancelDisplaySleepRequest {}
- (BOOL)wakeDisplaysWithError:(NSError **)error {
    self.wakeRequests++;
    if (self.failWake && error) *error = [NSError errorWithDomain:@"test" code:2 userInfo:nil];
    return !self.failWake;
}
- (void)endRestActivity {
    if (self.activityActive) self.activityEnds++;
    self.activityActive = NO;
}
@end

@interface TestEmergencyCountdownView : CountdownView
@end

@implementation TestEmergencyCountdownView

- (BOOL)isEmergencySkipPressActive {
    return YES;
}

@end

@interface TestStatusItemVisibilityObject : NSObject
@property (nonatomic, getter=isVisible) BOOL visible;
@property (nonatomic, copy) NSStatusItemAutosaveName autosaveName;
@property (nonatomic) NSStatusItemBehavior behavior;
@end

@implementation TestStatusItemVisibilityObject
@end

@implementation TestBreakTimerController

- (BOOL)allOnlineDisplaysAreAsleep {
    return self.workspaceScreensAsleep || self.testAllDisplaysAsleep;
}

- (BOOL)anyOnlineDisplayIsAwake {
    return !self.workspaceScreensAsleep && self.testAnyDisplayAwake;
}

- (void)showBreakWindowsWithMode:(CountdownScreenMode)mode {
    self.testLastShownMode = mode;
    self.testShownCount++;
}

- (void)bringBreakWindowsToFront {
}

@end

static NSCalendar *MeetingTestCalendar(void) {
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    return calendar;
}

static NSDate *MeetingTestDate(NSCalendar *calendar,
                               NSInteger year,
                               NSInteger month,
                               NSInteger day,
                               NSInteger hour,
                               NSInteger minute) {
    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.year = year;
    components.month = month;
    components.day = day;
    components.hour = hour;
    components.minute = minute;
    return [calendar dateFromComponents:components];
}

static TestBreakTimerController *FreshController(NSString *suiteName,
                                                  NSUserDefaults **defaultsOut,
                                                  StudyHistoryStore **historyStoreOut) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
    [defaults removePersistentDomainForName:suiteName];
    NSURL *historyURL = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"FocusBreakTimerControllerTests-%@.json", NSUUID.UUID.UUIDString]];
    StudyHistoryStore *historyStore = [[StudyHistoryStore alloc] initWithStorageURL:historyURL];
    TestBreakTimerController *controller = [[TestBreakTimerController alloc] initWithUserDefaults:defaults
                                                                                    historyStore:historyStore];
    controller.testAnyDisplayAwake = YES;
    if (defaultsOut) {
        *defaultsOut = defaults;
    }
    if (historyStoreOut) {
        *historyStoreOut = historyStore;
    }
    return controller;
}

static BreakTimerController *ControllerWithPendingRest(NSString *suiteName,
                                                       StudyHistoryStore **historyStoreOut) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
    [defaults removePersistentDomainForName:suiteName];
    RestObligationStore *restStore = [[RestObligationStore alloc] initWithUserDefaults:defaults];
    [restStore saveRemainingDuration:240 totalDuration:300 snoozeUsed:YES synchronously:YES];

    NSURL *historyURL = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"FocusBreakTimerControllerTests-%@.json", NSUUID.UUID.UUIDString]];
    StudyHistoryStore *historyStore = [[StudyHistoryStore alloc] initWithStorageURL:historyURL];
    if (historyStoreOut) {
        *historyStoreOut = historyStore;
    }
    TestBreakTimerController *controller = [[TestBreakTimerController alloc] initWithUserDefaults:defaults
                                                                                    historyStore:historyStore];
    controller.testAnyDisplayAwake = YES;
    return controller;
}

static void TestDisplayInactivityRequiresEveryDisplayAndCreditsRest(void) {
    NSString *suiteName = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.controller-tests.%@", NSUUID.UUID.UUIDString];
    TestBreakTimerController *controller = (TestBreakTimerController *)ControllerWithPendingRest(suiteName, NULL);
    controller.phase = TimerPhaseSnoozingRest;
    controller.phaseEndsAtContinuousTime = BreakTimerContinuousTime() + 60;

    controller.testAllDisplaysAsleep = NO;
    [controller reconcileDisplayInactivity];
    Require(!controller.isAsleep, @"one awake external display must prevent rest credit");

    controller.testAllDisplaysAsleep = YES;
    [controller reconcileDisplayInactivity];
    Require(controller.isAsleep, @"all sleeping displays should begin eligible rest credit");
    Require(fabs(controller.restRemainingAtInactivityStart - controller.restDuration) < 0.1,
            @"snoozed rest should require the full rest duration when displays turn off");

    controller.eligibleInactivityStartedAtContinuousTime = BreakTimerContinuousTime() - 120;
    controller.testAllDisplaysAsleep = NO;
    [controller resumeAfterEligibleInactivityIfPossible];
    Require(!controller.isAsleep && controller.phase == TimerPhaseResting,
            @"waking early should return to the remaining rest, not study");
    Require(controller.restObligationActive, @"partial display sleep must preserve the rest obligation");
    Require([controller currentPhaseRemaining] > 170 && [controller currentPhaseRemaining] <= 181,
            @"two minutes of display sleep should leave about three minutes of rest");

    [controller beginEligibleInactivityAtDate:NSDate.date reason:@"test all displays asleep"];
    controller.eligibleInactivityStartedAtContinuousTime = BreakTimerContinuousTime() - 181;
    controller.testAllDisplaysAsleep = NO;
    [controller resumeAfterEligibleInactivityIfPossible];
    Require(controller.phase == TimerPhaseWorking && !controller.restObligationActive,
            @"enough additional display sleep should satisfy rest and start work automatically");
    [[[NSUserDefaults alloc] initWithSuiteName:suiteName] removePersistentDomainForName:suiteName];
}

static void TestMenuRaceAtWorkDeadlineStartsRestFirst(void) {
    NSString *suiteName = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.controller-tests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
    NSURL *historyURL = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"FocusBreakTimerDeadlineTests-%@.json", NSUUID.UUID.UUIDString]];
    StudyHistoryStore *historyStore = [[StudyHistoryStore alloc] initWithStorageURL:historyURL];
    TestBreakTimerController *controller = [[TestBreakTimerController alloc] initWithUserDefaults:defaults
                                                                                    historyStore:historyStore];
    controller.phase = TimerPhaseWorking;
    controller.phaseEndsAtContinuousTime = BreakTimerContinuousTime() - 0.1;
    [controller restartWorkFromMenu:nil];
    Require(controller.phase == TimerPhaseResting && controller.restObligationActive,
            @"menu restart at the work deadline must enter rest before evaluating the action");
    [controller stopStudyFromMenu:nil];
    Require(controller.phase == TimerPhaseResting, @"menu stop at the deadline must not cancel due rest");
    userRequestedQuit = NO;
    [controller quitFromMenu:nil];
    Require(!userRequestedQuit, @"menu quit at the deadline must not cancel due rest");
    [defaults removePersistentDomainForName:suiteName];
}

static void TestPendingRestBlocksEveryStudyEntry(void) {
    NSString *suiteName = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.controller-tests.%@", NSUUID.UUID.UUIDString];
    StudyHistoryStore *historyStore = nil;
    BreakTimerController *controller = ControllerWithPendingRest(suiteName, &historyStore);
    controller.phase = TimerPhaseSnoozingRest;
    controller.phaseEndsAtContinuousTime = BreakTimerContinuousTime() + 60;
    controller.phaseEndsAt = [NSDate dateWithTimeIntervalSinceNow:60];
    controller.breakItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    controller.restartItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    controller.stopItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    controller.quitItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [controller updateConfigurableMenuItems];

    Require(controller.restObligationActive, @"controller should restore the pending rest obligation");
    Require(controller.hasSnoozedCurrentCycle, @"controller should restore the used snooze allowance");
    Require([controller.breakItem.title isEqualToString:@"立即开始休息"] && controller.breakItem.enabled,
            @"snoozed rest should only offer beginning the required rest immediately");
    Require(!controller.restartItem.enabled &&
            [controller.restartItem.title isEqualToString:@"休息完成后可开始学习"],
            @"work restart must be visibly disabled while rest is pending");
    Require(!controller.stopItem.enabled, @"stop study must be visibly disabled while rest is pending");
    Require(!controller.quitItem.enabled, @"quit must be visibly disabled while rest is pending");

    [controller startWorkCycle];
    Require(controller.phase == TimerPhaseSnoozingRest, @"direct work start must not bypass snoozed rest");
    Require(historyStore.activeSessionStartDate == nil, @"blocked work start must not create study history");

    [controller restartWorkFromMenu:nil];
    Require(controller.phase == TimerPhaseSnoozingRest, @"menu restart must not bypass snoozed rest");
    [controller stopStudy];
    Require(controller.phase == TimerPhaseSnoozingRest, @"direct stop must not create a stop-and-restart bypass");
    [controller stopStudyFromMenu:nil];
    Require(controller.phase == TimerPhaseSnoozingRest, @"menu stop must not create a stop-and-restart bypass");
    userRequestedQuit = NO;
    [controller quitFromMenu:nil];
    Require(!userRequestedQuit, @"menu quit must not terminate the app while rest is pending");

    controller.phase = TimerPhaseResting;
    [controller startBreakNow:nil];
    Require(controller.phase == TimerPhaseResting, @"starting rest again must not reset an active rest");
    Require(controller.hasSnoozedCurrentCycle, @"starting rest again must not restore snooze availability");

    [[[NSUserDefaults alloc] initWithSuiteName:suiteName] removePersistentDomainForName:suiteName];
}

static void TestWorkCanStartAfterObligationResolution(void) {
    NSString *suiteName = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.controller-tests.%@", NSUUID.UUID.UUIDString];
    StudyHistoryStore *historyStore = nil;
    BreakTimerController *controller = ControllerWithPendingRest(suiteName, &historyStore);
    controller.restObligationActive = NO;
    [controller clearPersistedRestObligation];
    [controller startWorkCycle];
    Require(controller.phase == TimerPhaseWorking, @"resolved rest should allow a new work cycle");
    Require(historyStore.activeSessionStartDate != nil, @"allowed work start should create an active study session");
    [controller stopStudy];
    [[[NSUserDefaults alloc] initWithSuiteName:suiteName] removePersistentDomainForName:suiteName];
}

static void TestMeetingScheduleStopsOnceAndSupportsEarlyResume(void) {
    NSString *suiteName = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.controller-tests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = nil;
    StudyHistoryStore *historyStore = nil;
    TestBreakTimerController *controller = FreshController(suiteName, &defaults, &historyStore);
    NSCalendar *calendar = MeetingTestCalendar();
    controller.meetingScheduleCalendar = calendar;
    NSDate *meetingStart = MeetingTestDate(calendar, 2026, 8, 12, 14, 0);
    NSDate *meetingMiddle = MeetingTestDate(calendar, 2026, 8, 12, 15, 0);
    NSDate *meetingEnd = MeetingTestDate(calendar, 2026, 8, 12, 17, 0);

    controller.phase = TimerPhaseWorking;
    controller.phaseEndsAtContinuousTime = BreakTimerContinuousTime() + 1200;
    [historyStore beginSessionAtDate:[meetingStart dateByAddingTimeInterval:-300]];
    Require([controller reconcileMeetingScheduleAtDate:meetingStart], @"meeting start should be handled");
    Require(controller.phase == TimerPhaseStopped && historyStore.activeSessionStartDate == nil,
            @"meeting start should stop study and close its history segment");
    Require(controller.meetingScheduleStore.stoppedBySchedule &&
            [controller.meetingScheduleStore.pendingAutoResumeDate isEqualToDate:meetingEnd],
            @"automatic meeting stop should schedule the end recovery");

    [controller restartWorkFromMenu:nil];
    Require(controller.phase == TimerPhaseWorking && !controller.meetingScheduleStore.stoppedBySchedule,
            @"the user should be able to resume early during the meeting");
    NSTimeInterval earlyResumeDeadline = controller.phaseEndsAtContinuousTime;
    Require(![controller reconcileMeetingScheduleAtDate:meetingMiddle],
            @"the same meeting must not stop an early manual resume again");
    [controller reconcileMeetingScheduleAtDate:meetingEnd];
    Require(controller.phase == TimerPhaseWorking &&
            fabs(controller.phaseEndsAtContinuousTime - earlyResumeDeadline) < 0.1,
            @"17:00 must not reset a work cycle that resumed early");
    Require(controller.meetingScheduleStore.pendingAutoResumeDate == nil,
            @"meeting end should clear completed schedule metadata");
    [controller stopStudy];
    [defaults removePersistentDomainForName:suiteName];
}

static void TestMeetingScheduleAutoResumeAndManualStopRules(void) {
    NSCalendar *calendar = MeetingTestCalendar();
    NSDate *meetingStart = MeetingTestDate(calendar, 2026, 8, 16, 14, 0);
    NSDate *beforeMeeting = MeetingTestDate(calendar, 2026, 8, 16, 13, 59);
    NSDate *beforeMeetingEnd = MeetingTestDate(calendar, 2026, 8, 16, 16, 59);
    NSDate *meetingEnd = MeetingTestDate(calendar, 2026, 8, 16, 17, 0);

    NSString *autoSuite = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.controller-tests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *autoDefaults = nil;
    TestBreakTimerController *autoController = FreshController(autoSuite, &autoDefaults, NULL);
    autoController.meetingScheduleCalendar = calendar;
    autoController.phase = TimerPhaseWorking;
    Require(![autoController reconcileMeetingScheduleAtDate:beforeMeeting] &&
            autoController.phase == TimerPhaseWorking,
            @"13:59 should not stop study");
    [autoController reconcileMeetingScheduleAtDate:meetingStart];
    Require(autoController.phase == TimerPhaseStopped, @"meeting should stop an active work cycle");
    autoController.isAsleep = YES;
    [autoController reconcileMeetingScheduleAtDate:beforeMeetingEnd];
    Require(autoController.phase == TimerPhaseStopped && autoController.isAsleep,
            @"waking or reconciling at 16:59 should preserve the scheduled stop");
    [autoController reconcileMeetingScheduleAtDate:meetingEnd];
    Require(autoController.phase == TimerPhaseWorking && !autoController.isAsleep,
            @"17:00 should start a full cycle when the scheduled stop remains active");
    [autoController stopStudy];
    [autoDefaults removePersistentDomainForName:autoSuite];

    NSString *manualSuite = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.controller-tests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *manualDefaults = nil;
    TestBreakTimerController *manualController = FreshController(manualSuite, &manualDefaults, NULL);
    manualController.meetingScheduleCalendar = calendar;
    manualController.phase = TimerPhaseWorking;
    [manualController reconcileMeetingScheduleAtDate:meetingStart];
    [manualController restartWorkFromMenu:nil];
    [manualController stopStudyFromMenu:nil];
    Require(manualController.meetingScheduleStore.pendingAutoResumeDate == nil,
            @"manual stop after an early resume should cancel auto recovery");
    [manualController reconcileMeetingScheduleAtDate:meetingEnd];
    Require(manualController.phase == TimerPhaseStopped,
            @"17:00 should respect an explicit manual stop");
    [manualDefaults removePersistentDomainForName:manualSuite];
}

static void TestMeetingMidWindowCatchUpPersistsWithoutRetrigger(void) {
    NSString *suiteName = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.controller-tests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = nil;
    TestBreakTimerController *controller = FreshController(suiteName, &defaults, NULL);
    NSCalendar *calendar = MeetingTestCalendar();
    controller.meetingScheduleCalendar = calendar;
    NSDate *middle = MeetingTestDate(calendar, 2026, 8, 12, 15, 0);
    controller.phase = TimerPhaseWorking;
    Require([controller reconcileMeetingScheduleAtDate:middle] && controller.phase == TimerPhaseStopped,
            @"first launch in the middle of a meeting should catch up the stop event");

    NSURL *historyURL = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"FocusBreakTimerControllerTests-%@.json", NSUUID.UUID.UUIDString]];
    StudyHistoryStore *historyStore = [[StudyHistoryStore alloc] initWithStorageURL:historyURL];
    TestBreakTimerController *reopened = [[TestBreakTimerController alloc] initWithUserDefaults:
        [[NSUserDefaults alloc] initWithSuiteName:suiteName] historyStore:historyStore];
    reopened.meetingScheduleCalendar = calendar;
    reopened.testAnyDisplayAwake = YES;
    reopened.phase = TimerPhaseWorking;
    Require([reopened reconcileMeetingScheduleAtDate:[middle dateByAddingTimeInterval:60]] &&
            reopened.phase == TimerPhaseStopped,
            @"reopening during an unresolved scheduled stop should remain stopped");

    reopened.meetingScheduleStore.enabled = NO;
    [reopened.meetingScheduleStore cancelPendingAutoResume];
    [reopened restartWorkFromMenu:nil];
    reopened.meetingScheduleStore.enabled = YES;
    Require(![reopened reconcileMeetingScheduleAtDate:[middle dateByAddingTimeInterval:120]] &&
            reopened.phase == TimerPhaseWorking,
            @"turning the switch back on must not retrigger an already handled meeting");
    [reopened stopStudy];
    [defaults removePersistentDomainForName:suiteName];
}

static void TestDisabledMeetingScheduleDoesNothing(void) {
    NSString *suiteName = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.controller-tests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = nil;
    TestBreakTimerController *controller = FreshController(suiteName, &defaults, NULL);
    NSCalendar *calendar = MeetingTestCalendar();
    controller.meetingScheduleCalendar = calendar;
    controller.meetingScheduleStore.enabled = NO;
    controller.phase = TimerPhaseWorking;
    NSDate *meetingStart = MeetingTestDate(calendar, 2026, 8, 12, 14, 0);
    Require(![controller reconcileMeetingScheduleAtDate:meetingStart] && controller.phase == TimerPhaseWorking,
            @"disabled meeting schedule must not stop study");
    [defaults removePersistentDomainForName:suiteName];
}

static void TestUpdatedMeetingScheduleAndLegacyResume(void) {
    NSCalendar *calendar = MeetingTestCalendar();
    NSString *suite = [@"io.github.zhoujin033.FocusBreakTimer.updated-meetings." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = nil;
    TestBreakTimerController *controller = FreshController(suite, &defaults, NULL);
    controller.meetingScheduleCalendar = calendar;
    controller.phase = TimerPhaseWorking;
    Require(![controller reconcileMeetingScheduleAtDate:MeetingTestDate(calendar, 2026, 8, 11, 14, 30)] &&
            controller.phase == TimerPhaseWorking,
            @"the former Tuesday meeting must no longer stop study");
    Require(![controller reconcileMeetingScheduleAtDate:MeetingTestDate(calendar, 2026, 8, 12, 13, 59)],
            @"Wednesday study should continue until 14:00");
    [controller reconcileMeetingScheduleAtDate:MeetingTestDate(calendar, 2026, 8, 12, 14, 0)];
    Require(controller.phase == TimerPhaseStopped &&
            [controller.meetingScheduleStore.pendingAutoResumeDate isEqualToDate:MeetingTestDate(calendar, 2026, 8, 12, 17, 0)],
            @"Wednesday 14:00 should stop study and schedule recovery for 17:00");
    [controller stopStudyFromMenu:nil];

    [controller.meetingScheduleStore markOccurrenceHandled:@"2026-08-16"
                                          autoResumeDate:MeetingTestDate(calendar, 2026, 8, 16, 17, 30)
                                       stoppedBySchedule:YES];
    [controller reconcileMeetingScheduleAtDate:MeetingTestDate(calendar, 2026, 8, 16, 16, 59)];
    Require(controller.phase == TimerPhaseStopped &&
            [controller.meetingScheduleStore.pendingAutoResumeDate isEqualToDate:MeetingTestDate(calendar, 2026, 8, 16, 17, 0)],
            @"an old Sunday 17:30 recovery must move to 17:00 after upgrade");
    [controller reconcileMeetingScheduleAtDate:MeetingTestDate(calendar, 2026, 8, 16, 17, 0)];
    Require(controller.phase == TimerPhaseWorking && controller.meetingScheduleStore.pendingAutoResumeDate == nil,
            @"an upgraded Sunday meeting must resume at 17:00 without waiting another half hour");
    [controller stopStudy];

    [controller.meetingScheduleStore markOccurrenceHandled:@"2026-08-11"
                                          autoResumeDate:MeetingTestDate(calendar, 2026, 8, 11, 17, 30)
                                       stoppedBySchedule:YES];
    [controller reconcileMeetingScheduleAtDate:MeetingTestDate(calendar, 2026, 8, 11, 16, 0)];
    Require(controller.meetingScheduleStore.pendingAutoResumeDate == nil &&
            !controller.meetingScheduleStore.stoppedBySchedule,
            @"an obsolete Tuesday recovery must be cancelled after upgrade");
    [controller reconcileMeetingScheduleAtDate:MeetingTestDate(calendar, 2026, 8, 11, 17, 30)];
    Require(controller.phase == TimerPhaseStopped, @"the old Tuesday event must not restart a stopped session");
    [controller.timer invalidate];
    [controller.meetingScheduleTimer invalidate];
    [defaults removePersistentDomainForName:suite];
}

static void TestEmergencySkipQuotaControlsCompletion(void) {
    NSString *suiteName = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.controller-tests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = nil;
    TestBreakTimerController *controller = FreshController(suiteName, &defaults, NULL);

    [controller startRestCycle];
    [controller snoozeRestCycle];
    Require(controller.phase == TimerPhaseSnoozingRest &&
            [controller.emergencySkipQuotaStore usageAtDate:NSDate.date].dailyCount == 0,
            @"using the one-minute delay must not consume emergency skip quota");
    controller.restObligationActive = NO;
    [controller clearPersistedRestObligation];

    for (NSInteger attempt = 1; attempt <= 3; attempt++) {
        [controller startRestCycle];
        controller.restSkipAvailableAtContinuousTime = BreakTimerContinuousTime() - 1;
        TestEmergencyCountdownView *view = [[TestEmergencyCountdownView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
        controller.emergencySkipHoldView = view;
        controller.emergencySkipHoldStartedAt = NSDate.date;
        if (attempt == 1) {
            controller.emergencySkipHoldStartedAtContinuousTime = BreakTimerContinuousTime() - 1;
            [controller emergencySkipHoldTick:nil];
            Require(controller.phase == TimerPhaseResting &&
                    [controller.emergencySkipQuotaStore usageAtDate:NSDate.date].dailyCount == 0,
                    @"a hold shorter than five seconds must neither end rest nor consume quota");
        }
        controller.emergencySkipHoldStartedAtContinuousTime = BreakTimerContinuousTime() - RestSkipHoldDuration - 0.1;
        [controller emergencySkipHoldTick:nil];

        if (attempt <= 2) {
            Require(controller.phase == TimerPhaseRestComplete && !controller.restObligationActive,
                    @"the first two successful holds should end rest");
        } else {
            Require(controller.phase == TimerPhaseResting && controller.restObligationActive,
                    @"the third daily hold must not end rest");
        }
    }
    EmergencySkipUsage *usage = [controller.emergencySkipQuotaStore usageAtDate:NSDate.date];
    Require(usage.dailyCount == 2 && usage.limitReason == EmergencySkipLimitReasonDaily,
            @"only two successful emergency skips should be recorded for the day");
    [defaults removePersistentDomainForName:suiteName];
}

static void TestMeetingScheduleStopsSnoozeAndRestDecisionStates(void) {
    NSCalendar *calendar = MeetingTestCalendar();
    NSDate *wednesdayMeeting = MeetingTestDate(calendar, 2026, 8, 12, 14, 0);
    NSDate *sundayMeeting = MeetingTestDate(calendar, 2026, 8, 16, 14, 0);

    NSString *snoozeSuite = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.controller-tests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *snoozeDefaults = nil;
    TestBreakTimerController *snoozeController = FreshController(snoozeSuite, &snoozeDefaults, NULL);
    snoozeController.meetingScheduleCalendar = calendar;
    [snoozeController startRestCycle];
    [snoozeController snoozeRestCycle];
    Require(snoozeController.phase == TimerPhaseSnoozingRest,
            @"test should begin in delayed-rest state");
    [snoozeController reconcileMeetingScheduleAtDate:wednesdayMeeting];
    Require(snoozeController.phase == TimerPhaseStopped && !snoozeController.restObligationActive,
            @"meeting start should cancel delayed rest and enter the normal stopped state");
    [snoozeDefaults removePersistentDomainForName:snoozeSuite];

    NSString *decisionSuite = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.controller-tests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *decisionDefaults = nil;
    TestBreakTimerController *decisionController = FreshController(decisionSuite, &decisionDefaults, NULL);
    decisionController.meetingScheduleCalendar = calendar;
    decisionController.phase = TimerPhaseRestComplete;
    decisionController.restObligationActive = NO;
    [decisionController reconcileMeetingScheduleAtDate:sundayMeeting];
    Require(decisionController.phase == TimerPhaseStopped,
            @"meeting start should close the rest decision screen and enter the normal stopped state");
    [decisionDefaults removePersistentDomainForName:decisionSuite];
}

static void TestSettingsPersistMeetingScheduleSwitch(void) {
    __unused NSApplication *application = NSApplication.sharedApplication;
    NSString *suiteName = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.controller-tests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = nil;
    TestBreakTimerController *controller = FreshController(suiteName, &defaults, NULL);
    [controller showSettingsWindow];
    Require(controller.settingsMeetingScheduleCheckbox.state == NSControlStateValueOn,
            @"meeting schedule checkbox should default to enabled");
    controller.settingsMeetingScheduleCheckbox.state = NSControlStateValueOff;
    [controller saveSettings:nil];
    Require(!controller.meetingScheduleStore.isEnabled,
            @"saving the disabled checkbox should disable the meeting schedule");

    [controller showSettingsWindow];
    controller.settingsMeetingScheduleCheckbox.state = NSControlStateValueOn;
    [controller saveSettings:nil];
    Require(controller.meetingScheduleStore.isEnabled,
            @"saving the enabled checkbox should restore the meeting schedule");
    [controller.settingsWindow orderOut:nil];
    [defaults removePersistentDomainForName:suiteName];
}

static void TestRestDurationSettingsAndCycleBoundaries(void) {
    NSString *suite = [@"io.github.zhoujin033.FocusBreakTimer.rest-settings-tests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = nil;
    TestBreakTimerController *controller = FreshController(suite, &defaults, NULL);
    Require(controller.restDuration == 120 && [controller validatedRestDurationMinutes] == 2,
            @"new and upgraded installations should default to a two-minute rest");
    controller.phaseEndsAtContinuousTime = BreakTimerContinuousTime() + 600;
    controller.breakItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    controller.restartItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    controller.stopItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    controller.quitItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [controller showSettingsWindow];
    Require([controller.settingsRestMinutesField.stringValue isEqualToString:@"2"] &&
            !NSIntersectsRect(controller.settingsMinutesField.frame, controller.settingsRestMinutesField.frame) &&
            NSContainsRect(controller.settingsWindow.contentView.bounds, controller.settingsRestMinutesField.frame),
            @"settings should show a separate, on-screen rest duration field with the two-minute default");
    controller.settingsMeetingScheduleCheckbox.state = NSControlStateValueOff;
    controller.settingsMinutesField.stringValue = @"40";
    controller.settingsRestMinutesField.stringValue = @"5";
    NSTimeInterval workDeadline = controller.phaseEndsAtContinuousTime;
    [controller saveSettings:nil];
    Require([defaults integerForKey:RestDurationMinutesDefaultsKey] == 5 &&
            controller.phaseEndsAtContinuousTime == workDeadline && controller.restDuration == 120 &&
            [controller.breakItem.title isEqualToString:@"立刻休息 5 分钟"],
            @"saving should persist the next rest length and menu title without resetting the active timer");
    [controller startRestCycle];
    Require(controller.restDuration == 300 && [controller currentPhaseRemaining] > 299,
            @"the next new rest should use the saved five-minute duration");
    NSTimeInterval restDeadline = controller.phaseEndsAtContinuousTime;
    [controller showSettingsWindow];
    controller.settingsRestMinutesField.stringValue = @"1";
    [controller saveSettings:nil];
    Require(controller.restDuration == 300 && controller.phaseEndsAtContinuousTime == restDeadline,
            @"changing settings during rest must preserve its deadline, progress denominator, and wake duration");
    [controller snoozeRestCycle];
    controller.phaseEndsAtContinuousTime = BreakTimerContinuousTime() - 1;
    [controller tick:nil];
    Require(controller.restDuration == 300 && [controller currentPhaseRemaining] > 299 && controller.hasSnoozedCurrentCycle,
            @"snooze must return to the original full rest without adopting a shorter setting");
    [controller completeRestCycle];
    [controller startWorkCycle];
    [controller startBreakNow:nil];
    Require(controller.restDuration == 60 && [controller currentPhaseRemaining] > 59,
            @"a new manual rest should now use the saved one-minute duration");
    [controller showSettingsWindow];
    controller.settingsRestMinutesField.stringValue = @"10";
    [controller saveSettings:nil];
    TestBreakTimerController *reopened = [[TestBreakTimerController alloc] initWithUserDefaults:defaults historyStore:controller.historyStore];
    Require([reopened validatedRestDurationMinutes] == 10 && reopened.restDuration == 60 &&
            reopened.restoredRestRemaining > 59 && reopened.restoredRestRemaining <= 60,
            @"restart must restore the unfinished one-minute cycle while retaining the new ten-minute preference");
    [controller.timer invalidate];
    [controller.meetingScheduleTimer invalidate];
    [controller.settingsWindow orderOut:nil];
    [defaults removePersistentDomainForName:suite];
}

static void TestRestDurationValidation(void) {
    NSInteger minutes = 0;
    for (NSString *valid in @[@"1", @"2", @"60", @" 5 \n"]) {
        Require(ParseDurationMinutes(valid, MaximumRestDurationMinutes, &minutes), @"valid integer rest minutes should be accepted");
    }
    for (NSString *invalid in @[@"", @" ", @"0", @"-1", @"61", @"240", @"1.5", @"2分钟", @"abc", @"99999999999999999999999999"]) {
        Require(!ParseDurationMinutes(invalid, MaximumRestDurationMinutes, &minutes), @"invalid or out-of-range rest minutes must be rejected");
    }
    NSString *suite = [@"io.github.zhoujin033.FocusBreakTimer.invalid-rest-tests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = nil;
    TestBreakTimerController *controller = FreshController(suite, &defaults, NULL);
    [defaults setInteger:0 forKey:RestDurationMinutesDefaultsKey];
    Require([controller validatedRestDurationMinutes] == 2, @"invalid persisted rest settings must recover to two minutes");
    [defaults setInteger:61 forKey:RestDurationMinutesDefaultsKey];
    Require([controller validatedRestDurationMinutes] == 2, @"oversized persisted settings must recover to two minutes");
    [defaults removePersistentDomainForName:suite];
}

static void TestStatusItemUsesIndependentVisibilityIdentity(void) {
    NSString *suiteName = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.controller-tests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = nil;
    TestBreakTimerController *controller = FreshController(suiteName, &defaults, NULL);
    TestStatusItemVisibilityObject *visibilityObject = [[TestStatusItemVisibilityObject alloc] init];
    controller.statusItem = (NSStatusItem *)(id)visibilityObject;
    [controller configureStatusItemVisibilityPolicy];
    Require([visibilityObject.autosaveName isEqualToString:PrimaryStatusItemAutosaveName],
            @"status item should use an app-specific persistent visibility identity");
    Require(visibilityObject.isVisible && visibilityObject.behavior == 0,
            @"status item should start visible and should not allow system removal");

    visibilityObject.visible = NO;
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    Require(visibilityObject.isVisible,
            @"an external visibility change should be restored automatically");
    [defaults removePersistentDomainForName:suiteName];
}

static void TestLegacyPreferencesMigrationPreservesTimerState(void) {
    NSString *currentSuite = [NSString stringWithFormat:@"io.github.zhoujin033.FocusBreakTimer.migration-tests.%@", NSUUID.UUID.UUIDString];
    NSString *legacySuite = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.migration-tests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *currentDefaults = [[NSUserDefaults alloc] initWithSuiteName:currentSuite];
    NSUserDefaults *legacyDefaults = [[NSUserDefaults alloc] initWithSuiteName:legacySuite];
    [currentDefaults removePersistentDomainForName:currentSuite];
    [legacyDefaults removePersistentDomainForName:legacySuite];

    [currentDefaults setInteger:25 forKey:WorkDurationMinutesDefaultsKey];
    [legacyDefaults setInteger:40 forKey:WorkDurationMinutesDefaultsKey];
    [legacyDefaults setBool:YES forKey:@"pendingRestObligation"];
    [legacyDefaults setDouble:180 forKey:@"pendingRestRemainingSeconds"];
    [legacyDefaults setObject:@[@(NSDate.date.timeIntervalSince1970)] forKey:@"emergencySkipTimestamps"];
    [legacyDefaults setInteger:123 forKey:@"NSStatusItem Preferred Position Item-0"];

    MigrateLegacyPreferences(currentDefaults, legacyDefaults);
    Require([currentDefaults integerForKey:WorkDurationMinutesDefaultsKey] == 25,
            @"migration should not replace preferences already saved by the new app identity");
    Require([currentDefaults boolForKey:@"pendingRestObligation"],
            @"migration should preserve a pending rest obligation");
    Require([currentDefaults doubleForKey:@"pendingRestRemainingSeconds"] == 180,
            @"migration should preserve the remaining rest duration");
    Require([currentDefaults arrayForKey:@"emergencySkipTimestamps"].count == 1,
            @"migration should preserve emergency skip usage");
    Require([currentDefaults objectForKey:@"NSStatusItem Preferred Position Item-0"] == nil,
            @"migration should not copy the contaminated legacy status item identity");

    [legacyDefaults setBool:NO forKey:@"pendingRestObligation"];
    MigrateLegacyPreferences(currentDefaults, legacyDefaults);
    Require([currentDefaults boolForKey:@"pendingRestObligation"],
            @"migration should run only once");

    [currentDefaults removePersistentDomainForName:currentSuite];
    [legacyDefaults removePersistentDomainForName:legacySuite];
}

static void TestMeetingScheduleInterruptsRestWithoutUsingSkipQuota(void) {
    NSString *suiteName = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.controller-tests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = nil;
    TestBreakTimerController *controller = FreshController(suiteName, &defaults, NULL);
    NSCalendar *calendar = MeetingTestCalendar();
    controller.meetingScheduleCalendar = calendar;
    NSDate *meetingStart = MeetingTestDate(calendar, 2026, 8, 12, 14, 0);

    [controller startRestCycle];
    Require(controller.restObligationActive, @"test should begin with a required rest");
    [controller reconcileMeetingScheduleAtDate:meetingStart];
    Require(controller.phase == TimerPhaseStopped && !controller.restObligationActive,
            @"meeting schedule should cancel an active rest and enter the regular stopped state");
    Require([controller.emergencySkipQuotaStore usageAtDate:meetingStart].weeklyCount == 0,
            @"meeting cancellation must not consume emergency skip quota");
    RestObligationSnapshot *snapshot = [controller.restObligationStore snapshotWithDefaultDuration:controller.restDuration];
    Require(!snapshot.pending, @"meeting cancellation should clear persisted rest obligation");
    [defaults removePersistentDomainForName:suiteName];
}

static void TestAlreadyStoppedMeetingDoesNotAutoResume(void) {
    NSString *suiteName = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.controller-tests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = nil;
    TestBreakTimerController *controller = FreshController(suiteName, &defaults, NULL);
    NSCalendar *calendar = MeetingTestCalendar();
    controller.meetingScheduleCalendar = calendar;
    NSDate *meetingStart = MeetingTestDate(calendar, 2026, 8, 12, 14, 0);
    NSDate *meetingEnd = MeetingTestDate(calendar, 2026, 8, 12, 17, 0);
    controller.phase = TimerPhaseStopped;
    [controller reconcileMeetingScheduleAtDate:meetingStart];
    Require(controller.meetingScheduleStore.pendingAutoResumeDate == nil,
            @"a study session stopped before the meeting must not gain auto resume");
    [controller reconcileMeetingScheduleAtDate:meetingEnd];
    Require(controller.phase == TimerPhaseStopped, @"17:00 should preserve the pre-existing stopped state");
    [defaults removePersistentDomainForName:suiteName];
}

static void TestMeetingEndDoesNotInterruptUserStartedRest(void) {
    NSString *suiteName = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.controller-tests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = nil;
    TestBreakTimerController *controller = FreshController(suiteName, &defaults, NULL);
    NSCalendar *calendar = MeetingTestCalendar();
    controller.meetingScheduleCalendar = calendar;
    NSDate *meetingStart = MeetingTestDate(calendar, 2026, 8, 12, 14, 0);
    NSDate *meetingEnd = MeetingTestDate(calendar, 2026, 8, 12, 17, 0);
    controller.phase = TimerPhaseWorking;
    [controller reconcileMeetingScheduleAtDate:meetingStart];
    [controller startBreakNow:nil];
    Require(controller.phase == TimerPhaseResting && controller.restObligationActive,
            @"the normal stopped state should still allow the user to start a rest");
    [controller reconcileMeetingScheduleAtDate:meetingEnd];
    Require(controller.phase == TimerPhaseResting && controller.restObligationActive,
            @"17:00 must not interrupt a rest the user started after the scheduled stop");
    Require(controller.meetingScheduleStore.pendingAutoResumeDate == nil,
            @"the obsolete auto-resume event should still be cleared");
    [defaults removePersistentDomainForName:suiteName];
}

static TestBreakTimerController *RestDisplaySleepController(NSTimeInterval duration,
                                                           TestDisplayPowerController **powerOut) {
    NSString *suite = [NSString stringWithFormat:@"io.github.zhoujin033.FocusBreakTimer.display-tests.%@", NSUUID.UUID.UUIDString];
    TestBreakTimerController *controller = FreshController(suite, NULL, NULL);
    controller.testDefaultsSuite = suite;
    controller.meetingScheduleStore.enabled = NO;
    TestDisplayPowerController *power = [[TestDisplayPowerController alloc] init];
    controller.displayPowerController = power;
    TestDisplaySleepInputStateProvider *input = [[TestDisplaySleepInputStateProvider alloc] init];
    input.snapshot = (DisplaySleepInputSnapshot){NO, 10};
    controller.displaySleepInputStateProvider = input;
    [controller startRestCycleWithDuration:duration activateObligation:YES skipLockDuration:30];
    if (powerOut) *powerOut = power;
    return controller;
}

static void CleanUpDisplaySleepTest(TestBreakTimerController *controller) {
    [controller cancelRestDisplaySleep];
    [controller.timer invalidate];
    controller.timer = nil;
    [controller.meetingScheduleTimer invalidate];
    [controller cancelEmergencySkipHold];
    [controller.userDefaults removePersistentDomainForName:controller.testDefaultsSuite];
}

static void ConfirmTestDisplaysAsleep(TestBreakTimerController *controller) {
    controller.testAllDisplaysAsleep = YES;
    controller.testAnyDisplayAwake = NO;
    [controller restDisplaySleepTick];
    Require(controller.isAsleep && controller.restDisplaySleepConfirmed,
            @"display sleep should only be confirmed once every display is off");
}

static void TestRestCompletionKeepsExistingView(void) {
    for (NSNumber *early in @[@NO, @YES]) {
        TestBreakTimerController *controller = RestDisplaySleepController(120, NULL);
        BreakWindow *window = [[BreakWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1280, 720)
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        CountdownView *view = [[CountdownView alloc] initWithFrame:window.contentView.bounds];
        window.contentView = view;
        [controller.breakWindows addObject:window];
        [controller updateRestWindowsWithRemainingSeconds:1];
        NSRect ring = [view progressRingRect];
        NSRect left = view.snoozeRestButtonRect;
        NSRect right = view.displaySleepButtonRect;
        NSInteger shownBefore = controller.testShownCount;
        [controller completeRestCycleWithEarlyEnd:early.boolValue];
        Require(controller.breakWindows.firstObject == window && window.contentView == view &&
                controller.testShownCount == shownBefore,
                @"natural and early rest completion must update the existing view without replacing its window");
        Require(view.mode == CountdownScreenModeDecision && view.remainingSeconds == 0 &&
                NSEqualRects(ring, [view progressRingRect]) &&
                NSEqualRects(left, view.continueStudyButtonRect) && NSEqualRects(right, view.stopStudyButtonRect),
                @"the final countdown frame and choice frame must share the ring and action geometry");
        Require(controller.phase == TimerPhaseRestComplete && !controller.historyStore.activeSessionStartDate,
                @"the visual transition must wait for a choice instead of starting study automatically");
        [window close];
        CleanUpDisplaySleepTest(controller);
    }
}

static void FinishTestDisplaySleepPreparation(TestBreakTimerController *controller) {
    controller.restDisplaySleepQuietStartedAt = BreakTimerContinuousTime() - 1.01;
    [controller restDisplaySleepTick];
}

static void TestRestDisplaySleepWaitsForInputAndQuiet(void) {
    TestDisplayPowerController *power = nil;
    TestBreakTimerController *controller = RestDisplaySleepController(90, &power);
    TestDisplaySleepInputStateProvider *input = (id)controller.displaySleepInputStateProvider;
    [controller requestRestDisplaySleep];
    NSUUID *token = controller.restDisplaySleepToken;
    Require(power.sleepRequests == 0 && !power.activityActive && ![controller canPresentBreakWindows],
            @"preparation must suppress window activation without issuing sleep or power assertions");
    for (NSInteger heldInput = 0; heldInput < 3; heldInput++) {
        input.snapshot = (DisplaySleepInputSnapshot){YES, 10};
        FinishTestDisplaySleepPreparation(controller);
        Require(power.sleepRequests == 0 && controller.restDisplaySleepStage == RestDisplaySleepStagePreparing,
                @"held mouse, shortcut key, or modifiers must keep the request in preparation");
        input.snapshot = (DisplaySleepInputSnapshot){NO, 0.1};
        FinishTestDisplaySleepPreparation(controller);
        Require(power.sleepRequests == 0, @"release, mouse movement, and scroll must restart the quiet interval");
    }
    input.snapshot = (DisplaySleepInputSnapshot){NO, 10};
    controller.restDisplaySleepQuietStartedAt = BreakTimerContinuousTime() - 0.5;
    [controller restDisplaySleepTick];
    Require(power.sleepRequests == 0, @"a partial quiet second must not be sufficient");
    [controller requestRestDisplaySleep];
    Require(controller.restDisplaySleepToken == token, @"repeat shortcuts must preserve the pending request");
    FinishTestDisplaySleepPreparation(controller);
    Require(power.sleepRequests == 1 && power.activityActive &&
            controller.restDisplaySleepStage == RestDisplaySleepStageAwaitingConfirmation &&
            controller.restDisplaySleepConfirmationDeadline - BreakTimerContinuousTime() > 4.9,
            @"one quiet second should issue exactly one sleep and start a fresh five-second confirmation period");
    [controller restDisplaySleepTick];
    Require(power.sleepRequests == 1 && ![controller canPresentBreakWindows],
            @"the confirmation stage must neither activate windows nor issue duplicate requests");
    CleanUpDisplaySleepTest(controller);
}

static void TestRestDisplaySleepPreparationCancellation(void) {
    for (NSInteger interruption = 0; interruption < 5; interruption++) {
        TestDisplayPowerController *power = nil;
        TestBreakTimerController *controller = RestDisplaySleepController(90, &power);
        [controller requestRestDisplaySleep];
        NSTimer *oldTimer = controller.restDisplaySleepTimer;
        if (interruption == 0) {
            controller.restDisplaySleepPreparationDeadline = BreakTimerContinuousTime() - 1;
            [controller restDisplaySleepTick];
            Require(controller.phase == TimerPhaseResting && controller.restDisplayPowerMessage.length > 0,
                    @"preparation timeout should restore ordinary rest and permit retry");
        } else if (interruption == 1) {
            controller.phaseEndsAtContinuousTime = BreakTimerContinuousTime() - 1;
            [controller tick:nil];
            Require(controller.phase == TimerPhaseRestComplete && !controller.restObligationActive,
                    @"rest expiring during preparation must show the decision without turning the screen off");
        } else if (interruption == 2) {
            [controller systemWillSleep:nil];
        } else if (interruption == 3) {
            [controller stopForScheduledMeetingAtDate:NSDate.date];
        } else {
            [controller snoozeRestCycle];
        }
        [oldTimer fire];
        [controller restDisplaySleepTick];
        Require(!controller.restDisplaySleepToken && !oldTimer.isValid &&
                power.sleepRequests == 0 && power.wakeRequests == 0 && !power.activityActive,
                @"cancellation and stale timers during preparation must never issue a later display command");
        CleanUpDisplaySleepTest(controller);
    }
}

static void TestRestDisplaySleepWorkspaceNotificationFallback(void) {
    TestDisplayPowerController *power = nil;
    TestBreakTimerController *controller = RestDisplaySleepController(90, &power);
    [controller requestRestDisplaySleep];
    FinishTestDisplaySleepPreparation(controller);
    [controller screensDidSleep:nil];
    Require(controller.restDisplaySleepConfirmed && controller.isAsleep &&
            [controller allOnlineDisplaysAreAsleep] && ![controller anyOnlineDisplayIsAwake],
            @"a system screens-sleep notification must override stale awake display queries");
    controller.phaseEndsAtContinuousTime = BreakTimerContinuousTime() - 1;
    [controller restDisplaySleepTick];
    Require(power.wakeRequests == 1 && controller.waitingForRestCompletionDisplayWake,
            @"a notification-confirmed sleep must keep its automatic wake task until rest ends");
    [controller screensDidWake:nil];
    [controller resumeAfterEligibleInactivityIfPossible];
    Require(controller.phase == TimerPhaseRestComplete && !controller.waitingForRestCompletionDisplayWake &&
            controller.testLastShownMode == CountdownScreenModeDecision,
            @"a system screens-wake notification must restore the rest decision screen");
    CleanUpDisplaySleepTest(controller);
}

static void TestRestDisplaySleepEntryAndEarlyWake(void) {
    TestDisplayPowerController *power = nil;
    TestBreakTimerController *controller = RestDisplaySleepController(120, &power);
    controller.hasSnoozedCurrentCycle = YES;
    CountdownView *view = [[CountdownView alloc] initWithFrame:NSMakeRect(0, 0, 1280, 720)];
    [controller countdownViewDidRequestDisplaySleep:view];
    Require(power.sleepRequests == 0, @"the entry must prepare before sending the system command");
    FinishTestDisplaySleepPreparation(controller);
    Require(power.sleepRequests == 1 && power.activityActive,
            @"the rest button should request display sleep and keep the timer runnable");
    Require(power.requestedDuration > 119 && power.requestedDuration <= 120,
            @"automatic wake must use the current remaining time, not a new five-minute rest");
    [controller requestRestDisplaySleep];
    Require(power.sleepRequests == 1, @"duplicate requests must not create another display-sleep operation");
    [controller restDisplaySleepTick];
    Require(!controller.isAsleep, @"an awake external display must not be treated as screen-off rest");

    ConfirmTestDisplaysAsleep(controller);
    Require(controller.timer == nil && controller.restDisplaySleepTimer.isValid,
            @"the independent wake timer must survive the ordinary timer being stopped");
    void (^lateCompletion)(NSError *) = power.completion;
    controller.phaseEndsAtContinuousTime = BreakTimerContinuousTime() + 80;
    controller.testAllDisplaysAsleep = NO;
    controller.testAnyDisplayAwake = YES;
    [controller restDisplaySleepTick];
    Require(controller.phase == TimerPhaseResting && controller.restObligationActive && !controller.isAsleep,
            @"an early wake must return to the same unfinished rest");
    Require([controller currentPhaseRemaining] > 79 && [controller currentPhaseRemaining] <= 80,
            @"early wake must show the actual remaining duration");
    Require(!controller.restDisplaySleepToken && !power.activityActive && power.activityEnds == 1 && power.wakeRequests == 0,
            @"early wake must cancel the scheduled wake and release power resources");
    Require(controller.hasSnoozedCurrentCycle && !controller.historyStore.activeSessionStartDate,
            @"screen-off rest must preserve snooze usage and must not record learning time");
    Require([controller.emergencySkipQuotaStore usageAtDate:NSDate.date].dailyCount == 0,
            @"display sleep must not consume an emergency skip");
    lateCompletion([NSError errorWithDomain:@"late" code:1 userInfo:nil]);
    Require(controller.restDisplayPowerMessage == nil && controller.phase == TimerPhaseResting,
            @"a cancelled request's completion must not mutate the resumed rest");
    CleanUpDisplaySleepTest(controller);
}

static void TestRestDisplaySleepCompletionAndWakeFailure(void) {
    for (NSNumber *fails in @[@NO, @YES]) {
        TestDisplayPowerController *power = nil;
        TestBreakTimerController *controller = RestDisplaySleepController(60, &power);
        power.failWake = fails.boolValue;
        [controller requestRestDisplaySleep];
        FinishTestDisplaySleepPreparation(controller);
        ConfirmTestDisplaysAsleep(controller);
        controller.phaseEndsAtContinuousTime = BreakTimerContinuousTime() - 0.1;
        [controller restDisplaySleepTick];
        Require(controller.phase == TimerPhaseRestComplete && !controller.restObligationActive &&
                controller.waitingForRestCompletionDisplayWake,
                @"rest completion must wait for a decision even when the wake request fails");
        Require(power.wakeRequests == 1 && !power.activityActive && controller.restDisplaySleepTimer == nil,
                @"completion must request a single display wake and release its timer and activity");
        Require(![controller.restObligationStore snapshotWithDefaultDuration:300].pending &&
                !controller.historyStore.activeSessionStartDate,
                @"completed screen-off rest must clear the stored obligation without starting learning");
        NSInteger shownBeforeWake = controller.testShownCount;
        controller.testAllDisplaysAsleep = NO;
        controller.testAnyDisplayAwake = YES;
        [controller resumeAfterEligibleInactivityIfPossible];
        [controller resumeAfterEligibleInactivityIfPossible];
        Require(controller.phase == TimerPhaseRestComplete &&
                controller.testLastShownMode == CountdownScreenModeDecision &&
                controller.testShownCount == shownBeforeWake + 1,
                @"real or manual display wake must show the decision screen exactly once");
        if (fails.boolValue) {
            Require(controller.restDisplayPowerMessage.length > 0,
                    @"a failed automatic wake should leave a useful diagnostic");
            [controller stopStudy];
            Require(controller.phase == TimerPhaseStopped, @"stop learning must keep the controller running");
        } else {
            [controller startWorkCycleFromUserAction];
            Require(controller.phase == TimerPhaseWorking && controller.historyStore.activeSessionStartDate,
                    @"learning should only restart after the user chooses to continue");
        }
        CleanUpDisplaySleepTest(controller);
    }
}

static void TestRestDisplaySleepFailuresAndStaleCallbacks(void) {
    TestDisplayPowerController *power = nil;
    TestBreakTimerController *controller = RestDisplaySleepController(90, &power);
    power.failActivity = YES;
    [controller requestRestDisplaySleep];
    FinishTestDisplaySleepPreparation(controller);
    Require(power.sleepRequests == 0 && controller.restObligationActive && !controller.restDisplaySleepToken,
            @"activity creation failure must not issue display sleep or end rest");
    power.failActivity = NO;
    [controller requestRestDisplaySleep];
    FinishTestDisplaySleepPreparation(controller);
    void (^firstCompletion)(NSError *) = power.completion;
    firstCompletion([NSError errorWithDomain:@"test" code:1 userInfo:nil]);
    Require(controller.phase == TimerPhaseResting && controller.restObligationActive &&
            controller.restDisplayPowerMessage.length > 0 && !power.activityActive,
            @"command failure must keep the rest running and report the failure");

    [controller requestRestDisplaySleep];
    FinishTestDisplaySleepPreparation(controller);
    NSUUID *secondToken = controller.restDisplaySleepToken;
    firstCompletion(nil);
    Require(controller.restDisplaySleepToken == secondToken && power.activityActive,
            @"an obsolete callback must not complete or cancel a newer request");
    controller.restDisplaySleepConfirmationDeadline = BreakTimerContinuousTime() - 1;
    [controller restDisplaySleepTick];
    Require(!controller.restDisplaySleepToken && !controller.isAsleep && controller.restObligationActive &&
            !power.activityActive && power.wakeRequests == 0,
            @"five-second confirmation timeout must not grant sleep credit or wake displays");
    CleanUpDisplaySleepTest(controller);
}

static void TestRestDisplaySleepInterruptionsAndPhaseGating(void) {
    for (NSNumber *meeting in @[@NO, @YES]) {
        TestDisplayPowerController *power = nil;
        TestBreakTimerController *controller = RestDisplaySleepController(90, &power);
        [controller requestRestDisplaySleep];
        FinishTestDisplaySleepPreparation(controller);
        ConfirmTestDisplaysAsleep(controller);
        void (^lateCompletion)(NSError *) = power.completion;
        if (meeting.boolValue) {
            [controller stopForScheduledMeetingAtDate:NSDate.date];
            Require(controller.phase == TimerPhaseStopped && !controller.restObligationActive,
                    @"meeting stop must take precedence over automatic display wake");
        } else {
            [controller systemWillSleep:nil];
            Require(controller.systemSleeping && controller.restObligationActive,
                    @"system sleep must retain the unfinished rest for the ordinary wake policy");
        }
        controller.phaseEndsAtContinuousTime = BreakTimerContinuousTime() - 1;
        lateCompletion(nil);
        [controller restDisplaySleepTick];
        Require(!controller.restDisplaySleepToken && !power.activityActive && power.wakeRequests == 0,
                @"interruption and late callbacks must not trigger a display wake");
        CleanUpDisplaySleepTest(controller);
    }

    TestDisplayPowerController *power = nil;
    TestBreakTimerController *controller = RestDisplaySleepController(90, &power);
    for (NSNumber *phase in @[@(TimerPhaseWorking), @(TimerPhaseSnoozingRest), @(TimerPhaseStopped), @(TimerPhaseRestComplete)]) {
        controller.phase = phase.integerValue;
        [controller requestRestDisplaySleep];
    }
    Require(power.sleepRequests == 0, @"only an active rest may issue display sleep");
    controller.phase = TimerPhaseResting;
    controller.phaseEndsAtContinuousTime = BreakTimerContinuousTime() - 1;
    [controller requestRestDisplaySleep];
    Require(power.sleepRequests == 0 && controller.phase == TimerPhaseRestComplete,
            @"a shortcut at the deadline must complete rest instead of turning the screen off");
    CleanUpDisplaySleepTest(controller);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        TestPendingRestBlocksEveryStudyEntry();
        TestWorkCanStartAfterObligationResolution();
        TestDisplayInactivityRequiresEveryDisplayAndCreditsRest();
        TestMenuRaceAtWorkDeadlineStartsRestFirst();
        TestMeetingScheduleStopsOnceAndSupportsEarlyResume();
        TestMeetingScheduleAutoResumeAndManualStopRules();
        TestMeetingMidWindowCatchUpPersistsWithoutRetrigger();
        TestMeetingScheduleInterruptsRestWithoutUsingSkipQuota();
        TestAlreadyStoppedMeetingDoesNotAutoResume();
        TestMeetingEndDoesNotInterruptUserStartedRest();
        TestDisabledMeetingScheduleDoesNothing();
        TestUpdatedMeetingScheduleAndLegacyResume();
        TestEmergencySkipQuotaControlsCompletion();
        TestMeetingScheduleStopsSnoozeAndRestDecisionStates();
        TestSettingsPersistMeetingScheduleSwitch();
        TestRestDurationSettingsAndCycleBoundaries();
        TestRestDurationValidation();
        TestStatusItemUsesIndependentVisibilityIdentity();
        TestLegacyPreferencesMigrationPreservesTimerState();
        TestRestCompletionKeepsExistingView();
        TestRestDisplaySleepWaitsForInputAndQuiet();
        TestRestDisplaySleepPreparationCancellation();
        TestRestDisplaySleepWorkspaceNotificationFallback();
        TestRestDisplaySleepEntryAndEarlyWake();
        TestRestDisplaySleepCompletionAndWakeFailure();
        TestRestDisplaySleepFailuresAndStaleCallbacks();
        TestRestDisplaySleepInterruptionsAndPhaseGating();
        NSLog(@"BreakTimerController tests passed");
    }
    return 0;
}
