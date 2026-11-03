#import <Foundation/Foundation.h>
#import "BreakTimerPolicy.h"

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static void TestRestObligationBlocksStudyActions(void) {
    BreakTimerActionPolicy resting = BreakTimerActionPolicyMake(TimerPhaseResting, YES);
    Require(!resting.canStartWork, @"active rest must block work restart");
    Require(!resting.canStopStudy, @"active rest must block stop-and-restart bypass");
    Require(!resting.canQuitApplication, @"active rest must block quitting as an instant bypass");
    Require(resting.restAction == BreakTimerRestActionUnavailable,
            @"starting rest again while resting must not reset snooze availability");

    BreakTimerActionPolicy snoozing = BreakTimerActionPolicyMake(TimerPhaseSnoozingRest, YES);
    Require(!snoozing.canStartWork, @"snoozed rest must block work restart");
    Require(!snoozing.canStopStudy, @"snoozed rest must block stop-and-restart bypass");
    Require(snoozing.restAction == BreakTimerRestActionStartSnoozedRestNow,
            @"snoozed rest should allow beginning the required rest immediately");
}

static void TestResolvedRestRestoresStudyActions(void) {
    BreakTimerActionPolicy complete = BreakTimerActionPolicyMake(TimerPhaseRestComplete, NO);
    Require(complete.canStartWork, @"completed rest should allow continuing study");
    Require(complete.canStopStudy, @"completed rest should allow stopping study");

    BreakTimerActionPolicy stopped = BreakTimerActionPolicyMake(TimerPhaseStopped, NO);
    Require(stopped.canStartWork, @"stopped state should allow starting study");
    Require(!stopped.canStopStudy, @"stopped state should not offer stop again");

    for (NSInteger phase = TimerPhaseWorking; phase <= TimerPhaseStopped; phase++) {
        BreakTimerActionPolicy locked = BreakTimerActionPolicyMake((TimerPhase)phase, YES);
        Require(!locked.canStartWork && !locked.canStopStudy && !locked.canQuitApplication,
                @"the rest obligation must override every phase and block study actions");
    }
}

static void TestInactiveRestCredit(void) {
    Require(fabs(BreakTimerRemainingRestAfterInactivity(300, 120) - 180) < 0.01,
            @"partial display sleep should leave the uncompleted rest duration");
    Require(BreakTimerRemainingRestAfterInactivity(300, 300) == 0,
            @"a full rest interval should satisfy the obligation");
    Require(BreakTimerRemainingRestAfterInactivity(300, 420) == 0,
            @"rest credit must never produce a negative duration");
    Require(BreakTimerRemainingRestAfterInactivity(300, -10) == 300,
            @"negative clock movement must not create rest credit");
}

static void TestMultiDisplaySleepPolicy(void) {
    Require(BreakTimerAllDisplayStatesAreAsleep(@[@YES, @YES]),
            @"two sleeping displays should count as screen-free rest");
    Require(!BreakTimerAllDisplayStatesAreAsleep(@[@YES, @NO]),
            @"an awake external display must prevent rest credit");
    Require(!BreakTimerAllDisplayStatesAreAsleep(@[]),
            @"an unavailable display query must not grant rest credit");
    Require(BreakTimerAnyDisplayStateIsAwake(@[@YES, @NO]),
            @"one awake display should allow the timer to resume");
    Require(!BreakTimerAnyDisplayStateIsAwake(@[@YES, @YES]),
            @"the timer must remain paused while every display sleeps");
}

static void TestContinuousClock(void) {
    NSTimeInterval before = BreakTimerContinuousTime();
    [NSThread sleepForTimeInterval:0.02];
    NSTimeInterval after = BreakTimerContinuousTime();
    Require(after > before, @"the continuous clock should advance independently of wall-clock dates");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        TestRestObligationBlocksStudyActions();
        TestResolvedRestRestoresStudyActions();
        TestInactiveRestCredit();
        TestMultiDisplaySleepPolicy();
        TestContinuousClock();
        NSLog(@"BreakTimerPolicy tests passed");
    }
    return 0;
}
