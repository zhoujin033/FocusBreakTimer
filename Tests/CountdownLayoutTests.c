#include "CountdownLayout.h"
#include <stdio.h>
#include <stdlib.h>

static void Require(int condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static int Near(double a, double b) {
    return fabs(a - b) < 0.00001;
}

static int Contains(double width, double height, FBTCountdownRect rect) {
    return rect.width > 0 && rect.height > 0 && rect.x >= 0 && rect.y >= 0 &&
        rect.x + rect.width <= width + 0.00001 &&
        rect.y + rect.height <= height + 0.00001;
}

static int Overlaps(FBTCountdownRect a, FBTCountdownRect b) {
    return a.x < b.x + b.width && b.x < a.x + a.width &&
        a.y < b.y + b.height && b.y < a.y + a.height;
}

static void CheckLayout(double width, double height) {
    FBTCountdownLayout layout = FBTMakeCountdownLayout(width, height);
    FBTCountdownRect title = FBTCountdownRectInView(layout, layout.title, 0, 0);
    FBTCountdownRect ring = FBTCountdownRectInView(layout, layout.ring, 0, 0);
    FBTCountdownRect snooze = FBTCountdownRectInView(layout, layout.snooze, 0, 0);
    FBTCountdownRect emergency = FBTCountdownRectInView(layout, layout.emergency, 0, 0);
    FBTCountdownRect sleep = FBTCountdownRectInView(layout, layout.displaySleep, 0, 0);
    FBTCountdownRect keepGoing = FBTCountdownRectInView(layout, layout.continueStudy, 0, 0);
    FBTCountdownRect stop = FBTCountdownRectInView(layout, layout.stopStudy, 0, 0);
    FBTCountdownRect rects[] = {title, ring, snooze, sleep, emergency, keepGoing, stop};
    for (unsigned i = 0; i < sizeof(rects) / sizeof(rects[0]); i++) {
        Require(Contains(width, height, rects[i]), "all elements must stay inside the display");
    }
    Require(Near(ring.width, ring.height), "the ring must stay circular at every aspect ratio");
    Require(Near(ring.x + ring.width / 2, width / 2), "ring must be horizontally centered");
    Require(Near(height - title.y - title.height, keepGoing.y),
            "the title/ring/main-action group must have equal top and bottom whitespace");
    Require(!Overlaps(title, ring) && title.y > ring.y,
            "the title must retain its own space above the ring");
    Require(!Overlaps(snooze, emergency), "rest buttons must never overlap");
    Require(!Overlaps(sleep, snooze) && !Overlaps(sleep, emergency) && !Overlaps(sleep, ring),
            "display sleep must remain separate from every rest element");
    Require(!Overlaps(ring, snooze) && !Overlaps(ring, emergency),
            "rest buttons must not cover the ring");
    Require(!Overlaps(keepGoing, stop) && !Overlaps(ring, keepGoing) && !Overlaps(ring, stop),
            "decision buttons must not overlap each other or the ring");
    Require(emergency.y + emergency.height < snooze.y,
            "emergency button must remain below the snooze button");
    Require(Near(snooze.x, keepGoing.x) && Near(snooze.y, keepGoing.y) &&
            Near(snooze.width, keepGoing.width) && Near(snooze.height, keepGoing.height) &&
            Near(sleep.x, stop.x) && Near(sleep.y, stop.y) &&
            Near(sleep.width, stop.width) && Near(sleep.height, stop.height),
            "rest completion must keep both action buttons in exactly the same positions and sizes");

    // Displays can be left of, above, or below the primary screen. Moving the
    // origin must translate every point without changing the size or scale.
    double origins[][2] = {{-1920, 0}, {0, -1080}, {1440, 900}, {-720, -1280}};
    for (unsigned i = 0; i < sizeof(origins) / sizeof(origins[0]); i++) {
        FBTCountdownRect translated = FBTCountdownRectInView(layout, layout.emergency,
                                                            origins[i][0], origins[i][1]);
        Require(Near(translated.x - origins[i][0], emergency.x) &&
                Near(translated.y - origins[i][1], emergency.y) &&
                Near(translated.width, emergency.width) && Near(translated.height, emergency.height),
                "coordinate conversion must preserve the drawn hit region");
    }
}

int main(void) {
    double sizes[][2] = {
        {960, 540}, {800, 450}, {1024, 576}, {1280, 720}, {1440, 900},
        {1512, 982}, {1728, 1117}, {1920, 1080}, {2560, 1440}, {3840, 2160},
        {3440, 1440}, {5120, 1440}, {1080, 1920}, {720, 1280}, {640, 480},
        {800, 600}, {1032.5, 648.25}
    };
    unsigned count = 0;
    for (unsigned i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        CheckLayout(sizes[i][0], sizes[i][1]);
        count++;
    }
    for (int width = 320; width <= 6016; width += 113) {
        for (int height = 240; height <= 3380; height += 79) {
            CheckLayout(width, height);
            count++;
        }
    }

    // 960x540 formerly put the emergency button 14.8 points over the snooze
    // button. It must now be a uniform 0.75 rendering of the 1280x720 layout.
    FBTCountdownLayout compact = FBTMakeCountdownLayout(960, 540);
    Require(Near(compact.scale, 0.75), "compact screens must use uniform fitting");
    Require(Near(FBTMakeCountdownLayout(1920, 1080).scale, 1),
            "ordinary desktop layouts must retain their existing size");

    Require(FBTMakeCountdownLayout(0, 720).scale == 0 &&
            FBTMakeCountdownLayout(1280, 0).scale == 0 &&
            FBTMakeCountdownLayout(-1, 720).scale == 0 &&
            FBTMakeCountdownLayout(NAN, 720).scale == 0 &&
            FBTMakeCountdownLayout(1280, INFINITY).scale == 0,
            "transient invalid sizes must produce an empty layout");
    printf("Countdown layout tests passed (%u display sizes).\n", count);
    return 0;
}
