#import <Foundation/Foundation.h>
#import "RestObligationStore.h"

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *suiteName = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.tests.%@", NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
        [defaults removePersistentDomainForName:suiteName];

        RestObligationStore *store = [[RestObligationStore alloc] initWithUserDefaults:defaults];
        RestObligationSnapshot *empty = [store snapshotWithDefaultDuration:300];
        Require(!empty.pending, @"a new store should not require rest");

        [store saveRemainingDuration:175 totalDuration:300 snoozeUsed:YES synchronously:YES];
        RestObligationStore *reopenedStore = [[RestObligationStore alloc] initWithUserDefaults:
            [[NSUserDefaults alloc] initWithSuiteName:suiteName]];
        RestObligationSnapshot *restored = [reopenedStore snapshotWithDefaultDuration:300];
        Require(restored.pending, @"pending rest should survive a store recreation");
        Require(fabs(restored.remainingDuration - 175) < 0.01, @"remaining rest should be restored");
        Require(restored.snoozeUsed, @"used snooze allowance must remain unavailable after restart");
        Require(restored.totalDuration == 300, @"the original cycle length should survive a restart");

        [defaults setDouble:-20 forKey:@"pendingRestRemainingSeconds"];
        RestObligationSnapshot *repaired = [store snapshotWithDefaultDuration:300];
        Require(repaired.remainingDuration == 300, @"invalid persisted data should require a full rest");

        [store saveRemainingDuration:500 totalDuration:600 snoozeUsed:YES synchronously:YES];
        RestObligationSnapshot *custom = [store snapshotWithDefaultDuration:120];
        Require(custom.remainingDuration == 500 && custom.totalDuration == 600,
                @"a changed default must not shorten an unfinished custom rest");
        [defaults removeObjectForKey:@"pendingRestTotalSeconds"];
        [defaults setDouble:240 forKey:@"pendingRestRemainingSeconds"];
        RestObligationSnapshot *legacy = [store snapshotWithDefaultDuration:300];
        Require(legacy.remainingDuration == 240 && legacy.totalDuration == 300,
                @"legacy five-minute rest records should keep their original remaining time");

        [store clear];
        Require(![store snapshotWithDefaultDuration:300].pending, @"completed rest should clear persistence");
        Require([defaults objectForKey:@"pendingRestTotalSeconds"] == nil, @"completion must also clear the saved cycle length");
        [defaults removePersistentDomainForName:suiteName];
        NSLog(@"RestObligationStore tests passed");
    }
    return 0;
}
