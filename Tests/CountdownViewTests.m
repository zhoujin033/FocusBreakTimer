#import <Cocoa/Cocoa.h>
#define FOCUS_BREAK_TIMER_DISABLE_APP_MAIN 1
#import "../Sources/main.m"

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

@interface TestDisplaySleepDelegate : NSObject <CountdownViewDelegate>
@property (nonatomic) NSInteger displaySleepRequests;
@property (nonatomic) NSInteger snoozeRequests;
@property (nonatomic) NSInteger continueStudyRequests;
@property (nonatomic) NSInteger stopStudyRequests;
@end

@implementation TestDisplaySleepDelegate
- (void)countdownViewDidRequestDisplaySleep:(CountdownView *)view { self.displaySleepRequests++; }
- (void)countdownViewDidBeginEmergencySkipHold:(CountdownView *)view {}
- (void)countdownViewDidCancelEmergencySkipHold:(CountdownView *)view {}
- (void)countdownViewDidRequestSnoozeRest:(CountdownView *)view { self.snoozeRequests++; }
- (void)countdownViewDidRequestContinueStudy:(CountdownView *)view { self.continueStudyRequests++; }
- (void)countdownViewDidRequestStopStudy:(CountdownView *)view { self.stopStudyRequests++; }
@end

static NSEvent *DisplaySleepKeyEvent(NSEventModifierFlags modifiers, BOOL repeat) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:modifiers
                          timestamp:0 windowNumber:0 context:nil characters:@"D"
         charactersIgnoringModifiers:@"d" isARepeat:repeat keyCode:2];
}

static void TestDisplaySleepButtonAndShortcut(void) {
    CountdownView *view = [[CountdownView alloc] initWithFrame:NSMakeRect(0, 0, 1280, 720)];
    TestDisplaySleepDelegate *delegate = [[TestDisplaySleepDelegate alloc] init];
    view.delegate = delegate;
    NSEventModifierFlags shortcut = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    Require([view handleDisplaySleepShortcut:DisplaySleepKeyEvent(shortcut, NO)] && delegate.displaySleepRequests == 1,
            @"the rest shortcut should request display sleep");
    [view handleDisplaySleepShortcut:DisplaySleepKeyEvent(shortcut, YES)];
    Require(delegate.displaySleepRequests == 1, @"holding the shortcut must not trigger repeatedly");
    view.displaySleepPending = YES;
    [view handleDisplaySleepShortcut:DisplaySleepKeyEvent(shortcut, NO)];
    Require(delegate.displaySleepRequests == 1, @"pending display sleep must suppress repeated requests");
    view.displaySleepPending = NO;
    Require(![view handleDisplaySleepShortcut:DisplaySleepKeyEvent(NSEventModifierFlagCommand, NO)],
            @"a different modifier combination must remain unhandled");

    NSRect button = view.displaySleepButtonRect;
    NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                      location:NSMakePoint(NSMidX(button), NSMidY(button))
                                 modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1];
    [view mouseDown:click];
    Require(delegate.displaySleepRequests == 1, @"mouse-down must not turn the display off while the button is held");
    NSEvent *release = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
                                        location:click.locationInWindow modifierFlags:0 timestamp:0
                                    windowNumber:0 context:nil eventNumber:1 clickCount:1 pressure:0];
    [view mouseUp:release];
    Require(delegate.displaySleepRequests == 2, @"the button must use the same display-sleep request as the shortcut");
    [view mouseDown:click];
    NSEvent *dragOutside = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged
                                            location:NSZeroPoint modifierFlags:0 timestamp:0
                                        windowNumber:0 context:nil eventNumber:2 clickCount:1 pressure:1];
    [view mouseDragged:dragOutside];
    [view mouseUp:release];
    Require(delegate.displaySleepRequests == 2, @"dragging outside must cancel the click even if released back inside");
    [view mouseUp:release];
    Require(delegate.displaySleepRequests == 2, @"release without a matching press must not request sleep");
    [view mouseDown:click];
    view.mode = CountdownScreenModeDecision;
    [view mouseUp:release];
    Require(delegate.displaySleepRequests == 2, @"a mode change must cancel an armed sleep button");
    view.mode = CountdownScreenModeResting;
    view.snoozeAvailable = NO;
    Require(!NSIsEmptyRect(view.displaySleepButtonRect), @"display sleep must remain after snooze is used");
    view.mode = CountdownScreenModeDecision;
    Require(NSIsEmptyRect(view.displaySleepButtonRect) &&
            ![view handleDisplaySleepShortcut:DisplaySleepKeyEvent(shortcut, NO)],
            @"the decision screen must not expose display sleep or its shortcut");
    Require(delegate.displaySleepRequests == 2, @"decision mode must not trigger display sleep");
}

static void TestHitRegionsFollowGeometryBeforeDrawing(void) {
    CountdownView *view = [[CountdownView alloc] initWithFrame:NSMakeRect(0, 0, 960, 540)];
    Require(NSContainsRect(view.bounds, view.emergencySkipButtonRect), @"skip must be on screen before drawing");
    Require(!NSIntersectsRect(view.emergencySkipButtonRect, view.snoozeRestButtonRect),
            @"compact display buttons must not overlap");
    Require(NSContainsRect(view.bounds, view.displaySleepButtonRect) &&
            !NSIntersectsRect(view.displaySleepButtonRect, view.snoozeRestButtonRect) &&
            !NSIntersectsRect(view.displaySleepButtonRect, view.emergencySkipButtonRect),
            @"display sleep must fit compact displays without overlapping other actions");
    NSRect smallButton = view.emergencySkipButtonRect;
    [view setFrameSize:NSMakeSize(1280, 720)];
    NSRect largeButton = view.emergencySkipButtonRect;
    Require(fabs(NSWidth(smallButton) / NSWidth(largeButton) - 0.75) < 0.00001,
            @"hit regions must resize without waiting for a paint");

    [view setBoundsOrigin:NSMakePoint(13, 27)];
    Require(NSEqualRects(view.emergencySkipButtonRect, NSOffsetRect(largeButton, 13, 27)),
            @"drawing and hit testing must use the same bounds origin");
    view.snoozeAvailable = NO;
    Require(NSIsEmptyRect(view.snoozeRestButtonRect), @"hidden snooze must not remain clickable");
    view.mode = CountdownScreenModeDecision;
    Require(NSIsEmptyRect(view.emergencySkipButtonRect), @"decision mode must remove the skip hit region");
    Require(NSContainsRect(view.bounds, view.continueStudyButtonRect) &&
            NSContainsRect(view.bounds, view.stopStudyButtonRect) &&
            !NSIntersectsRect(view.continueStudyButtonRect, view.stopStudyButtonRect),
            @"decision actions must remain visible and separate");
}

static NSBitmapImageRep *RenderView(CountdownView *view, CGFloat backingScale) {
    NSSize size = view.bounds.size;
    NSInteger width = (NSInteger)llround(size.width * backingScale);
    NSInteger height = (NSInteger)llround(size.height * backingScale);
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    Require(bitmap != nil, @"bitmap allocation must succeed");
    bitmap.size = size;
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    Require(context != nil, @"bitmap graphics context must be available");

    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = context;
    // Explicitly establish points-to-pixels, independently of bitmap metadata.
    CGAffineTransform initial = CGContextGetCTM(context.CGContext);
    CGContextScaleCTM(context.CGContext, backingScale / initial.a, backingScale / initial.d);
    CGAffineTransform before = CGContextGetCTM(context.CGContext);
    [view drawRect:view.bounds];
    Require(CGAffineTransformEqualToTransform(before, CGContextGetCTM(context.CGContext)),
            @"drawing a compact screen must not leak its transform to the next view");
    [NSGraphicsContext restoreGraphicsState];
    return bitmap;
}

static void TestDrawingAtScale(NSSize size, CGFloat backingScale) {
    CountdownView *view = [[CountdownView alloc] initWithFrame:(NSRect){NSZeroPoint, size}];
    view.restEndsAt = [NSDate dateWithTimeIntervalSince1970:1800000000];
    view.progress = 1.0;
    NSBitmapImageRep *bitmap = RenderView(view, backingScale);
    view.progress = 0.0;
    NSBitmapImageRep *emptyRing = RenderView(view, backingScale);
    NSInteger width = bitmap.pixelsWide, height = bitmap.pixelsHigh;

    // Compare full/empty native renderings so geometry checks do not depend on
    // the chosen accent hue or accidentally include labels and button borders.
    NSInteger minX = width, minY = height, maxX = -1, maxY = -1;
    for (NSInteger y = 0; y < height; y++) {
        unsigned char *row = bitmap.bitmapData + y * bitmap.bytesPerRow;
        unsigned char *emptyRow = emptyRing.bitmapData + y * emptyRing.bytesPerRow;
        for (NSInteger x = 0; x < width; x++) {
            unsigned char *pixel = row + x * 4;
            unsigned char *emptyPixel = emptyRow + x * 4;
            NSInteger difference = labs((long)pixel[0] - emptyPixel[0]) +
                labs((long)pixel[1] - emptyPixel[1]) + labs((long)pixel[2] - emptyPixel[2]);
            if (difference > 48) {
                minX = MIN(minX, x); minY = MIN(minY, y);
                maxX = MAX(maxX, x); maxY = MAX(maxY, y);
            }
        }
    }
    Require(maxX >= minX && maxY >= minY, @"full-progress ring must actually be drawn");
    CGFloat expectedDiameter = NSWidth([view progressRingRect]) * [view countdownLayout].scale * backingScale;
    Require(fabs((maxX - minX + 1) - expectedDiameter) <= 4 &&
            fabs((maxY - minY + 1) - expectedDiameter) <= 4,
            @"1x and 2x renderings must keep the expected circular ring size");
    Require(fabs((minX + maxX + 1) / 2.0 - width / 2.0) <= 2,
            @"rendered ring must be centered on its own display");
    CGFloat lineWidth = [view ringLineWidthForRect:[view progressRingRect]];
    Require(lineWidth >= 14.0 && lineWidth <= 26.0,
            @"the timer must restore the original 3.7.3 ring weight");
    NSColor *corner = [[bitmap colorAtX:0 y:0] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
    CGFloat scale = [view countdownLayout].scale * backingScale;
    NSRect ring = [view progressRingRect];
    NSColor *inside = [[bitmap colorAtX:(NSInteger)(NSMidX(ring) * scale)
                                   y:(NSInteger)(height - (NSMidY(ring) + NSHeight(ring) * 0.35) * scale)]
        colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
    Require(corner.redComponent > 0.02 && corner.redComponent < 0.15 &&
            fabs(corner.redComponent - corner.greenComponent) < 0.005 &&
            fabs(corner.redComponent - corner.blueComponent) < 0.005 &&
            inside.redComponent > corner.redComponent && inside.redComponent - corner.redComponent < 0.05,
            @"the screen must restore the neutral charcoal background and subtle inner disk of 3.7.3");
}

static void TestSharedAppearanceAndActionRouting(void) {
    CountdownView *view = [[CountdownView alloc] initWithFrame:NSMakeRect(0, 0, 1280, 720)];
    TestDisplaySleepDelegate *delegate = [[TestDisplaySleepDelegate alloc] init];
    view.delegate = delegate;
    view.remainingSeconds = 1;
    view.progress = 0;
    NSRect left = view.snoozeRestButtonRect;
    NSRect right = view.displaySleepButtonRect;
    NSRect ring = [view progressRingRect];
    NSBitmapImageRep *rest = RenderView(view, 1);
    NSPoint points[] = {
        {NSMinX(left) + 12, NSMinY(left) + 12},
        {NSMinX(right) + 12, NSMinY(right) + 12}
    };
    for (NSNumber *early in @[@NO, @YES]) {
        view.mode = CountdownScreenModeDecision;
        view.remainingSeconds = 0;
        view.restEndedEarly = early.boolValue;
        NSBitmapImageRep *decision = RenderView(view, 1);
        Require(NSEqualRects(left, view.continueStudyButtonRect) && NSEqualRects(right, view.stopStudyButtonRect) &&
                NSEqualRects(ring, [view progressRingRect]), @"all frames must remain stable at natural or early rest completion");
        for (NSUInteger i = 0; i < 2; i++) {
            NSInteger x = (NSInteger)points[i].x;
            NSInteger y = rest.pixelsHigh - 1 - (NSInteger)points[i].y;
            NSColor *before = [[rest colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
            NSColor *after = [[decision colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
            if (i == 0) {
                Require(before.greenComponent > 0.2 && before.greenComponent < 0.5 &&
                        before.greenComponent > before.redComponent + 0.04,
                        @"the main action must restore the muted green fill of 3.7.3");
            } else {
                Require(before.redComponent > 0.07 && fabs(before.redComponent - before.greenComponent) < 0.005 &&
                        fabs(before.redComponent - before.blueComponent) < 0.005,
                        @"the secondary action must keep its neutral charcoal surface");
            }
            Require(fabs(before.redComponent - after.redComponent) < 0.001 &&
                    fabs(before.greenComponent - after.greenComponent) < 0.001 &&
                    fabs(before.blueComponent - after.blueComponent) < 0.001,
                    @"actual AppKit-rendered button fills must match across the two modes");
        }
    }
    NSPoint centers[] = {{NSMidX(left), NSMidY(left)}, {NSMidX(right), NSMidY(right)}};
    for (NSUInteger i = 0; i < 2; i++) {
        NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:centers[i]
            modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1];
        [view mouseDown:event];
    }
    Require(delegate.continueStudyRequests == 1 && delegate.stopStudyRequests == 1 && delegate.displaySleepRequests == 0,
            @"decision buttons must still send their own continue/stop actions at the shared positions");
    view.mode = CountdownScreenModeResting;
    NSEvent *leftClick = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:centers[0]
        modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1];
    [view mouseDown:leftClick];
    view.snoozeAvailable = NO;
    [view mouseDown:leftClick];
    Require(delegate.snoozeRequests == 1 && NSIsEmptyRect(view.snoozeRestButtonRect),
            @"the styled unavailable snooze button must remain non-interactive");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        TestHitRegionsFollowGeometryBeforeDrawing();
        TestDisplaySleepButtonAndShortcut();
        TestSharedAppearanceAndActionRouting();
        NSSize sizes[] = {{960, 540}, {1280, 720}, {1920, 1080}, {1080, 1920}};
        for (NSUInteger i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
            @autoreleasepool {
                TestDrawingAtScale(sizes[i], 1.0);
                TestDrawingAtScale(sizes[i], 2.0);
            }
        }
        NSLog(@"Countdown view tests passed (hit regions and 8 AppKit bitmap renderings)");
    }
    return 0;
}
