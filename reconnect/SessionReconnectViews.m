#import "SessionReconnectViews.h"

@interface SessionSidebarButton ()
@property(nonatomic, strong) NSTrackingArea *hoverArea;
@property(nonatomic) BOOL hovered;
@property(nonatomic, strong) NSProgressIndicator *spinner;
@end

@implementation SessionSidebarButton
- (void)setBusy:(BOOL)busy {
    _busy = busy;
    if (busy && !self.spinner) {
        self.spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(10, 10, 16, 16)];
        self.spinner.style = NSProgressIndicatorStyleSpinning;
        self.spinner.controlSize = NSControlSizeSmall;
        self.spinner.usesThreadedAnimation = YES;
        self.spinner.displayedWhenStopped = NO;
        [self addSubview:self.spinner];
    }
    if (busy) [self.spinner startAnimation:nil];
    else [self.spinner stopAnimation:nil];
    self.needsDisplay = YES;
}
- (void)updateTrackingAreas {
    if (self.hoverArea) [self removeTrackingArea:self.hoverArea];
    self.hoverArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways |
                NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:self.hoverArea];
    [super updateTrackingAreas];
}
- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    self.hovered = YES;
    self.needsDisplay = YES;
}
- (void)mouseExited:(NSEvent *)event {
    (void)event;
    self.hovered = NO;
    self.needsDisplay = YES;
}
- (BOOL)isFlipped { return YES; }
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSString *appearance = [self.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    BOOL dark = [appearance isEqualToString:NSAppearanceNameDarkAqua];
    BOOL active = NSApp.active && self.window.keyWindow;
    BOOL pressed = self.cell.highlighted;
    CGFloat alpha = active ? (dark ? 0.68 : 0.64) : (dark ? 0.32 : 0.30);
    CGFloat background = 0;
    if (self.hovered && self.enabled) {
        background = dark ? 0.05 : 0.04;
        if (!active) alpha = dark ? 0.44 : 0.42;
    }
    if (pressed) { alpha = dark ? 0.92 : 0.90; background = dark ? 0.10 : 0.07; }
    if (!self.enabled) alpha = dark ? 0.32 : 0.30;
    CGFloat channel = dark ? 1 : 0;
    if (background > 0) {
        [[NSColor colorWithSRGBRed:channel green:channel blue:channel alpha:background] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:self.bounds] fill];
    }
    if (self.busy) return;
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(25.2, 19.2)];
    [path curveToPoint:NSMakePoint(18, 26.4) controlPoint1:NSMakePoint(25.2, 23.176)
        controlPoint2:NSMakePoint(21.976, 26.4)];
    [path curveToPoint:NSMakePoint(10.8, 19.2) controlPoint1:NSMakePoint(14.024, 26.4)
        controlPoint2:NSMakePoint(10.8, 23.176)];
    [path curveToPoint:NSMakePoint(18, 12) controlPoint1:NSMakePoint(10.8, 15.224)
        controlPoint2:NSMakePoint(14.024, 12)];
    [path lineToPoint:NSMakePoint(22, 12)];
    [path moveToPoint:NSMakePoint(19, 9)];
    [path lineToPoint:NSMakePoint(22, 12)];
    [path lineToPoint:NSMakePoint(19, 15)];
    path.lineWidth = 1.4;
    path.lineCapStyle = NSLineCapStyleRound;
    path.lineJoinStyle = NSLineJoinStyleRound;
    NSAffineTransform *scale = [NSAffineTransform transform];
    [scale translateXBy:NSWidth(self.bounds) / 2 + 0.3 yBy:NSHeight(self.bounds) / 2];
    [scale scaleXBy:NSWidth(self.bounds) / 36 * 0.90 yBy:NSHeight(self.bounds) / 36 * 0.90];
    [scale translateXBy:-18 yBy:-18];
    [path transformUsingAffineTransform:scale];
    [[NSColor colorWithSRGBRed:channel green:channel blue:channel alpha:alpha] setStroke];
    [path stroke];
    if (self.holding) {
        [[NSColor.systemOrangeColor colorWithAlphaComponent:active ? 1.0 : 0.55] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(27, 5, 5, 5)] fill];
    }
}

@end

@interface SessionReconnectFeedback ()
@property(nonatomic, strong) NSTextField *feedbackLabel;
@property(nonatomic, strong) NSProgressIndicator *feedbackSpinner;
@end

@implementation SessionReconnectFeedback
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithSRGBRed:81.0 / 255 green:81.0 / 255 blue:81.0 / 255
                        alpha:224.0 / 255] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:14 yRadius:14] fill];
}
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
- (void)showMessage:(NSString *)message spinning:(BOOL)spinning inView:(NSView *)content {
    if (!self.feedbackLabel) {
        self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
        self.wantsLayer = YES;
        self.layer.cornerRadius = 14;
        self.layer.masksToBounds = YES;
        self.feedbackLabel = [NSTextField wrappingLabelWithString:@""];
        self.feedbackLabel.alignment = NSTextAlignmentCenter;
        self.feedbackLabel.preferredMaxLayoutWidth = 170;
        self.feedbackLabel.maximumNumberOfLines = 2;
        self.feedbackLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        self.feedbackLabel.textColor = NSColor.whiteColor;
        [self addSubview:self.feedbackLabel];
        self.feedbackSpinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(85, 46, 20, 20)];
        self.feedbackSpinner.style = NSProgressIndicatorStyleSpinning;
        self.feedbackSpinner.usesThreadedAnimation = YES;
        self.feedbackSpinner.displayedWhenStopped = NO;
        [self addSubview:self.feedbackSpinner];
    }
    self.frame = NSMakeRect((NSWidth(content.bounds) - 190) / 2,
                           (NSHeight(content.bounds) - 84) / 2, 190, 84);
    self.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin |
                            NSViewMinYMargin | NSViewMaxYMargin;
    self.feedbackLabel.stringValue = message;
    CGFloat textHeight = MIN(36, MAX(17, ceil(self.feedbackLabel.fittingSize.height)));
    CGFloat groupHeight = textHeight + (spinning ? 28 : 0);
    CGFloat textY = (NSHeight(self.bounds) - groupHeight) / 2;
    self.feedbackLabel.frame = NSMakeRect(10, textY, 170, textHeight);
    self.feedbackSpinner.frame = NSMakeRect(85, textY + textHeight + 8, 20, 20);
    if (spinning) [self.feedbackSpinner startAnimation:nil];
    else [self.feedbackSpinner stopAnimation:nil];
    [content addSubview:self positioned:NSWindowAbove relativeTo:nil];
}
@end
