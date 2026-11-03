#ifndef FOCUS_BREAK_TIMER_COUNTDOWN_LAYOUT_H
#define FOCUS_BREAK_TIMER_COUNTDOWN_LAYOUT_H

#include <math.h>

/* Geometry is in AppKit points, never display pixels or global screen coordinates.
 * Keep the established layout on a canvas of at least 1280 x 720 points, then
 * uniformly scale that canvas to fit smaller/HiDPI-scaled displays. Drawing and
 * hit testing must use the same transform. This header is also testable without
 * AppKit so that layout regressions can be checked on any build host. */
typedef struct {
    double x, y, width, height;
} FBTCountdownRect;

typedef struct {
    double scale, canvasWidth, canvasHeight, titleFontSize;
    FBTCountdownRect title, ring, snooze, displaySleep, emergency, continueStudy, stopStudy;
} FBTCountdownLayout;

static inline FBTCountdownLayout FBTMakeCountdownLayout(double width, double height) {
    FBTCountdownLayout layout = {0};
    if (!isfinite(width) || !isfinite(height) || width <= 0 || height <= 0) {
        return layout;
    }

    layout.scale = fmin(1.0, fmin(width / 1280.0, height / 720.0));
    double w = layout.canvasWidth = width / layout.scale;
    double h = layout.canvasHeight = height / layout.scale;
    double diameter = fmin(fmin(w * 0.58, h * 0.54), 720.0);
    layout.titleFontSize = fmin(fmax(diameter * 0.085, 32.0), 70.0);
    double titleHeight = layout.titleFontSize * 1.25;
    double titleGap = fmin(h * 0.035, 38.0);
    double buttonHeight = fmin(fmax(h * 0.075, 68.0), 92.0);
    double buttonWidth = fmin(fmax(w * 0.25, 310.0), 430.0);
    double ringGap = fmin(fmax(h * 0.045, 34.0), 56.0);
    // Center the entire title/ring/action group, not the ring alone. Both
    // screen modes share this anchor; the emergency row stays below it.
    double groupHeight = titleHeight + titleGap + diameter + ringGap + buttonHeight;
    double buttonY = (h - groupHeight) / 2.0;
    layout.ring = (FBTCountdownRect){(w - diameter) / 2.0, buttonY + buttonHeight + ringGap,
                                    diameter, diameter};
    layout.title = (FBTCountdownRect){32.0, layout.ring.y + diameter + titleGap, w - 64.0, titleHeight};
    double gap = 24.0;
    double restLeft = (w - buttonWidth * 2.0 - gap) / 2.0;
    layout.snooze = (FBTCountdownRect){restLeft, buttonY,
                                      buttonWidth, buttonHeight};
    layout.displaySleep = (FBTCountdownRect){restLeft + buttonWidth + gap, buttonY,
                                            buttonWidth, buttonHeight};

    double emergencyHeight = fmin(fmax(h * 0.052, 46.0), 58.0);
    double emergencyWidth = fmin(fmax(w * 0.28, 340.0), 470.0);
    layout.emergency = (FBTCountdownRect){(w - emergencyWidth) / 2.0,
        buttonY - emergencyHeight - 16.0, emergencyWidth, emergencyHeight};

    layout.continueStudy = layout.snooze;
    layout.stopStudy = layout.displaySleep;
    return layout;
}

static inline FBTCountdownRect FBTCountdownRectInView(FBTCountdownLayout layout,
                                                     FBTCountdownRect rect,
                                                     double originX, double originY) {
    return (FBTCountdownRect){originX + rect.x * layout.scale,
                             originY + rect.y * layout.scale,
                             rect.width * layout.scale, rect.height * layout.scale};
}

#endif
