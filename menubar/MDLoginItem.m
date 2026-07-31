#import "MDLoginItem.h"
#import <CoreServices/CoreServices.h>

@implementation MDLoginItem

+ (NSURL *)appURL { return [NSBundle mainBundle].bundleURL; }

+ (LSSharedFileListItemRef)findItemInList:(LSSharedFileListRef)list {
  if (!list) return NULL;
  UInt32 seed = 0;
  CFArrayRef items = LSSharedFileListCopySnapshot(list, &seed);
  LSSharedFileListItemRef found = NULL;
  NSURL *want = [self appURL];
  for (CFIndex i = 0; items && i < CFArrayGetCount(items); i++) {
    LSSharedFileListItemRef it = (LSSharedFileListItemRef)CFArrayGetValueAtIndex(items, i);
    CFURLRef u = NULL;
    if (LSSharedFileListItemResolve(it, 0, &u, NULL) == noErr && u) {
      if ([(__bridge NSURL *)u isEqual:want]) { found = (LSSharedFileListItemRef)CFRetain(it); CFRelease(u); break; }
      CFRelease(u);
    }
  }
  if (items) CFRelease(items);
  return found; // +1 retained (or NULL); CALLER MUST CFRelease
}

+ (void)setEnabled:(BOOL)enabled {
  LSSharedFileListRef list = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
  if (!list) return;
  LSSharedFileListItemRef existing = [self findItemInList:list];
  if (enabled && !existing) {
    LSSharedFileListItemRef added = LSSharedFileListInsertItemURL(list, kLSSharedFileListItemLast,
        NULL, NULL, (__bridge CFURLRef)[self appURL], NULL, NULL);
    if (added) CFRelease(added);
  } else if (!enabled && existing) {
    LSSharedFileListItemRemove(list, existing);
  }
  if (existing) CFRelease(existing);
  CFRelease(list);
}

@end
