#import <Cocoa/Cocoa.h>

static NSColor *Color(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha) {
    return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:alpha];
}

static void DrawRoundedShadow(NSRect rect, CGFloat radius, CGFloat alpha) {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
    [[NSColor colorWithCalibratedWhite:0.0 alpha:alpha] setFill];
    [path fill];
}

static void DrawIcon(CGFloat size) {
    NSRect canvas = NSMakeRect(0, 0, size, size);
    CGFloat corner = size * 0.225;

    NSBezierPath *backgroundPath = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(canvas, size * 0.035, size * 0.035)
                                                                   xRadius:corner
                                                                   yRadius:corner];
    NSGradient *background = [[NSGradient alloc] initWithStartingColor:Color(0.025, 0.050, 0.055, 1.0)
                                                           endingColor:Color(0.080, 0.150, 0.145, 1.0)];
    [background drawInBezierPath:backgroundPath angle:90.0];

    NSBezierPath *highlight = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(canvas, size * 0.060, size * 0.060)
                                                              xRadius:corner * 0.86
                                                              yRadius:corner * 0.86];
    highlight.lineWidth = MAX(1.0, size * 0.010);
    [Color(1.0, 1.0, 1.0, 0.12) setStroke];
    [highlight stroke];

    CGFloat ringDiameter = size * 0.62;
    NSRect ringRect = NSMakeRect((size - ringDiameter) / 2.0,
                                 (size - ringDiameter) / 2.0,
                                 ringDiameter,
                                 ringDiameter);
    CGFloat lineWidth = size * 0.055;
    NSRect strokeRect = NSInsetRect(ringRect, lineWidth / 2.0, lineWidth / 2.0);
    NSPoint center = NSMakePoint(NSMidX(strokeRect), NSMidY(strokeRect));
    CGFloat radius = NSWidth(strokeRect) / 2.0;

    DrawRoundedShadow(NSOffsetRect(ringRect, 0, -size * 0.018), ringDiameter / 2.0, 0.20);

    NSBezierPath *track = [NSBezierPath bezierPathWithOvalInRect:strokeRect];
    track.lineWidth = lineWidth;
    track.lineCapStyle = NSLineCapStyleRound;
    [Color(0.18, 0.31, 0.30, 0.58) setStroke];
    [track stroke];

    NSBezierPath *progress = [NSBezierPath bezierPath];
    [progress appendBezierPathWithArcWithCenter:center
                                         radius:radius
                                     startAngle:92.0
                                       endAngle:-225.0
                                      clockwise:YES];
    progress.lineWidth = lineWidth;
    progress.lineCapStyle = NSLineCapStyleRound;
    [Color(0.31, 0.88, 0.78, 1.0) setStroke];
    [progress stroke];

    CGFloat dotSize = size * 0.085;
    NSRect dotRect = NSMakeRect(center.x - dotSize / 2.0,
                                center.y + radius - dotSize / 2.0,
                                dotSize,
                                dotSize);
    [Color(0.88, 0.96, 0.90, 1.0) setFill];
    [[NSBezierPath bezierPathWithOvalInRect:dotRect] fill];

    NSString *number = @"20";
    CGFloat fontSize = size * 0.245;
    NSDictionary<NSAttributedStringKey, id> *numberAttributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:fontSize weight:NSFontWeightHeavy],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    NSSize numberSize = [number sizeWithAttributes:numberAttributes];
    [number drawAtPoint:NSMakePoint(center.x - numberSize.width / 2.0,
                                    center.y - numberSize.height / 2.0 + size * 0.008)
        withAttributes:numberAttributes];
}

static BOOL WritePNG(NSString *path, CGFloat size) {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [image lockFocus];
    DrawIcon(size);
    [image unlockFocus];

    NSRect imageRect = NSMakeRect(0, 0, size, size);
    CGImageRef cgImage = [image CGImageForProposedRect:&imageRect context:nil hints:nil];
    if (!cgImage) {
        return NO;
    }

    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    bitmap.size = NSMakeSize(size, size);
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [png writeToFile:path atomically:YES];
}

static void AppendUInt32(NSMutableData *data, uint32_t value) {
    uint32_t bigEndian = CFSwapInt32HostToBig(value);
    [data appendBytes:&bigEndian length:sizeof(bigEndian)];
}

static void AppendType(NSMutableData *data, const char *type) {
    [data appendBytes:type length:4];
}

static BOOL WriteICNS(NSString *iconsetDir, NSString *icnsPath) {
    NSArray<NSDictionary<NSString *, NSString *> *> *chunks = @[
        @{@"type": @"icp4", @"file": @"icon_16x16.png"},
        @{@"type": @"icp5", @"file": @"icon_32x32.png"},
        @{@"type": @"icp6", @"file": @"icon_32x32@2x.png"},
        @{@"type": @"ic07", @"file": @"icon_128x128.png"},
        @{@"type": @"ic08", @"file": @"icon_256x256.png"},
        @{@"type": @"ic09", @"file": @"icon_512x512.png"},
        @{@"type": @"ic10", @"file": @"icon_512x512@2x.png"}
    ];

    NSMutableData *icns = [NSMutableData data];
    AppendType(icns, "icns");
    AppendUInt32(icns, 0);

    for (NSDictionary<NSString *, NSString *> *chunk in chunks) {
        NSString *pngPath = [iconsetDir stringByAppendingPathComponent:chunk[@"file"]];
        NSData *png = [NSData dataWithContentsOfFile:pngPath];
        if (!png) {
            return NO;
        }

        AppendType(icns, chunk[@"type"].UTF8String);
        AppendUInt32(icns, (uint32_t)(png.length + 8));
        [icns appendData:png];
    }

    uint32_t totalLength = CFSwapInt32HostToBig((uint32_t)icns.length);
    [icns replaceBytesInRange:NSMakeRange(4, 4) withBytes:&totalLength length:sizeof(totalLength)];
    return [icns writeToFile:icnsPath atomically:YES];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 4) {
            fprintf(stderr, "usage: IconGenerator <iconset-dir> <preview-png> <icns-path>\n");
            return 2;
        }

        NSString *iconsetDir = [NSString stringWithUTF8String:argv[1]];
        NSString *previewPath = [NSString stringWithUTF8String:argv[2]];
        NSString *icnsPath = [NSString stringWithUTF8String:argv[3]];
        NSFileManager *fileManager = NSFileManager.defaultManager;
        [fileManager removeItemAtPath:iconsetDir error:nil];
        [fileManager createDirectoryAtPath:iconsetDir withIntermediateDirectories:YES attributes:nil error:nil];
        [fileManager createDirectoryAtPath:previewPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [fileManager createDirectoryAtPath:icnsPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];

        NSDictionary<NSString *, NSNumber *> *sizes = @{
            @"icon_16x16.png": @16,
            @"icon_16x16@2x.png": @32,
            @"icon_32x32.png": @32,
            @"icon_32x32@2x.png": @64,
            @"icon_128x128.png": @128,
            @"icon_128x128@2x.png": @256,
            @"icon_256x256.png": @256,
            @"icon_256x256@2x.png": @512,
            @"icon_512x512.png": @512,
            @"icon_512x512@2x.png": @1024
        };

        for (NSString *name in sizes) {
            NSString *path = [iconsetDir stringByAppendingPathComponent:name];
            if (!WritePNG(path, sizes[name].doubleValue)) {
                fprintf(stderr, "failed to write %s\n", path.UTF8String);
                return 1;
            }
        }

        if (!WritePNG(previewPath, 1024)) {
            fprintf(stderr, "failed to write preview\n");
            return 1;
        }

        if (!WriteICNS(iconsetDir, icnsPath)) {
            fprintf(stderr, "failed to write icns\n");
            return 1;
        }
    }

    return 0;
}
