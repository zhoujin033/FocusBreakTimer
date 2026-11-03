#import <Cocoa/Cocoa.h>
#import "StudyHistoryStore.h"
#import "StudyStatisticsCalculator.h"
#import "StudyStatisticsWindowController.h"

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static NSInteger IndexForToday(StudyActivitySnapshot *snapshot, NSCalendar *calendar) {
    for (NSInteger index = 0; index < (NSInteger)snapshot.dates.count; index++) {
        if ([calendar isDateInToday:snapshot.dates[(NSUInteger)index]]) {
            return index;
        }
    }
    return -1;
}

static void TestHeatmapClickOpensDayDetail(void) {
    __unused NSApplication *application = NSApplication.sharedApplication;
    NSURL *historyURL = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"FocusBreakTimerStatisticsWindowTests-%@.json", NSUUID.UUID.UUIDString]];
    StudyHistoryStore *store = [[StudyHistoryStore alloc] initWithStorageURL:historyURL];
    NSDate *end = NSDate.date;
    [store beginSessionAtDate:[end dateByAddingTimeInterval:-25.0 * 60.0]];
    [store endActiveSessionAtDate:end];

    StudyStatisticsWindowController *controller = [[StudyStatisticsWindowController alloc] initWithHistoryStore:store];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [controller performSelector:NSSelectorFromString(@"buildWindowIfNeeded")];
#pragma clang diagnostic pop
    [controller refresh];

    NSView *heatmap = [controller valueForKey:@"heatmapView"];
    StudyActivitySnapshot *snapshot = [heatmap valueForKey:@"snapshot"];
    NSCalendar *calendar = [StudyStatisticsCalculator studyCalendar];
    NSInteger index = IndexForToday(snapshot, calendar);
    Require(index >= 0, @"today should have a heatmap cell");

    NSInteger week = index / 7;
    NSInteger weekday = index % 7;
    CGFloat gap = NSWidth(heatmap.bounds) >= 1080.0 ? 4.0 : 3.0;
    CGFloat availableWidth = MAX(0, NSWidth(heatmap.bounds) - 8.0);
    CGFloat cellSize = floor((availableWidth - gap * (snapshot.weekCount - 1)) / snapshot.weekCount);
    cellSize = MAX(8.0, MIN(20.0, cellSize));
    CGFloat gridWidth = cellSize * snapshot.weekCount + gap * (snapshot.weekCount - 1);
    CGFloat startX = floor((NSWidth(heatmap.bounds) - gridWidth) / 2.0);
    NSPoint localPoint = NSMakePoint(startX + week * (cellSize + gap) + cellSize / 2.0,
                                    58.0 + weekday * (cellSize + gap) + cellSize / 2.0);
    NSPoint windowPoint = [heatmap convertPoint:localPoint toView:nil];
    NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                         location:windowPoint
                                    modifierFlags:0
                                        timestamp:0
                                     windowNumber:controller.window.windowNumber
                                          context:nil
                                      eventNumber:1
                                       clickCount:1
                                         pressure:1.0];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [heatmap performSelector:NSSelectorFromString(@"mouseDown:") withObject:event];
#pragma clang diagnostic pop

    NSSegmentedControl *pageControl = [controller valueForKey:@"pageControl"];
    NSDate *selectedDate = [controller valueForKey:@"selectedDate"];
    NSView *metricsBand = [controller valueForKey:@"metricsBand"];
    NSView *tableScrollView = [controller valueForKey:@"tableScrollView"];
    Require(pageControl.selectedSegment == 1, @"clicking a heatmap cell should select the day page");
    Require([calendar isDate:selectedDate inSameDayAsDate:snapshot.dates[(NSUInteger)index]],
            @"day detail should use the clicked cell's actual date");
    Require(metricsBand.hidden, @"overview should no longer remain visible after a cell click");
    Require(!tableScrollView.hidden, @"day detail should become visible after a cell click");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        TestHeatmapClickOpensDayDetail();
        NSLog(@"StudyStatisticsWindowController tests passed");
    }
    return 0;
}
