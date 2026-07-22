#import "AppDelegate.h"
#import "MDController.h"
#import "MDWatchers.h"

@interface AppDelegate ()
@property (strong) NSStatusItem *statusItem;
@property (strong) MDController *controller;
@property (strong) MDWatchers *watchers;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
  self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
  self.controller = [[MDController alloc] init];
  [self refresh];
  __weak AppDelegate *weak = self;
  self.watchers = [[MDWatchers alloc] initWithStatePath:self.controller.stateFilePath
                                               onChange:^{ [weak refresh]; }];
  [self.watchers start];
}

- (void)refresh {
  NSString *state = [self.controller currentState];
  NSImage *icon = [self iconForState:state];
  icon.template = YES;
  [self.statusItem setImage:icon];
  [self.statusItem setToolTip:[@"Docker: " stringByAppendingString:state]];
  if (self.watchers)
    [self.watchers watchVmxPid:([state isEqualToString:@"running"] ? [self.controller vmxPid] : 0)];
  [self rebuildMenu];
}

- (NSString *)humanState:(NSString *)s {
  if ([s isEqualToString:@"running"])   return @"Docker: Running";
  if ([s isEqualToString:@"stopped"])   return @"Docker: Stopped";
  if ([s isEqualToString:@"creating"])  return @"Docker: Starting…";
  if ([s isEqualToString:@"absent"])    return @"Docker: Not set up";
  if ([s isEqualToString:@"no-fusion"]) return @"VMware Fusion needed";
  return @"Docker: (error)";
}

- (void)rebuildMenu {
  NSString *state = [self.controller currentState];
  NSMenu *m = [[NSMenu alloc] init];

  NSMenuItem *header = [m addItemWithTitle:[self humanState:state] action:NULL keyEquivalent:@""];
  header.enabled = NO;
  [m addItem:[NSMenuItem separatorItem]];

  if ([state isEqualToString:@"no-fusion"]) {
    NSMenuItem *f = [m addItemWithTitle:@"Install VMware Fusion…" action:NULL keyEquivalent:@""];
    f.enabled = NO;
  } else if ([state isEqualToString:@"absent"] || [state isEqualToString:@"error"]) {
    [m addItemWithTitle:@"Set Up / Repair…" action:@selector(doSetup:) keyEquivalent:@""];
  } else if (![state isEqualToString:@"creating"]) {
    if ([state isEqualToString:@"running"]) {
      [m addItemWithTitle:@"Stop Docker" action:@selector(doStop:) keyEquivalent:@""];
      [m addItemWithTitle:@"Restart Docker" action:@selector(doRestart:) keyEquivalent:@""];
    } else {
      [m addItemWithTitle:@"Start Docker" action:@selector(doStart:) keyEquivalent:@""];
    }
  }

  [m addItem:[NSMenuItem separatorItem]];
  [m addItemWithTitle:@"Show Log" action:@selector(showLog:) keyEquivalent:@""];
  [m addItem:[NSMenuItem separatorItem]];
  [m addItemWithTitle:@"Quit Container Tools for Mavericks" action:@selector(terminate:) keyEquivalent:@"q"];

  for (NSMenuItem *it in m.itemArray) if (it.action && it.action != @selector(terminate:)) it.target = self;
  [self.statusItem setMenu:m];
}

- (void)runAndRefresh:(NSString *)verb {
  NSImage *icon = [self iconForState:@"working"];
  icon.template = YES;
  [self.statusItem setImage:icon];
  [self.controller runVerb:verb completion:^(NSString *out, int code) { [self refresh]; }];
}
- (void)doStart:(id)s   { [self runAndRefresh:@"start"]; }
- (void)doStop:(id)s    { [self runAndRefresh:@"stop"]; }
- (void)doRestart:(id)s { [self runAndRefresh:@"restart"]; }
- (void)doSetup:(id)s   { [self runAndRefresh:@"setup"]; }

- (void)showLog:(id)s {
  NSString *log = [NSHomeDirectory() stringByAppendingPathComponent:
    @"Library/Logs/ModernMavericks/container-tools/bootstrap.log"];
  [[NSWorkspace sharedWorkspace] openFile:log withApplication:@"Console"];
}

- (NSImage *)iconForState:(NSString *)state {
  NSImage *img = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO
      drawingHandler:^BOOL(NSRect r) {
    NSRect o = NSInsetRect(r, 3, 3);
    NSBezierPath *p = [NSBezierPath bezierPathWithOvalInRect:o];
    [[NSColor blackColor] set];
    if ([state isEqualToString:@"running"]) { [p fill]; }
    else if ([state isEqualToString:@"working"] || [state isEqualToString:@"creating"]) {
      [p stroke]; NSBezierPath *h = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(o, 4, 4)]; [h fill];
    } else { p.lineWidth = 1.5; [p stroke]; }
    return YES;
  }];
  return img;
}

@end
