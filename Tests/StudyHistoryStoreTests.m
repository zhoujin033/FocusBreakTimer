#import <Foundation/Foundation.h>
#import "StudyHistoryStore.h"

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static NSTimeInterval TotalDuration(NSArray<StudySessionRecord *> *sessions) {
    NSTimeInterval total = 0;
    for (StudySessionRecord *session in sessions) {
        total += session.duration;
    }
    return total;
}

static NSURL *TemporaryHistoryURL(NSString *name) {
    NSURL *folder = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"FocusBreakTimerTests-%@-%@", name, NSUUID.UUID.UUIDString]
                     isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folder
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:nil];
    return [folder URLByAppendingPathComponent:@"study-history.json"];
}

static void RemoveTestFolder(NSURL *historyURL) {
    [NSFileManager.defaultManager removeItemAtURL:historyURL.URLByDeletingLastPathComponent error:nil];
}

static void TestSessionLifecycle(void) {
    NSURL *url = TemporaryHistoryURL(@"lifecycle");
    StudyHistoryStore *store = [[StudyHistoryStore alloc] initWithStorageURL:url];
    NSDate *base = [NSDate dateWithTimeIntervalSince1970:1000];
    [store beginSessionAtDate:base];
    [store endActiveSessionAtDate:[base dateByAddingTimeInterval:600]];

    NSArray<StudySessionRecord *> *sessions = [store sessionsIntersectingStartDate:[NSDate dateWithTimeIntervalSince1970:0]
                                                                            endDate:[NSDate dateWithTimeIntervalSince1970:5000]
                                                                               now:[NSDate dateWithTimeIntervalSince1970:5000]];
    Require(sessions.count == 1, @"completed session should be stored");
    Require(fabs(TotalDuration(sessions) - 600) < 0.01, @"completed duration should be exact");

    [store beginSessionAtDate:[NSDate dateWithTimeIntervalSince1970:2000]];
    [store beginSessionAtDate:[NSDate dateWithTimeIntervalSince1970:2300]];
    sessions = [store sessionsIntersectingStartDate:[NSDate dateWithTimeIntervalSince1970:0]
                                            endDate:[NSDate dateWithTimeIntervalSince1970:5000]
                                               now:[NSDate dateWithTimeIntervalSince1970:2400]];
    Require(sessions.count == 3, @"restart should close the old session and expose the active session");
    Require(fabs(TotalDuration(sessions) - 1000) < 0.01, @"restart should not lose partial study time");
    RemoveTestFolder(url);
}

static void TestBoundaryClipping(void) {
    NSURL *url = TemporaryHistoryURL(@"boundaries");
    StudyHistoryStore *store = [[StudyHistoryStore alloc] initWithStorageURL:url];
    NSDate *start = [NSDate dateWithTimeIntervalSince1970:86000];
    [store beginSessionAtDate:start];
    [store endActiveSessionAtDate:[NSDate dateWithTimeIntervalSince1970:86600]];

    NSArray<StudySessionRecord *> *firstDay = [store sessionsIntersectingStartDate:[NSDate dateWithTimeIntervalSince1970:0]
                                                                            endDate:[NSDate dateWithTimeIntervalSince1970:86400]
                                                                               now:[NSDate dateWithTimeIntervalSince1970:90000]];
    NSArray<StudySessionRecord *> *secondDay = [store sessionsIntersectingStartDate:[NSDate dateWithTimeIntervalSince1970:86400]
                                                                             endDate:[NSDate dateWithTimeIntervalSince1970:172800]
                                                                                now:[NSDate dateWithTimeIntervalSince1970:90000]];
    Require(fabs(TotalDuration(firstDay) - 400) < 0.01, @"session should be clipped at the first boundary");
    Require(fabs(TotalDuration(secondDay) - 200) < 0.01, @"session should continue after the boundary");
    RemoveTestFolder(url);
}

static void TestInterruptedRecovery(void) {
    NSURL *url = TemporaryHistoryURL(@"recovery");
    StudyHistoryStore *writer = [[StudyHistoryStore alloc] initWithStorageURL:url];
    NSDate *start = [NSDate dateWithTimeIntervalSince1970:1000];
    [writer beginSessionAtDate:start];
    [writer updateHeartbeatAtDate:[NSDate dateWithTimeIntervalSince1970:1040]];

    StudyHistoryStore *reader = [[StudyHistoryStore alloc] initWithStorageURL:url];
    [reader recoverInterruptedSessionAtDate:[NSDate dateWithTimeIntervalSince1970:2000]];
    NSArray<StudySessionRecord *> *sessions = [reader sessionsIntersectingStartDate:[NSDate dateWithTimeIntervalSince1970:0]
                                                                             endDate:[NSDate dateWithTimeIntervalSince1970:3000]
                                                                                now:[NSDate dateWithTimeIntervalSince1970:3000]];
    Require(sessions.count == 1, @"interrupted active session should be recovered");
    Require(fabs(TotalDuration(sessions) - 40) < 0.01, @"recovery should stop at the final persisted heartbeat");
    Require(reader.activeSessionStartDate == nil, @"recovery should clear stale active state");
    RemoveTestFolder(url);
}

static void TestClearAndRestart(void) {
    NSURL *url = TemporaryHistoryURL(@"clear");
    StudyHistoryStore *store = [[StudyHistoryStore alloc] initWithStorageURL:url];
    [store beginSessionAtDate:[NSDate dateWithTimeIntervalSince1970:1000]];
    [store endActiveSessionAtDate:[NSDate dateWithTimeIntervalSince1970:1600]];
    [store beginSessionAtDate:[NSDate dateWithTimeIntervalSince1970:2000]];
    [store clearAllHistoryAtDate:[NSDate dateWithTimeIntervalSince1970:2100] restartSession:YES];

    NSArray<StudySessionRecord *> *sessions = [store sessionsIntersectingStartDate:[NSDate dateWithTimeIntervalSince1970:0]
                                                                            endDate:[NSDate dateWithTimeIntervalSince1970:5000]
                                                                               now:[NSDate dateWithTimeIntervalSince1970:2160]];
    Require(sessions.count == 1 && sessions.firstObject.isActive, @"clear while studying should start a fresh active session");
    Require(fabs(TotalDuration(sessions) - 60) < 0.01, @"time before clear should be discarded");

    [store clearAllHistoryAtDate:[NSDate dateWithTimeIntervalSince1970:2200] restartSession:NO];
    sessions = [store sessionsIntersectingStartDate:[NSDate dateWithTimeIntervalSince1970:0]
                                            endDate:[NSDate dateWithTimeIntervalSince1970:5000]
                                               now:[NSDate dateWithTimeIntervalSince1970:2300]];
    Require(sessions.count == 0, @"clear while stopped should leave history empty");
    Require(store.earliestSessionDate == nil, @"empty history should not expose an earliest date");
    RemoveTestFolder(url);
}

static void TestCorruptHistoryBackup(void) {
    NSURL *url = TemporaryHistoryURL(@"corrupt");
    NSData *invalidData = [@"not-json" dataUsingEncoding:NSUTF8StringEncoding];
    [invalidData writeToURL:url atomically:YES];
    __unused StudyHistoryStore *store = [[StudyHistoryStore alloc] initWithStorageURL:url];
    Require(![NSFileManager.defaultManager fileExistsAtPath:url.path], @"corrupt source should be moved aside");
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:url.URLByDeletingLastPathComponent
                                                          includingPropertiesForKeys:nil
                                                                             options:0
                                                                               error:nil];
    NSPredicate *backupPredicate = [NSPredicate predicateWithBlock:^BOOL(NSURL *candidate, NSDictionary *bindings) {
        return [candidate.lastPathComponent hasPrefix:@"study-history.corrupt-"];
    }];
    Require([[files filteredArrayUsingPredicate:backupPredicate] count] == 1, @"corrupt history should have one backup");
    RemoveTestFolder(url);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        TestSessionLifecycle();
        TestBoundaryClipping();
        TestInterruptedRecovery();
        TestClearAndRestart();
        TestCorruptHistoryBackup();
        NSLog(@"StudyHistoryStore tests passed");
    }
    return 0;
}
