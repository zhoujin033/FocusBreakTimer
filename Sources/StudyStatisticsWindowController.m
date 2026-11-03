#import "StudyStatisticsWindowController.h"
#import "StudyHistoryStore.h"
#import "StudyStatisticsCalculator.h"

typedef NS_ENUM(NSInteger, StudyStatisticsPage) {
    StudyStatisticsPageOverview,
    StudyStatisticsPageDay
};

static NSString *StudyDurationText(NSTimeInterval duration) {
    if (duration <= 0) {
        return @"0分钟";
    }
    NSInteger seconds = (NSInteger)floor(duration);
    if (seconds < 60) {
        return @"少于1分钟";
    }
    NSInteger minutes = seconds / 60;
    NSInteger hours = minutes / 60;
    NSInteger remainingMinutes = minutes % 60;
    if (hours == 0) {
        return [NSString stringWithFormat:@"%ld分钟", (long)minutes];
    }
    if (remainingMinutes == 0) {
        return [NSString stringWithFormat:@"%ld小时", (long)hours];
    }
    return [NSString stringWithFormat:@"%ld小时%ld分钟", (long)hours, (long)remainingMinutes];
}

static NSString *StudyMetricDurationText(NSTimeInterval duration) {
    if (duration <= 0) {
        return @"0分钟";
    }
    NSInteger seconds = (NSInteger)floor(duration);
    if (seconds < 60) {
        return @"少于1分钟";
    }
    NSInteger minutes = seconds / 60;
    NSInteger hours = minutes / 60;
    NSInteger remainingMinutes = minutes % 60;
    if (hours == 0) {
        return [NSString stringWithFormat:@"%ld分钟", (long)minutes];
    }
    if (remainingMinutes == 0) {
        return [NSString stringWithFormat:@"%ld小时", (long)hours];
    }
    return [NSString stringWithFormat:@"%ld小时%ld分", (long)hours, (long)remainingMinutes];
}

static BOOL StudyAppearanceIsDark(NSAppearance *appearance) {
    NSString *match = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    return [match isEqualToString:NSAppearanceNameDarkAqua];
}

static NSColor *StudyDynamicColor(NSColor *lightColor, NSColor *darkColor) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        return StudyAppearanceIsDark(appearance) ? darkColor : lightColor;
    }];
}

@interface StudyTextSegmentedControl : NSSegmentedControl
@end

@implementation StudyTextSegmentedControl

- (void)drawRect:(NSRect)dirtyRect {
    NSInteger segmentCount = self.segmentCount;
    if (segmentCount <= 0) {
        return;
    }
    CGFloat segmentWidth = NSWidth(self.bounds) / segmentCount;
    for (NSInteger index = 0; index < segmentCount; index++) {
        NSString *label = [self labelForSegment:index] ?: @"";
        BOOL selected = index == self.selectedSegment;
        NSDictionary *attributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:18.0 weight:selected ? NSFontWeightSemibold : NSFontWeightRegular],
            NSForegroundColorAttributeName: selected ? NSColor.labelColor : NSColor.tertiaryLabelColor
        };
        NSSize size = [label sizeWithAttributes:attributes];
        NSRect segmentRect = NSMakeRect(segmentWidth * index, 0, segmentWidth, NSHeight(self.bounds));
        [label drawAtPoint:NSMakePoint(NSMidX(segmentRect) - size.width / 2.0,
                                      NSMidY(segmentRect) - size.height / 2.0)
          withAttributes:attributes];
    }
}

@end

@interface StudyMetricsBandView : NSView
@property (nonatomic, copy) NSArray<NSTextField *> *valueLabels;
@property (nonatomic, copy) NSArray<NSTextField *> *titleLabels;
- (void)setMetricValues:(NSArray<NSString *> *)values titles:(NSArray<NSString *> *)titles;
- (void)layoutMetricLabels;
@end

@implementation StudyMetricsBandView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        NSMutableArray *valueLabels = [NSMutableArray arrayWithCapacity:5];
        NSMutableArray *titleLabels = [NSMutableArray arrayWithCapacity:5];
        for (NSInteger index = 0; index < 5; index++) {
            NSTextField *valueLabel = [NSTextField labelWithString:@"0 分钟"];
            valueLabel.alignment = NSTextAlignmentCenter;
            valueLabel.font = [NSFont monospacedDigitSystemFontOfSize:24.0 weight:NSFontWeightMedium];
            valueLabel.textColor = NSColor.labelColor;
            valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            [self addSubview:valueLabel];
            [valueLabels addObject:valueLabel];

            NSTextField *titleLabel = [NSTextField labelWithString:@""];
            titleLabel.alignment = NSTextAlignmentCenter;
            titleLabel.font = [NSFont systemFontOfSize:15.0 weight:NSFontWeightRegular];
            titleLabel.textColor = NSColor.secondaryLabelColor;
            titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            [self addSubview:titleLabel];
            [titleLabels addObject:titleLabel];
        }
        _valueLabels = valueLabels;
        _titleLabels = titleLabels;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setMetricValues:(NSArray<NSString *> *)values titles:(NSArray<NSString *> *)titles {
    for (NSInteger index = 0; index < 5; index++) {
        self.valueLabels[(NSUInteger)index].stringValue = index < (NSInteger)values.count ? values[(NSUInteger)index] : @"";
        self.titleLabels[(NSUInteger)index].stringValue = index < (NSInteger)titles.count ? titles[(NSUInteger)index] : @"";
    }
    [self setNeedsLayout:YES];
    [self layoutMetricLabels];
}

- (void)layout {
    [super layout];
    [self layoutMetricLabels];
}

- (void)layoutMetricLabels {
    CGFloat segmentWidth = NSWidth(self.bounds) / 5.0;
    for (NSInteger index = 0; index < 5; index++) {
        CGFloat segmentX = segmentWidth * index;
        CGFloat valueWidth = MAX(0, segmentWidth - 4.0);
        NSTextField *valueLabel = self.valueLabels[(NSUInteger)index];
        CGFloat fontSize = 24.0;
        while (fontSize > 17.0) {
            NSFont *font = [NSFont monospacedDigitSystemFontOfSize:fontSize weight:NSFontWeightMedium];
            if ([valueLabel.stringValue sizeWithAttributes:@{NSFontAttributeName: font}].width <= valueWidth - 8.0) {
                valueLabel.font = font;
                break;
            }
            fontSize -= 1.0;
        }
        if (fontSize <= 17.0) {
            valueLabel.font = [NSFont monospacedDigitSystemFontOfSize:17.0 weight:NSFontWeightMedium];
        }
        valueLabel.frame = NSMakeRect(segmentX + 2.0, 26.0, valueWidth, 32.0);
        self.titleLabels[(NSUInteger)index].frame = NSMakeRect(segmentX + 8.0, 67.0, MAX(0, segmentWidth - 16.0), 24.0);
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSRect borderRect = NSInsetRect(self.bounds, 0.5, 0.5);
    NSColor *background = StudyDynamicColor([NSColor colorWithCalibratedWhite:0.995 alpha:1.0],
                                            [NSColor colorWithCalibratedWhite:0.12 alpha:1.0]);
    [background setFill];
    NSBezierPath *backgroundPath = [NSBezierPath bezierPathWithRoundedRect:borderRect xRadius:24.0 yRadius:24.0];
    [backgroundPath fill];
    [NSColor.separatorColor setStroke];
    backgroundPath.lineWidth = 1.0;
    [backgroundPath stroke];

    CGFloat segmentWidth = NSWidth(self.bounds) / 5.0;
    for (NSInteger index = 1; index < 5; index++) {
        CGFloat x = floor(segmentWidth * index) + 0.5;
        NSBezierPath *separator = [NSBezierPath bezierPath];
        [separator moveToPoint:NSMakePoint(x, 24.0)];
        [separator lineToPoint:NSMakePoint(x, NSHeight(self.bounds) - 24.0)];
        separator.lineWidth = 1.0;
        [separator stroke];
    }
}

@end

@interface StudyBarChartView : NSView
@property (nonatomic, copy) NSArray<NSNumber *> *values;
@property (nonatomic, copy) NSArray<NSString *> *axisLabels;
@property (nonatomic, copy) NSArray<NSString *> *hoverTexts;
@property (nonatomic, copy) NSString *emptyText;
@property (nonatomic) NSTimeInterval fixedMaximum;
@property (nonatomic) NSInteger hoverIndex;
@end

@implementation StudyBarChartView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _values = @[];
        _axisLabels = @[];
        _hoverTexts = @[];
        _emptyText = @"暂无学习记录";
        _hoverIndex = -1;
    }
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas.copy) {
        [self removeTrackingArea:area];
    }
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                       options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                                         owner:self
                                                      userInfo:nil];
    [self addTrackingArea:area];
}

- (void)setValues:(NSArray<NSNumber *> *)values {
    _values = [values copy];
    self.hoverIndex = -1;
    self.needsDisplay = YES;
}

- (void)setAxisLabels:(NSArray<NSString *> *)axisLabels {
    _axisLabels = [axisLabels copy];
    self.needsDisplay = YES;
}

- (void)setHoverTexts:(NSArray<NSString *> *)hoverTexts {
    _hoverTexts = [hoverTexts copy];
    self.needsDisplay = YES;
}

- (void)setEmptyText:(NSString *)emptyText {
    _emptyText = [emptyText copy];
    self.needsDisplay = YES;
}

- (void)setFixedMaximum:(NSTimeInterval)fixedMaximum {
    _fixedMaximum = fixedMaximum;
    self.needsDisplay = YES;
}

- (NSRect)plotRect {
    return NSMakeRect(42.0, 24.0, MAX(0, NSWidth(self.bounds) - 54.0), MAX(0, NSHeight(self.bounds) - 36.0));
}

- (NSTimeInterval)chartMaximum {
    if (self.fixedMaximum > 0) {
        return self.fixedMaximum;
    }
    NSTimeInterval maximum = 0;
    for (NSNumber *value in self.values) {
        maximum = MAX(maximum, value.doubleValue);
    }
    if (maximum <= 0) {
        return 3600.0;
    }
    NSTimeInterval step = maximum <= 3600.0 ? 900.0 : 3600.0;
    return ceil(maximum / step) * step;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSRect plotRect = [self plotRect];
    [NSColor.separatorColor setStroke];
    for (NSInteger lineIndex = 0; lineIndex <= 2; lineIndex++) {
        CGFloat y = NSMinY(plotRect) + NSHeight(plotRect) * lineIndex / 2.0;
        NSBezierPath *line = [NSBezierPath bezierPath];
        [line moveToPoint:NSMakePoint(NSMinX(plotRect), y)];
        [line lineToPoint:NSMakePoint(NSMaxX(plotRect), y)];
        line.lineWidth = lineIndex == 0 ? 1.0 : 0.5;
        [line stroke];
    }

    NSTimeInterval maximum = [self chartMaximum];
    NSDictionary *axisAttributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:10.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: NSColor.secondaryLabelColor
    };
    NSString *maximumText = maximum >= 3600.0
        ? [NSString stringWithFormat:@"%.0f时", maximum / 3600.0]
        : [NSString stringWithFormat:@"%.0f分", maximum / 60.0];
    [maximumText drawAtPoint:NSMakePoint(4.0, NSMaxY(plotRect) - 7.0) withAttributes:axisAttributes];
    [@"0" drawAtPoint:NSMakePoint(25.0, NSMinY(plotRect) - 6.0) withAttributes:axisAttributes];

    BOOL hasValues = NO;
    for (NSNumber *value in self.values) {
        if (value.doubleValue > 0) {
            hasValues = YES;
            break;
        }
    }
    if (!hasValues) {
        NSDictionary *emptyAttributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:14.0 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: NSColor.tertiaryLabelColor
        };
        NSSize emptySize = [self.emptyText sizeWithAttributes:emptyAttributes];
        [self.emptyText drawAtPoint:NSMakePoint(NSMidX(plotRect) - emptySize.width / 2.0,
                                               NSMidY(plotRect) - emptySize.height / 2.0)
                         withAttributes:emptyAttributes];
    }

    NSUInteger count = self.values.count;
    if (count == 0) {
        return;
    }
    CGFloat slotWidth = NSWidth(plotRect) / count;
    CGFloat barWidth = MAX(3.0, slotWidth * 0.62);
    for (NSUInteger index = 0; index < count; index++) {
        NSTimeInterval value = self.values[index].doubleValue;
        CGFloat normalized = maximum > 0 ? MIN(1.0, value / maximum) : 0;
        CGFloat barHeight = value > 0 ? MAX(2.0, normalized * NSHeight(plotRect)) : 0;
        NSRect barRect = NSMakeRect(NSMinX(plotRect) + slotWidth * index + (slotWidth - barWidth) / 2.0,
                                   NSMinY(plotRect), barWidth, barHeight);
        NSColor *barColor = (NSInteger)index == self.hoverIndex
            ? [NSColor colorWithCalibratedRed:0.08 green:0.53 blue:0.94 alpha:1.0]
            : [NSColor colorWithCalibratedRed:0.18 green:0.58 blue:0.94 alpha:0.9];
        [barColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:barRect xRadius:3.0 yRadius:3.0] fill];

        if (index < self.axisLabels.count && self.axisLabels[index].length > 0) {
            NSString *label = self.axisLabels[index];
            NSSize labelSize = [label sizeWithAttributes:axisAttributes];
            [label drawAtPoint:NSMakePoint(NSMidX(barRect) - labelSize.width / 2.0, 5.0)
                withAttributes:axisAttributes];
        }
    }

    if (self.hoverIndex >= 0 && self.hoverIndex < (NSInteger)self.hoverTexts.count) {
        NSString *hoverText = self.hoverTexts[(NSUInteger)self.hoverIndex];
        NSDictionary *hoverAttributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: NSColor.labelColor
        };
        NSSize hoverSize = [hoverText sizeWithAttributes:hoverAttributes];
        NSRect hoverBackground = NSMakeRect(NSMaxX(plotRect) - hoverSize.width - 16.0,
                                            NSMaxY(plotRect) - hoverSize.height - 8.0,
                                            hoverSize.width + 12.0,
                                            hoverSize.height + 6.0);
        [NSColor.windowBackgroundColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:hoverBackground xRadius:4.0 yRadius:4.0] fill];
        [hoverText drawAtPoint:NSMakePoint(NSMinX(hoverBackground) + 6.0, NSMinY(hoverBackground) + 3.0)
                withAttributes:hoverAttributes];
    }
}

- (NSInteger)barIndexAtPoint:(NSPoint)point {
    NSRect plotRect = [self plotRect];
    if (!NSPointInRect(point, plotRect) || self.values.count == 0) {
        return -1;
    }
    CGFloat slotWidth = NSWidth(plotRect) / self.values.count;
    NSInteger index = (NSInteger)floor((point.x - NSMinX(plotRect)) / slotWidth);
    return MIN(MAX(index, 0), (NSInteger)self.values.count - 1);
}

- (void)mouseMoved:(NSEvent *)event {
    NSInteger index = [self barIndexAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (index != self.hoverIndex) {
        self.hoverIndex = index;
        self.needsDisplay = YES;
    }
}

- (void)mouseExited:(NSEvent *)event {
    self.hoverIndex = -1;
    self.needsDisplay = YES;
}

@end

typedef struct {
    CGFloat cellSize;
    CGFloat gap;
    CGFloat startX;
    CGFloat startY;
} StudyHeatmapGeometry;

@interface StudyActivityHeatmapView : NSView
@property (nonatomic, strong) StudyActivitySnapshot *snapshot;
@property (nonatomic) StudyActivityAggregationMode aggregationMode;
@property (nonatomic) NSInteger hoverIndex;
@property (nonatomic, copy, nullable) void (^dateClickHandler)(NSDate *date);
@end

@implementation StudyActivityHeatmapView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _aggregationMode = StudyActivityAggregationModeDaily;
        _hoverIndex = -1;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas.copy) {
        [self removeTrackingArea:area];
    }
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                       options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                                         owner:self
                                                      userInfo:nil];
    [self addTrackingArea:area];
}

- (void)setSnapshot:(StudyActivitySnapshot *)snapshot {
    _snapshot = snapshot;
    self.hoverIndex = -1;
    self.needsDisplay = YES;
}

- (void)setAggregationMode:(StudyActivityAggregationMode)aggregationMode {
    _aggregationMode = aggregationMode;
    self.hoverIndex = -1;
    self.needsDisplay = YES;
}

- (StudyHeatmapGeometry)geometry {
    NSInteger weekCount = MAX(1, self.snapshot.weekCount);
    CGFloat gap = NSWidth(self.bounds) >= 1080.0 ? 4.0 : 3.0;
    CGFloat availableWidth = MAX(0, NSWidth(self.bounds) - 8.0);
    CGFloat cellSize = floor((availableWidth - gap * (weekCount - 1)) / weekCount);
    cellSize = MAX(8.0, MIN(20.0, cellSize));
    CGFloat gridWidth = cellSize * weekCount + gap * (weekCount - 1);
    StudyHeatmapGeometry geometry;
    geometry.cellSize = cellSize;
    geometry.gap = gap;
    geometry.startX = floor((NSWidth(self.bounds) - gridWidth) / 2.0);
    geometry.startY = 58.0;
    return geometry;
}

- (NSRect)rectForIndex:(NSInteger)index geometry:(StudyHeatmapGeometry)geometry {
    NSInteger week = index / 7;
    NSInteger weekday = index % 7;
    return NSMakeRect(geometry.startX + week * (geometry.cellSize + geometry.gap),
                      geometry.startY + weekday * (geometry.cellSize + geometry.gap),
                      geometry.cellSize,
                      geometry.cellSize);
}

- (NSArray<NSColor *> *)activityColors {
    return @[
        StudyDynamicColor([NSColor colorWithCalibratedRed:0.84 green:0.92 blue:1.00 alpha:1.0],
                          [NSColor colorWithCalibratedRed:0.13 green:0.24 blue:0.34 alpha:1.0]),
        StudyDynamicColor([NSColor colorWithCalibratedRed:0.68 green:0.84 blue:0.99 alpha:1.0],
                          [NSColor colorWithCalibratedRed:0.12 green:0.32 blue:0.48 alpha:1.0]),
        StudyDynamicColor([NSColor colorWithCalibratedRed:0.49 green:0.75 blue:0.98 alpha:1.0],
                          [NSColor colorWithCalibratedRed:0.10 green:0.41 blue:0.63 alpha:1.0]),
        StudyDynamicColor([NSColor colorWithCalibratedRed:0.28 green:0.64 blue:0.97 alpha:1.0],
                          [NSColor colorWithCalibratedRed:0.08 green:0.50 blue:0.78 alpha:1.0]),
        StudyDynamicColor([NSColor colorWithCalibratedRed:0.08 green:0.53 blue:0.94 alpha:1.0],
                          [NSColor colorWithCalibratedRed:0.12 green:0.60 blue:0.94 alpha:1.0])
    ];
}

- (NSColor *)emptyCellColor {
    return StudyDynamicColor([NSColor colorWithCalibratedWhite:0.95 alpha:1.0],
                             [NSColor colorWithCalibratedWhite:0.20 alpha:1.0]);
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    if (!self.snapshot || self.snapshot.dates.count == 0) {
        return;
    }

    StudyHeatmapGeometry geometry = [self geometry];
    NSArray<NSNumber *> *durations = [self.snapshot durationsForMode:self.aggregationMode];
    NSTimeInterval maximum = 0;
    if (self.aggregationMode == StudyActivityAggregationModeDaily) {
        for (NSInteger index = 0; index < (NSInteger)durations.count; index++) {
            NSDate *date = self.snapshot.dates[(NSUInteger)index];
            if ([date compare:self.snapshot.today] != NSOrderedDescending) {
                maximum = MAX(maximum, durations[(NSUInteger)index].doubleValue);
            }
        }
    } else {
        for (NSInteger week = 0; week < self.snapshot.weekCount; week++) {
            maximum = MAX(maximum, durations[(NSUInteger)(week * 7)].doubleValue);
        }
    }
    NSArray<NSColor *> *activityColors = [self activityColors];
    NSColor *emptyColor = [self emptyCellColor];
    CGFloat radius = MIN(4.0, geometry.cellSize * 0.24);

    for (NSInteger index = 0; index < (NSInteger)self.snapshot.dates.count; index++) {
        NSDate *date = self.snapshot.dates[(NSUInteger)index];
        NSInteger week = index / 7;
        NSInteger weekday = index % 7;
        NSTimeInterval value = durations[(NSUInteger)index].doubleValue;
        BOOL future = [date compare:self.snapshot.today] == NSOrderedDescending;
        NSColor *color = emptyColor;
        if (self.aggregationMode == StudyActivityAggregationModeDaily) {
            if (!future && value > 0 && maximum > 0) {
                NSInteger level = (NSInteger)ceil(value / maximum * activityColors.count);
                level = MIN(MAX(level, 1), (NSInteger)activityColors.count);
                color = activityColors[(NSUInteger)(level - 1)];
            }
        } else {
            NSTimeInterval weekValue = durations[(NSUInteger)(week * 7)].doubleValue;
            NSInteger availableCells = 0;
            for (NSInteger weekDayIndex = 0; weekDayIndex < 7; weekDayIndex++) {
                NSInteger candidateIndex = week * 7 + weekDayIndex;
                if (candidateIndex < (NSInteger)self.snapshot.dates.count &&
                    [self.snapshot.dates[(NSUInteger)candidateIndex] compare:self.snapshot.today] != NSOrderedDescending) {
                    availableCells++;
                }
            }
            NSInteger filledCells = weekValue > 0 && maximum > 0
                ? MIN(availableCells, MAX(1, (NSInteger)ceil(weekValue / maximum * 7.0)))
                : 0;
            if (weekday >= availableCells - filledCells && weekday < availableCells) {
                color = activityColors[3];
            }
            if (self.hoverIndex >= 0 && week == self.hoverIndex / 7) {
                color = activityColors[0];
            }
            if (future) {
                color = emptyColor;
            }
        }
        [color setFill];
        NSRect cellRect = [self rectForIndex:index geometry:geometry];
        [[NSBezierPath bezierPathWithRoundedRect:cellRect xRadius:radius yRadius:radius] fill];

    }

    [self drawMonthLabelsWithGeometry:geometry];
    [self drawHoverTooltipWithGeometry:geometry durations:durations];
}

- (void)drawMonthLabelsWithGeometry:(StudyHeatmapGeometry)geometry {
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: NSColor.secondaryLabelColor
    };
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.dateFormat = @"M月";
    NSCalendar *calendar = [StudyStatisticsCalculator studyCalendar];
    NSInteger previousMonth = -1;
    CGFloat labelY = geometry.startY + 7.0 * (geometry.cellSize + geometry.gap) + 8.0;
    for (NSInteger index = 0; index < (NSInteger)self.snapshot.dates.count; index++) {
        NSDate *date = self.snapshot.dates[(NSUInteger)index];
        NSInteger month = [calendar component:NSCalendarUnitMonth fromDate:date];
        if (index == 0 || month != previousMonth) {
            NSInteger week = index / 7;
            NSString *label = [formatter stringFromDate:date];
            CGFloat x = geometry.startX + week * (geometry.cellSize + geometry.gap);
            [label drawAtPoint:NSMakePoint(x, labelY) withAttributes:attributes];
        }
        previousMonth = month;
    }
}

- (void)drawHoverTooltipWithGeometry:(StudyHeatmapGeometry)geometry
                            durations:(NSArray<NSNumber *> *)durations {
    if (self.hoverIndex < 0 || self.hoverIndex >= (NSInteger)self.snapshot.dates.count) {
        return;
    }
    NSInteger hoverWeek = self.hoverIndex / 7;
    NSInteger dateIndex = self.aggregationMode == StudyActivityAggregationModeDaily
        ? self.hoverIndex
        : MIN((NSInteger)self.snapshot.dates.count - 1, hoverWeek * 7 + 6);
    NSDate *date = self.snapshot.dates[(NSUInteger)dateIndex];
    NSTimeInterval duration = durations[(NSUInteger)self.hoverIndex].doubleValue;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.dateFormat = self.aggregationMode == StudyActivityAggregationModeDaily ? @"M月d日" : @"yyyy年M月d日";
    NSString *dateText = [formatter stringFromDate:date];
    NSString *tooltip = nil;
    switch (self.aggregationMode) {
        case StudyActivityAggregationModeWeekly:
            tooltip = [NSString stringWithFormat:@"%@ 当周学习了 %@", dateText, StudyDurationText(duration)];
            break;
        case StudyActivityAggregationModeCumulative:
            tooltip = [NSString stringWithFormat:@"截至%@ 当周累计学习 %@", dateText, StudyDurationText(duration)];
            break;
        case StudyActivityAggregationModeDaily:
        default:
            tooltip = [NSString stringWithFormat:@"%@ 学习了 %@", dateText, StudyDurationText(duration)];
            break;
    }

    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:16.0 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: NSColor.labelColor
    };
    NSSize textSize = [tooltip sizeWithAttributes:attributes];
    NSRect cellRect = [self rectForIndex:self.hoverIndex geometry:geometry];
    CGFloat tooltipWidth = textSize.width + 26.0;
    CGFloat tooltipHeight = textSize.height + 18.0;
    CGFloat x = NSMidX(cellRect) - tooltipWidth / 2.0;
    x = MIN(MAX(4.0, x), NSWidth(self.bounds) - tooltipWidth - 4.0);
    CGFloat y = 6.0;
    NSRect tooltipRect = NSMakeRect(x, y, tooltipWidth, tooltipHeight);

    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor colorWithCalibratedWhite:0 alpha:0.16];
    shadow.shadowBlurRadius = 8.0;
    shadow.shadowOffset = NSMakeSize(0, -2.0);
    [shadow set];
    [NSColor.windowBackgroundColor setFill];
    NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:tooltipRect xRadius:10.0 yRadius:10.0];
    [background fill];
    [NSGraphicsContext restoreGraphicsState];
    [NSColor.separatorColor setStroke];
    background.lineWidth = 1.0;
    [background stroke];
    [tooltip drawAtPoint:NSMakePoint(NSMinX(tooltipRect) + 13.0, NSMinY(tooltipRect) + 9.0)
          withAttributes:attributes];
}

- (NSInteger)indexAtPoint:(NSPoint)point {
    if (!self.snapshot || self.snapshot.weekCount <= 0) {
        return -1;
    }
    StudyHeatmapGeometry geometry = [self geometry];
    CGFloat step = geometry.cellSize + geometry.gap;
    CGFloat relativeX = point.x - geometry.startX;
    CGFloat relativeY = point.y - geometry.startY;
    if (relativeX < 0 || relativeY < 0) {
        return -1;
    }
    NSInteger week = (NSInteger)floor(relativeX / step);
    NSInteger weekday = (NSInteger)floor(relativeY / step);
    if (week < 0 || week >= self.snapshot.weekCount || weekday < 0 || weekday >= 7) {
        return -1;
    }
    if (fmod(relativeX, step) > geometry.cellSize || fmod(relativeY, step) > geometry.cellSize) {
        return -1;
    }
    NSInteger index = week * 7 + weekday;
    if (index >= (NSInteger)self.snapshot.dates.count ||
        [self.snapshot.dates[(NSUInteger)index] compare:self.snapshot.today] == NSOrderedDescending) {
        return -1;
    }
    return index;
}

- (void)updateHoverForEvent:(NSEvent *)event {
    NSInteger index = [self indexAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (index != self.hoverIndex) {
        self.hoverIndex = index;
        self.needsDisplay = YES;
    }
    [NSCursor.arrowCursor set];
}

- (void)mouseEntered:(NSEvent *)event {
    [self updateHoverForEvent:event];
}

- (void)mouseMoved:(NSEvent *)event {
    [self updateHoverForEvent:event];
}

- (void)mouseExited:(NSEvent *)event {
    self.hoverIndex = -1;
    self.needsDisplay = YES;
    [NSCursor.arrowCursor set];
}

- (void)mouseDown:(NSEvent *)event {
    NSInteger index = [self indexAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (index >= 0 && self.dateClickHandler) {
        self.dateClickHandler(self.snapshot.dates[(NSUInteger)index]);
        return;
    }
    [super mouseDown:event];
}

@end

@interface StudyStatisticsWindowController () <NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) StudyHistoryStore *historyStore;
@property (nonatomic) StudyStatisticsPage page;
@property (nonatomic, strong) NSDate *selectedDate;
@property (nonatomic, strong) NSSegmentedControl *pageControl;

@property (nonatomic, strong) StudyMetricsBandView *metricsBand;
@property (nonatomic, strong) NSTextField *activityTitleLabel;
@property (nonatomic, strong) StudyTextSegmentedControl *activityModeControl;
@property (nonatomic, strong) StudyActivityHeatmapView *heatmapView;

@property (nonatomic, strong) NSButton *previousButton;
@property (nonatomic, strong) NSButton *nextButton;
@property (nonatomic, strong) NSButton *resetDateButton;
@property (nonatomic, strong) NSTextField *periodLabel;
@property (nonatomic, strong) NSTextField *summaryTitleLabel;
@property (nonatomic, strong) NSTextField *summaryValueLabel;
@property (nonatomic, strong) NSTextField *secondaryTitleLabel;
@property (nonatomic, strong) NSTextField *secondaryValueLabel;
@property (nonatomic, strong) NSTextField *chartTitleLabel;
@property (nonatomic, strong) StudyBarChartView *chartView;
@property (nonatomic, strong) NSTextField *detailsTitleLabel;
@property (nonatomic, strong) NSScrollView *tableScrollView;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, copy) NSArray<NSDictionary *> *rows;
@property (nonatomic, strong) NSTimer *refreshTimer;
@end

@implementation StudyStatisticsWindowController

- (instancetype)initWithHistoryStore:(StudyHistoryStore *)historyStore {
    self = [super initWithWindow:nil];
    if (self) {
        _historyStore = historyStore;
        _page = StudyStatisticsPageOverview;
        _selectedDate = NSDate.date;
        _rows = @[];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(historyDidChange:)
                                                   name:StudyHistoryDidChangeNotification
                                                 object:historyStore];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self.refreshTimer invalidate];
}

- (void)buildWindowIfNeeded {
    if (self.window) {
        return;
    }
    NSRect frame = NSMakeRect(0, 0, 1240, 680);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"学习统计";
    window.releasedWhenClosed = NO;
    window.minSize = NSMakeSize(920, 600);
    window.delegate = self;
    window.acceptsMouseMovedEvents = YES;
    self.window = window;

    NSView *contentView = [[NSView alloc] initWithFrame:frame];
    window.contentView = contentView;

    self.pageControl = [NSSegmentedControl segmentedControlWithLabels:@[@"概览", @"日"]
                                                        trackingMode:NSSegmentSwitchTrackingSelectOne
                                                              target:self
                                                              action:@selector(pageChanged:)];
    self.pageControl.selectedSegment = 0;
    [contentView addSubview:self.pageControl];

    self.metricsBand = [[StudyMetricsBandView alloc] initWithFrame:NSZeroRect];
    [contentView addSubview:self.metricsBand];
    self.activityTitleLabel = [self labelWithFont:[NSFont systemFontOfSize:22.0 weight:NSFontWeightSemibold]
                                            color:NSColor.labelColor];
    self.activityTitleLabel.stringValue = @"学习活动";
    [contentView addSubview:self.activityTitleLabel];
    self.activityModeControl = (StudyTextSegmentedControl *)[StudyTextSegmentedControl segmentedControlWithLabels:@[@"每日", @"每周", @"累计"]
                                                                                                     trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                                                           target:self
                                                                                                           action:@selector(activityModeChanged:)];
    self.activityModeControl.selectedSegment = 0;
    [contentView addSubview:self.activityModeControl];
    self.heatmapView = [[StudyActivityHeatmapView alloc] initWithFrame:NSZeroRect];
    __weak typeof(self) weakSelf = self;
    self.heatmapView.dateClickHandler = ^(NSDate *date) {
        [weakSelf showDayForDate:date];
    };
    [contentView addSubview:self.heatmapView];

    self.previousButton = [self navigationButtonWithSymbol:@"chevron.left" fallbackTitle:@"‹" toolTip:@"上一天" action:@selector(showPreviousDay:)];
    self.nextButton = [self navigationButtonWithSymbol:@"chevron.right" fallbackTitle:@"›" toolTip:@"下一天" action:@selector(showNextDay:)];
    [contentView addSubview:self.previousButton];
    [contentView addSubview:self.nextButton];
    self.periodLabel = [NSTextField labelWithString:@""];
    self.periodLabel.alignment = NSTextAlignmentCenter;
    self.periodLabel.font = [NSFont systemFontOfSize:17.0 weight:NSFontWeightSemibold];
    [contentView addSubview:self.periodLabel];
    self.resetDateButton = [NSButton buttonWithTitle:@"今天" target:self action:@selector(resetToToday:)];
    self.resetDateButton.bezelStyle = NSBezelStyleRounded;
    [contentView addSubview:self.resetDateButton];

    self.summaryTitleLabel = [self labelWithFont:[NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium]
                                          color:NSColor.secondaryLabelColor];
    self.summaryValueLabel = [self labelWithFont:[NSFont monospacedDigitSystemFontOfSize:34.0 weight:NSFontWeightSemibold]
                                          color:NSColor.labelColor];
    self.secondaryTitleLabel = [self labelWithFont:[NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium]
                                            color:NSColor.secondaryLabelColor];
    self.secondaryValueLabel = [self labelWithFont:[NSFont monospacedDigitSystemFontOfSize:24.0 weight:NSFontWeightSemibold]
                                            color:NSColor.labelColor];
    [contentView addSubview:self.summaryTitleLabel];
    [contentView addSubview:self.summaryValueLabel];
    [contentView addSubview:self.secondaryTitleLabel];
    [contentView addSubview:self.secondaryValueLabel];

    self.chartTitleLabel = [self labelWithFont:[NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold]
                                         color:NSColor.labelColor];
    [contentView addSubview:self.chartTitleLabel];
    self.chartView = [[StudyBarChartView alloc] initWithFrame:NSZeroRect];
    [contentView addSubview:self.chartView];
    self.detailsTitleLabel = [self labelWithFont:[NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold]
                                           color:NSColor.labelColor];
    [contentView addSubview:self.detailsTitleLabel];

    self.tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 720, 180)];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 30.0;
    self.tableView.usesAlternatingRowBackgroundColors = YES;
    self.tableView.autoresizingMask = NSViewWidthSizable;
    NSTableColumn *periodColumn = [[NSTableColumn alloc] initWithIdentifier:@"period"];
    periodColumn.title = @"时间";
    periodColumn.minWidth = 300.0;
    periodColumn.resizingMask = NSTableColumnAutoresizingMask;
    [self.tableView addTableColumn:periodColumn];
    NSTableColumn *durationColumn = [[NSTableColumn alloc] initWithIdentifier:@"duration"];
    durationColumn.title = @"学习时长";
    durationColumn.width = 180.0;
    durationColumn.minWidth = 120.0;
    durationColumn.maxWidth = 240.0;
    durationColumn.resizingMask = NSTableColumnUserResizingMask;
    [self.tableView addTableColumn:durationColumn];

    self.tableScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.tableScrollView.documentView = self.tableView;
    self.tableScrollView.hasVerticalScroller = YES;
    self.tableScrollView.autohidesScrollers = YES;
    self.tableScrollView.borderType = NSBezelBorder;
    [contentView addSubview:self.tableScrollView];

    [self applyPageVisibility];
    [self layoutContent];
}

- (NSTextField *)labelWithFont:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:@""];
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (NSButton *)navigationButtonWithSymbol:(NSString *)symbol
                            fallbackTitle:(NSString *)fallbackTitle
                                  toolTip:(NSString *)toolTip
                                   action:(SEL)action {
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:toolTip];
    NSButton *button = image
        ? [NSButton buttonWithImage:image target:self action:action]
        : [NSButton buttonWithTitle:fallbackTitle target:self action:action];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.toolTip = toolTip;
    return button;
}

- (void)layoutContent {
    if (!self.window.contentView) {
        return;
    }
    NSRect bounds = self.window.contentView.bounds;
    CGFloat width = NSWidth(bounds);
    CGFloat height = NSHeight(bounds);
    self.pageControl.frame = NSMakeRect((width - 190.0) / 2.0, height - 47.0, 190.0, 28.0);

    self.metricsBand.frame = NSMakeRect(40.0, height - 200.0, width - 80.0, 116.0);
    self.activityTitleLabel.frame = NSMakeRect(40.0, height - 285.0, 240.0, 30.0);
    self.activityModeControl.frame = NSMakeRect(width - 292.0, height - 287.0, 252.0, 34.0);
    self.heatmapView.frame = NSMakeRect(36.0, MAX(24.0, height - 568.0), width - 72.0, 268.0);

    self.previousButton.frame = NSMakeRect(28.0, height - 92.0, 36.0, 30.0);
    self.nextButton.frame = NSMakeRect(width - 168.0, height - 92.0, 36.0, 30.0);
    self.resetDateButton.frame = NSMakeRect(width - 122.0, height - 92.0, 92.0, 30.0);
    self.periodLabel.frame = NSMakeRect(74.0, height - 89.0, width - 252.0, 24.0);
    self.summaryTitleLabel.frame = NSMakeRect(32.0, height - 138.0, 260.0, 18.0);
    self.summaryValueLabel.frame = NSMakeRect(32.0, height - 184.0, width * 0.60, 42.0);
    self.secondaryTitleLabel.frame = NSMakeRect(width - 232.0, height - 138.0, 200.0, 18.0);
    self.secondaryValueLabel.frame = NSMakeRect(width - 232.0, height - 179.0, 200.0, 34.0);
    self.chartTitleLabel.frame = NSMakeRect(32.0, height - 218.0, width - 64.0, 20.0);
    self.chartView.frame = NSMakeRect(24.0, height - 424.0, width - 48.0, 198.0);
    self.detailsTitleLabel.frame = NSMakeRect(32.0, height - 456.0, width - 64.0, 20.0);
    self.tableScrollView.frame = NSMakeRect(28.0, 20.0, width - 56.0, MAX(96.0, height - 486.0));

    NSSize tableContentSize = self.tableScrollView.contentSize;
    CGFloat headerHeight = self.tableView.headerView ? NSHeight(self.tableView.headerView.frame) : 0;
    CGFloat documentHeight = MAX(tableContentSize.height, headerHeight + self.rows.count * self.tableView.rowHeight);
    self.tableView.frame = NSMakeRect(0, 0, tableContentSize.width, documentHeight);
}

- (void)showStatisticsWindow {
    [self buildWindowIfNeeded];
    self.page = StudyStatisticsPageOverview;
    self.pageControl.selectedSegment = 0;
    self.selectedDate = NSDate.date;
    [self applyPageVisibility];
    [self refresh];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSRunningApplication.currentApplication activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    [self startRefreshTimer];
}

- (void)startRefreshTimer {
    [self.refreshTimer invalidate];
    self.refreshTimer = [NSTimer timerWithTimeInterval:30.0 target:self selector:@selector(refreshTimerFired:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.refreshTimer forMode:NSRunLoopCommonModes];
}

- (void)refreshTimerFired:(NSTimer *)timer {
    [self refresh];
}

- (void)historyDidChange:(NSNotification *)notification {
    if (self.window.isVisible) {
        [self refresh];
    }
}

- (void)windowDidResize:(NSNotification *)notification {
    [self layoutContent];
}

- (void)windowWillClose:(NSNotification *)notification {
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

- (void)pageChanged:(NSSegmentedControl *)sender {
    self.page = sender.selectedSegment == 0 ? StudyStatisticsPageOverview : StudyStatisticsPageDay;
    if (self.page == StudyStatisticsPageDay && !self.selectedDate) {
        self.selectedDate = NSDate.date;
    }
    [self applyPageVisibility];
    [self refresh];
}

- (void)activityModeChanged:(NSSegmentedControl *)sender {
    self.heatmapView.aggregationMode = (StudyActivityAggregationMode)sender.selectedSegment;
}

- (void)applyPageVisibility {
    BOOL showOverview = self.page == StudyStatisticsPageOverview;
    self.metricsBand.hidden = !showOverview;
    self.activityTitleLabel.hidden = !showOverview;
    self.activityModeControl.hidden = !showOverview;
    self.heatmapView.hidden = !showOverview;

    NSArray<NSView *> *dayViews = @[
        self.previousButton, self.nextButton, self.resetDateButton, self.periodLabel,
        self.summaryTitleLabel, self.summaryValueLabel, self.secondaryTitleLabel,
        self.secondaryValueLabel, self.chartTitleLabel, self.chartView,
        self.detailsTitleLabel, self.tableScrollView
    ];
    for (NSView *view in dayViews) {
        view.hidden = showOverview;
    }
}

- (void)showDayForDate:(NSDate *)date {
    self.selectedDate = date;
    self.page = StudyStatisticsPageDay;
    self.pageControl.selectedSegment = 1;
    [self applyPageVisibility];
    [self refresh];
}

- (void)showPreviousDay:(id)sender {
    NSCalendar *calendar = NSCalendar.currentCalendar;
    self.selectedDate = [calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:self.selectedDate options:0] ?: self.selectedDate;
    [self refresh];
}

- (void)showNextDay:(id)sender {
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDate *candidate = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:self.selectedDate options:0] ?: self.selectedDate;
    NSDate *today = [calendar startOfDayForDate:NSDate.date];
    self.selectedDate = [candidate compare:today] == NSOrderedDescending ? today : candidate;
    [self refresh];
}

- (void)resetToToday:(id)sender {
    self.selectedDate = NSDate.date;
    [self refresh];
}

- (void)refresh {
    if (!self.window) {
        return;
    }
    if (self.page == StudyStatisticsPageOverview) {
        [self refreshOverview];
    } else {
        [self refreshDayView];
        [self updateDayNavigationButtons];
        [self.tableView reloadData];
    }
    [self layoutContent];
}

- (NSArray<StudySessionRecord *> *)allSessionsAtDate:(NSDate *)now calendar:(NSCalendar *)calendar {
    NSDate *earliest = self.historyStore.earliestSessionDate;
    if (!earliest) {
        return @[];
    }
    NSDate *startDate = [calendar startOfDayForDate:earliest];
    NSDate *endDate = [now dateByAddingTimeInterval:1.0];
    return [self.historyStore sessionsIntersectingStartDate:startDate endDate:endDate now:now];
}

- (void)refreshOverview {
    NSDate *now = NSDate.date;
    NSCalendar *calendar = [StudyStatisticsCalculator studyCalendar];
    NSArray<StudySessionRecord *> *sessions = [self allSessionsAtDate:now calendar:calendar];
    StudyStatisticsSummary *summary = [StudyStatisticsCalculator summaryForSessions:sessions calendar:calendar now:now];
    StudyActivitySnapshot *snapshot = [StudyStatisticsCalculator activitySnapshotForSessions:sessions
                                                                                      calendar:calendar
                                                                                           now:now
                                                                                     weekCount:53];
    NSArray *values = @[
        StudyMetricDurationText(summary.totalDuration),
        StudyMetricDurationText(summary.peakDayDuration),
        StudyMetricDurationText(summary.longestSessionDuration),
        [NSString stringWithFormat:@"%ld 天", (long)summary.currentStreakDays],
        [NSString stringWithFormat:@"%ld 天", (long)summary.longestStreakDays]
    ];
    NSArray *titles = @[@"累计学习时间", @"单日峰值时间", @"最长单次学习", @"当前连续天数", @"最长连续天数"];
    [self.metricsBand setMetricValues:values titles:titles];
    self.heatmapView.snapshot = snapshot;
}

- (void)refreshDayView {
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDate *dayStart = [calendar startOfDayForDate:self.selectedDate];
    NSDate *dayEnd = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:dayStart options:0];
    NSDate *now = NSDate.date;
    NSArray<StudySessionRecord *> *sessions = [self.historyStore sessionsIntersectingStartDate:dayStart endDate:dayEnd now:now];

    NSTimeInterval total = 0;
    NSMutableArray<NSNumber *> *values = [NSMutableArray arrayWithCapacity:24];
    NSMutableArray<NSString *> *labels = [NSMutableArray arrayWithCapacity:24];
    NSMutableArray<NSString *> *hoverTexts = [NSMutableArray arrayWithCapacity:24];
    for (NSInteger hour = 0; hour < 24; hour++) {
        NSDate *hourStart = [calendar dateByAddingUnit:NSCalendarUnitHour value:hour toDate:dayStart options:0];
        NSDate *hourEnd = [calendar dateByAddingUnit:NSCalendarUnitHour value:1 toDate:hourStart options:0];
        NSTimeInterval hourTotal = [StudyStatisticsCalculator totalDurationForSessions:sessions startDate:hourStart endDate:hourEnd];
        [values addObject:@(hourTotal)];
        [labels addObject:(hour % 3 == 0 ? [NSString stringWithFormat:@"%ld", (long)hour] : @"")];
        [hoverTexts addObject:[NSString stringWithFormat:@"%02ld:00–%02ld:00 · %@",
                               (long)hour, (long)((hour + 1) % 24), StudyDurationText(hourTotal)]];
    }

    NSMutableArray<NSDictionary *> *rows = [NSMutableArray arrayWithCapacity:sessions.count];
    NSDateFormatter *timeFormatter = [[NSDateFormatter alloc] init];
    timeFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    timeFormatter.dateFormat = @"HH:mm";
    for (StudySessionRecord *session in sessions) {
        total += session.duration;
        NSString *endText = session.isActive ? @"现在" : [timeFormatter stringFromDate:session.endDate];
        [rows addObject:@{
            @"period": [NSString stringWithFormat:@"%@–%@%@",
                         [timeFormatter stringFromDate:session.startDate],
                         endText,
                         session.isActive ? @"  进行中" : @""],
            @"duration": StudyDurationText(session.duration)
        }];
    }
    self.rows = rows;

    NSDateFormatter *periodFormatter = [[NSDateFormatter alloc] init];
    periodFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    periodFormatter.dateFormat = @"yyyy年M月d日 EEEE";
    self.periodLabel.stringValue = [periodFormatter stringFromDate:dayStart];
    BOOL isToday = [calendar isDateInToday:dayStart];
    self.summaryTitleLabel.stringValue = isToday ? @"今日学习" : @"当日学习";
    self.summaryValueLabel.stringValue = StudyDurationText(total);
    self.secondaryTitleLabel.stringValue = @"学习段数";
    self.secondaryValueLabel.stringValue = [NSString stringWithFormat:@"%ld 段", (long)sessions.count];
    self.chartTitleLabel.stringValue = @"一天中的学习分布";
    self.detailsTitleLabel.stringValue = @"学习记录";
    self.chartView.values = values;
    self.chartView.axisLabels = labels;
    self.chartView.hoverTexts = hoverTexts;
    self.chartView.fixedMaximum = 3600.0;
    self.chartView.emptyText = @"当天暂无学习记录";
}

- (void)updateDayNavigationButtons {
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDate *today = [calendar startOfDayForDate:NSDate.date];
    NSDate *selectedDay = [calendar startOfDayForDate:self.selectedDate];
    self.nextButton.enabled = [selectedDay compare:today] == NSOrderedAscending;
    NSDate *earliest = self.historyStore.earliestSessionDate;
    self.previousButton.enabled = earliest && [selectedDay compare:[calendar startOfDayForDate:earliest]] == NSOrderedDescending;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.rows.count;
}

- (nullable NSView *)tableView:(NSTableView *)tableView
            viewForTableColumn:(NSTableColumn *)tableColumn
                           row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.rows.count) {
        return nil;
    }
    NSString *identifier = tableColumn.identifier;
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 30.0)];
        cell.identifier = identifier;
        NSTextField *label = [NSTextField labelWithString:@""];
        label.frame = NSMakeRect(8.0, 5.0, tableColumn.width - 16.0, 20.0);
        label.autoresizingMask = NSViewWidthSizable;
        label.font = [NSFont systemFontOfSize:13.0];
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        cell.textField = label;
        [cell addSubview:label];
    }
    cell.textField.stringValue = self.rows[(NSUInteger)row][identifier] ?: @"";
    return cell;
}

@end
