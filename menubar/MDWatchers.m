#import "MDWatchers.h"
#import <AppKit/AppKit.h>
#import <sys/event.h>
#import <fcntl.h>

@interface MDWatchers () {
  NSString *_statePath;
  void (^_onChange)(void);
  dispatch_source_t _fileSrc;   // state file NOTE_WRITE
  dispatch_source_t _procSrc;   // vmx NOTE_EXIT
  dispatch_source_t _timerSrc;  // slow fallback
  id _wakeObserver;             // NSWorkspace wake token
  int _fileFd;
}
@end

@implementation MDWatchers

- (instancetype)initWithStatePath:(NSString *)statePath onChange:(void (^)(void))onChange {
  if ((self = [super init])) { _statePath = [statePath copy]; _onChange = [onChange copy]; _fileFd = -1; }
  return self;
}

- (void)start {
  [self armFileWatch];
  __weak MDWatchers *weak = self;
  // Slow fallback (covers externally-initiated starts when the agent is disabled).
  _timerSrc = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
  dispatch_source_set_timer(_timerSrc, dispatch_time(DISPATCH_TIME_NOW, 60*NSEC_PER_SEC), 60*NSEC_PER_SEC, 5*NSEC_PER_SEC);
  dispatch_source_set_event_handler(_timerSrc, ^{ MDWatchers *me = weak; if (me && me->_onChange) me->_onChange(); });
  dispatch_resume(_timerSrc);
  // Refresh on wake.
  _wakeObserver = [[[NSWorkspace sharedWorkspace] notificationCenter]
      addObserverForName:NSWorkspaceDidWakeNotification
      object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        MDWatchers *me = weak; if (me && me->_onChange) me->_onChange();
      }];
}

- (void)dealloc {
  if (_fileSrc) dispatch_source_cancel(_fileSrc);
  if (_procSrc) dispatch_source_cancel(_procSrc);
  if (_timerSrc) dispatch_source_cancel(_timerSrc);
  if (_fileFd >= 0) close(_fileFd);
  if (_wakeObserver) [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:_wakeObserver];
}

- (void)armFileWatch {
  if (_fileSrc) { dispatch_source_cancel(_fileSrc); _fileSrc = nil; }
  if (_fileFd >= 0) { close(_fileFd); _fileFd = -1; }
  // Ensure the file exists so we can open it; the watch re-arms on delete.
  [[NSFileManager defaultManager] createFileAtPath:_statePath contents:nil attributes:nil];
  _fileFd = open(_statePath.fileSystemRepresentation, O_EVTONLY);
  if (_fileFd < 0) return;
  _fileSrc = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, _fileFd,
      DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME, dispatch_get_main_queue());
  __weak MDWatchers *weak = self;
  dispatch_source_set_event_handler(_fileSrc, ^{
    MDWatchers *me = weak; if (!me) return;
    unsigned long f = dispatch_source_get_data(me->_fileSrc);
    if (me->_onChange) me->_onChange();
    if (f & (DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME)) [me armFileWatch]; // re-open
  });
  dispatch_resume(_fileSrc);
}

- (void)watchVmxPid:(pid_t)pid {
  if (_procSrc) { dispatch_source_cancel(_procSrc); _procSrc = nil; }
  if (pid <= 0) return;
  _procSrc = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)pid,
      DISPATCH_PROC_EXIT, dispatch_get_main_queue());
  __weak MDWatchers *weak = self;
  dispatch_source_set_event_handler(_procSrc, ^{
    MDWatchers *me = weak; if (!me) return;
    // Stop watching this pid BEFORE notifying. _onChange re-enters refresh -> watchVmxPid:, which
    // cancels+nils _procSrc; doing that first and then touching me->_procSrc here would call
    // dispatch_source_cancel(NULL) -> crash. Snapshot the source, clear the ivar, cancel the
    // snapshot, then notify (the re-entrant watchVmxPid: now sees a nil _procSrc and no-ops).
    dispatch_source_t src = me->_procSrc;
    me->_procSrc = nil;
    if (src) dispatch_source_cancel(src);
    if (me->_onChange) me->_onChange();
  });
  dispatch_resume(_procSrc);
}

@end
